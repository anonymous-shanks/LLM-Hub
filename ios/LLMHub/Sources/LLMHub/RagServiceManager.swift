import Foundation
import RunAnywhere

// MARK: - RagServiceManager
// Singleton that manages the EmbeddingService lifecycle and RagService.
// Mirrors Android's RagServiceManager design.

@MainActor
final class RagServiceManager: ObservableObject {

    static let shared = RagServiceManager()

    // MARK: - Constants

    private let globalMemoryChatId = "__global_memory__"

    // MARK: - Published State

    @Published private(set) var isReady: Bool = false         // C embedding API loaded successfully
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var isReembedding: Bool = false

    /// RAG is configured (user enabled it + model selected) — does NOT require C API to be loaded.
    var isConfigured: Bool {
        AppSettings.shared.ragEnabled && AppSettings.shared.selectedEmbeddingModelId != nil
    }

    // MARK: - Private

    private let embeddingService = EmbeddingService()
    private let ragService = RagService()
    private let memoryStore = MemoryStore.shared
    private var initializedModelName: String? = nil
    private var populatedChatIds: Set<UUID> = []

    private init() {}

    // MARK: - Initialization

    /// Call this when the selected embedding model changes (from SettingsScreen or Settings).
    func initialize(modelId: String?) async {
        guard let modelId, !modelId.isEmpty else {
            await embeddingService.cleanup()
            isReady = false
            initializedModelName = nil
            statusMessage = AppSettings.shared.localized("embedding_disabled")
            return
        }

        // Skip if already loaded with the same model.
        if initializedModelName == modelId, await embeddingService.isInitialized {
            return
        }

        statusMessage = "Loading embedding model…"
        isReady = false

        // Locate the downloaded ONNX file.
        guard let model = ModelData.models.first(where: { $0.id == modelId }) else {
            statusMessage = "Embedding model not found in catalog."
            return
        }

        guard let modelDir = try? SimplifiedFileManager.shared.getModelFolderURL(modelId: modelId, framework: model.inferenceFramework) else {
            statusMessage = "Embedding model not downloaded."
            return
        }

        let onnxURL: URL
        if let found = (try? FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil))?.first(where: { $0.pathExtension.lowercased() == "onnx" }) {
            onnxURL = found
        } else {
            statusMessage = "ONNX file not found for embedding model."
            return
        }

        do {
            try await embeddingService.initialize(modelPath: onnxURL.path, modelName: model.name)
            initializedModelName = modelId
            isReady = true
            statusMessage = AppSettings.shared.localized("embedding_enabled")

            // Restore global memory chunks into RAG service.
            await restoreGlobalMemory()
        } catch {
            isReady = false
            statusMessage = "Failed to load embedding model: \(error.localizedDescription)"
        }
    }

    // MARK: - Per-chat documents

    /// Add a text document to the per-chat RAG pool, chunk + embed it.
    func addDocument(chatId: UUID, text: String, fileName: String) async -> Bool {
        guard isConfigured else { return false }
        let idStr = chatId.uuidString
        await ragService.addRawDocument(chatId: idStr, content: text, fileName: fileName)
        if isReady {
            await ragService.embedAllPending(chatId: idStr, service: embeddingService)
        }
        return true
    }

    /// Inject any global memory chunks into a specific chat (called on chat load).
    func populateChat(chatId: UUID) async {
        guard isReady, !populatedChatIds.contains(chatId) else { return }
        populatedChatIds.insert(chatId)
        await ragService.replicateChunks(fromChatId: globalMemoryChatId, toChatId: chatId.uuidString)
    }

    func clearChat(chatId: UUID) async {
        await ragService.clear(chatId: chatId.uuidString)
        populatedChatIds.remove(chatId)
    }

    func hasDocuments(chatId: UUID) async -> Bool {
        await ragService.hasDocuments(chatId: chatId.uuidString)
    }

    func documentCount(chatId: UUID) async -> Int {
        await ragService.documentCount(chatId: chatId.uuidString)
    }

    // MARK: - Search

    func searchRelevantContext(
        chatId: UUID,
        query: String,
        maxResults: Int = 3
    ) async -> [ContextChunk] {
        let idStr = chatId.uuidString
        let queryEmbedding = isReady ? (try? await embeddingService.embed(query)) : nil
        return await ragService.search(chatId: idStr, query: query, queryEmbedding: queryEmbedding, maxResults: maxResults)
    }

    func searchGlobalContext(query: String, maxResults: Int = 5, relaxed: Bool = false) async -> [ContextChunk] {
        let queryEmbedding = isReady ? (try? await embeddingService.embed(query)) : nil
        return await ragService.search(chatId: globalMemoryChatId, query: query, queryEmbedding: queryEmbedding, maxResults: maxResults, relaxedLexicalFallback: relaxed)
    }

    // MARK: - Global Memory

    func addGlobalMemory(text: String, fileName: String, metadata: String = "pasted") async -> Bool {
        guard isConfigured else { return false }
        await ragService.addRawDocument(chatId: globalMemoryChatId, content: text, fileName: fileName)
        if isReady {
            await ragService.embedAllPending(chatId: globalMemoryChatId, service: embeddingService)
        }
        let doc = MemoryDocument(fileName: fileName, content: text, metadata: metadata)
        memoryStore.appendDocument(doc)
        return true
    }

    func clearGlobalMemory() async {
        await ragService.clear(chatId: globalMemoryChatId)
        populatedChatIds.removeAll()
        memoryStore.clearAllDocuments()
    }

    func removeGlobalDocument(docId: String) async {
        memoryStore.removeDocument(id: docId)
        // Rebuild ragService global memory from remaining documents.
        await ragService.clear(chatId: globalMemoryChatId)
        populatedChatIds.removeAll()
        await restoreGlobalMemory()
    }

    func updateGlobalMemoryDocument(docId: String, newContent: String) async {
        guard var doc = memoryStore.documents.first(where: { $0.id == docId }) else { return }
        doc.content = newContent
        memoryStore.updateDocument(doc)
        // Rebuild ragService global memory with updated content.
        await ragService.clear(chatId: globalMemoryChatId)
        populatedChatIds.removeAll()
        await restoreGlobalMemory()
        if isReady {
            await ragService.embedAllPending(chatId: globalMemoryChatId, service: embeddingService)
        }
    }

    func globalDocumentCount() async -> Int {
        await ragService.documentCount(chatId: globalMemoryChatId)
    }

    // MARK: - Re-embedding (when model changes)

    func reembedGlobalMemory(newModelId: String) async {
        isReembedding = true
        defer { isReembedding = false }

        await initialize(modelId: newModelId)
        guard isReady else { return }

        await ragService.clear(chatId: globalMemoryChatId)
        populatedChatIds.removeAll()

        for doc in memoryStore.documents {
            await ragService.addRawDocument(chatId: globalMemoryChatId, content: doc.content, fileName: doc.fileName)
        }
        await ragService.embedAllPending(chatId: globalMemoryChatId, service: embeddingService)
    }

    // MARK: - Persistence Helpers

    private func restoreGlobalMemory() async {
        for doc in memoryStore.documents {
            await ragService.addRawDocument(chatId: globalMemoryChatId, content: doc.content, fileName: doc.fileName)
        }
        if isReady {
            await ragService.embedAllPending(chatId: globalMemoryChatId, service: embeddingService)
        }
    }
}

