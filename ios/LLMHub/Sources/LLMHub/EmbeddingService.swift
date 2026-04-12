import CRACommons
import Foundation

// MARK: - EmbeddingService
// Wraps the RACommons rac_embeddings_service C API to generate
// float-vector embeddings from text using a GGUF embedding model.

actor EmbeddingService {

    // MARK: - State

    private var handle: rac_handle_t? = nil
    private(set) var isInitialized: Bool = false
    private(set) var currentModelName: String? = nil
    private(set) var embeddingDimension: Int = 0

    // MARK: - Init

    init() {}

    // MARK: - Lifecycle

    /// Initialize the embedding service and load a GGUF embedding model.
    func initialize(modelPath: String, modelName: String) throws {
        // Tear down any existing instance.
        if handle != nil {
            rac_embeddings_cleanup(handle)
            rac_embeddings_destroy(handle)
            handle = nil
            isInitialized = false
            embeddingDimension = 0
        }

        var newHandle: rac_handle_t? = nil
        let createResult = rac_embeddings_create(modelPath, &newHandle)
        guard createResult == RAC_SUCCESS, newHandle != nil else {
            throw EmbeddingError.initFailed("rac_embeddings_create failed: \(createResult)")
        }
        handle = newHandle

        // Initialize with the model path.
        let initResult = modelPath.withCString { pathPtr in
            rac_embeddings_initialize(handle, pathPtr)
        }
        guard initResult == RAC_SUCCESS else {
            rac_embeddings_destroy(handle)
            handle = nil
            throw EmbeddingError.modelLoadFailed("rac_embeddings_initialize failed: \(initResult)")
        }

        // Query dimension via service info if available; fallback to test embed.
        var info = rac_embeddings_info_t()
        if rac_embeddings_get_info(handle, &info) == RAC_SUCCESS && info.dimension > 0 {
            embeddingDimension = Int(info.dimension)
        } else if let testEmb = try? embedTest() {
            embeddingDimension = testEmb.count
        }

        isInitialized = true
        currentModelName = modelName
    }

    private func embedTest() throws -> [Float] {
        guard let h = handle else { return [] }
        return EmbeddingService.callEmbed(handle: h, text: "test")
    }

    // nonisolated: no actor-isolated storage touched → no "sending" across boundaries
    private nonisolated static func callEmbed(handle: rac_handle_t, text: String) -> [Float] {
        var result = rac_embeddings_result_t()
        var options = RAC_EMBEDDINGS_OPTIONS_DEFAULT
        let status = withUnsafePointer(to: &options) { opts in
            rac_embeddings_embed(handle, text, opts, &result)
        }
        guard status == RAC_SUCCESS, result.num_embeddings > 0,
              let embeddings = result.embeddings else {
            rac_embeddings_result_free(&result)
            return []
        }
        let dim = Int(embeddings[0].dimension)
        guard dim > 0, let data = embeddings[0].data else {
            rac_embeddings_result_free(&result)
            return []
        }
        let output = Array(UnsafeBufferPointer(start: data, count: dim))
        rac_embeddings_result_free(&result)
        return output
    }

    func cleanup() {
        guard handle != nil else { return }
        rac_embeddings_cleanup(handle)
        rac_embeddings_destroy(handle)
        handle = nil
        isInitialized = false
        currentModelName = nil
        embeddingDimension = 0
    }

    // MARK: - Embed

    /// Generate a dense float embedding for the given text.
    func embed(_ text: String) throws -> [Float] {
        guard isInitialized, let h = handle else {
            throw EmbeddingError.notInitialized
        }

        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1024))
        guard !trimmed.isEmpty else { return [] }

        let output = EmbeddingService.callEmbed(handle: h, text: trimmed)
        guard !output.isEmpty else {
            throw EmbeddingError.embeddingFailed("empty result")
        }
        return output
    }
}

// MARK: - Errors

enum EmbeddingError: Error, LocalizedError {
    case notInitialized
    case initFailed(String)
    case modelLoadFailed(String)
    case embeddingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized: return "Embedding service not initialized."
        case .initFailed(let m): return "Embedding init failed: \(m)"
        case .modelLoadFailed(let m): return "Model load failed: \(m)"
        case .embeddingFailed(let m): return "Embedding failed: \(m)"
        }
    }
}
