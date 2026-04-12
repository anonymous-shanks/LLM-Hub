import Foundation

// MARK: - MemoryChunk
// A single persisted chunk of global memory (mirrors Android's MemoryChunkEmbedding).

struct MemoryChunk: Codable, Identifiable, Sendable {
    let id: UUID
    let fileName: String
    let content: String
    let chunkIndex: Int
    let embedding: [Float]?
    let addedAt: Date

    init(fileName: String, content: String, chunkIndex: Int, embedding: [Float]? = nil) {
        self.id = UUID()
        self.fileName = fileName
        self.content = content
        self.chunkIndex = chunkIndex
        self.embedding = embedding
        self.addedAt = Date()
    }
}

// MARK: - MemoryStore
// Persists global memory chunks to Documents/llmhub_memory.json.

@MainActor
final class MemoryStore: ObservableObject {

    static let shared = MemoryStore()

    @Published private(set) var chunks: [MemoryChunk] = []

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("llmhub_memory.json")
    }

    private init() {
        load()
    }

    // MARK: - Mutations

    func append(_ chunk: MemoryChunk) {
        chunks.append(chunk)
        save()
    }

    func appendAll(_ newChunks: [MemoryChunk]) {
        chunks.append(contentsOf: newChunks)
        save()
    }

    func clearAll() {
        chunks.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([MemoryChunk].self, from: data) {
            chunks = decoded
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(chunks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
