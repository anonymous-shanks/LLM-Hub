import Foundation
import LlamaCPPRuntime
import RunAnywhere
#if canImport(UIKit)
import UIKit
import ImageIO
#endif

@MainActor
class LLMBackend: ObservableObject {
    static let shared = LLMBackend()
    private static let appleFoundationAliasId = "apple.foundation.system"
    private static let runAnywhereFoundationModelId = "foundation-models-default"

    @Published var isLoaded: Bool = false
    @Published var currentlyLoadedModel: String? = nil
    @Published var isBackendLoading: Bool = false
    @Published var loadedContextWindow: Int? = nil

    // Generation parameters
    var maxTokens: Int = 2048
    var contextWindow: Int = 2048
    var topK: Int = 64
    var topP: Float = 0.95
    var temperature: Float = 1.0
    var selectedBackend: String = "GPU"
    var enableVision: Bool = true
    var enableAudio: Bool = true
    var enableThinking: Bool = true

    private var isSDKInitialized = false
    private var areModelsRegistered = false
    private var loadedLLMModelId: String?
    private var loadedVLMModelId: String?
    private var loadedVLMProjectorPath: String?

    private init() {}

    private func legacyModelDirectory(for model: AIModel) -> URL? {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documentsDir.appendingPathComponent("models").appendingPathComponent(model.id)
    }

    private func hasAllRequiredFiles(in directory: URL, for model: AIModel) -> Bool {
        guard !model.requiredFileNames.isEmpty else { return false }
        return model.requiredFileNames.allSatisfy { fileName in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path)
        }
    }

    private func runAnywhereModelDirectory(for model: AIModel) -> URL? {
        try? SimplifiedFileManager.shared.getModelFolderURL(modelId: model.id, framework: model.inferenceFramework)
    }

    private func isModelAvailableLocally(_ model: AIModel) -> Bool {
        // Custom imported models store their file at model.url (an absolute file path).
        if model.source == "Custom", FileManager.default.fileExists(atPath: model.url) {
            return true
        }

        if RunAnywhere.isModelDownloaded(model.id, framework: model.inferenceFramework) {
            return true
        }

        if let runAnywhereDir = runAnywhereModelDirectory(for: model),
           FileManager.default.fileExists(atPath: runAnywhereDir.path),
           hasAllRequiredFiles(in: runAnywhereDir, for: model) {
            return true
        }

        if let legacyDir = legacyModelDirectory(for: model),
           FileManager.default.fileExists(atPath: legacyDir.path),
           hasAllRequiredFiles(in: legacyDir, for: model) {
            return true
        }

        return false
    }

    private func migrateLegacyModelIfNeeded(_ model: AIModel) throws -> Bool {
        if isModelAvailableLocally(model),
           let runAnywhereDir = runAnywhereModelDirectory(for: model),
           FileManager.default.fileExists(atPath: runAnywhereDir.path),
           hasAllRequiredFiles(in: runAnywhereDir, for: model) {
            return false
        }

        guard let legacyDir = legacyModelDirectory(for: model),
              FileManager.default.fileExists(atPath: legacyDir.path),
              hasAllRequiredFiles(in: legacyDir, for: model) else {
            return false
        }

        let destinationDir = try SimplifiedFileManager.shared.getModelFolderURL(modelId: model.id, framework: model.inferenceFramework)
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        for fileName in model.requiredFileNames {
            let sourceURL = legacyDir.appendingPathComponent(fileName)
            let destinationURL = destinationDir.appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }

        print("ℹ️ [LLMBackend] Migrated legacy model files for \(model.id)")
        return true
    }

    private func migrateCustomModelIfNeeded(_ model: AIModel) throws -> Bool {
        guard model.source == "Custom",
              let destinationDir = runAnywhereModelDirectory(for: model) else {
            return false
        }

        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        var copiedAny = false
        let mainSourceURL = URL(fileURLWithPath: model.url)
        let mainDestinationURL = destinationDir.appendingPathComponent(mainSourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: mainSourceURL.path),
           !FileManager.default.fileExists(atPath: mainDestinationURL.path) {
            try FileManager.default.copyItem(at: mainSourceURL, to: mainDestinationURL)
            copiedAny = true
        }

        for filePath in model.additionalFiles {
            let sourceURL = URL(fileURLWithPath: filePath)
            let destinationURL = destinationDir.appendingPathComponent(sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: sourceURL.path),
               !FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                copiedAny = true
            }
        }

        if copiedAny {
            print("ℹ️ [LLMBackend] Migrated custom model files into RunAnywhere storage for \(model.id)")
        }
        return copiedAny
    }

    private func filename(from url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.path.split(separator: "/").last.map(String.init) ?? url.lastPathComponent
    }

    private func loadedAIModel() -> AIModel? {
        guard let modelName = currentlyLoadedModel else { return nil }
        if let model = ModelData.allModels().first(where: { $0.name == modelName }) {
            return model
        }
        if modelName == "Apple Foundation Model" {
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                return AIModel(
                    id: "apple.foundation.system",
                    name: "Apple Foundation Model",
                    description: "On-device Apple Intelligence foundation model.",
                    url: "apple://foundation-model",
                    category: .text,
                    sizeBytes: 0,
                    source: "Apple",
                    supportsVision: false,
                    supportsAudio: false,
                    supportsThinking: true,
                    supportsGpu: true,
                    requirements: ModelRequirements(minRamGB: 8, recommendedRamGB: 8),
                    contextWindowSize: 4096,
                    modelFormat: .gguf,
                    additionalFiles: []
                )
            }
            #endif
        }
        return nil
    }

    private func framework(for model: AIModel) -> InferenceFramework {
        model.inferenceFramework
    }

    private func isAppleFoundationAlias(_ model: AIModel) -> Bool {
        model.id == Self.appleFoundationAliasId
    }

    private func activeRunAnywhereModelId(for model: AIModel) -> String {
        isAppleFoundationAlias(model) ? Self.runAnywhereFoundationModelId : model.id
    }

    private func listGGUFFiles(in directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { $0.pathExtension.lowercased() == "gguf" }
            .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
    }

    private func resolveModelGGUFPath(for model: AIModel) throws -> String {
        // Custom imported models store the GGUF path directly in model.url.
        if model.source == "Custom" {
            guard FileManager.default.fileExists(atPath: model.url) else {
                throw NSError(domain: "LLMBackend", code: -101, userInfo: [NSLocalizedDescriptionKey: "Custom model file missing: \(model.url)"])
            }
            return model.url
        }

        let folderURL = try SimplifiedFileManager.shared.getModelFolderURL(modelId: model.id, framework: model.inferenceFramework)
        let files = listGGUFFiles(in: folderURL)

        if let modelURL = URL(string: model.url) {
            let preferredFilename = filename(from: modelURL).lowercased()
            if let exact = files.first(where: { $0.lastPathComponent.lowercased() == preferredFilename }) {
                return exact.path
            }
        }

        if let quantTag = quantizationTag(from: model.name),
           let quantMatched = files.first(where: {
               let lower = $0.lastPathComponent.lowercased()
               return !lower.contains("mmproj") && lower.contains(quantTag)
           }) {
            return quantMatched.path
        }

        if let preferred = files.first(where: { !$0.lastPathComponent.lowercased().contains("mmproj") }) {
            return preferred.path
        }

        if let first = files.first {
            return first.path
        }

        throw NSError(domain: "LLMBackend", code: -101, userInfo: [NSLocalizedDescriptionKey: "Main GGUF file not found for model \(model.name)"])
    }

    private func quantizationTag(from modelName: String) -> String? {
        guard let leftParen = modelName.lastIndex(of: "("),
              let rightParen = modelName.lastIndex(of: ")"),
              leftParen < rightParen else {
            return nil
        }
        let tag = modelName[modelName.index(after: leftParen)..<rightParen]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return tag.isEmpty ? nil : tag
    }

    private func familyStem(from modelName: String) -> String {
        modelName
            .replacingOccurrences(of: "\\s*\\([^)]*\\)\\s*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func resolveVisionProjectorPath(for model: AIModel) -> String? {
        // Custom imported models store the vision projector path in additionalFiles.
        if model.source == "Custom" {
            let mmprojPath = model.additionalFiles.first {
                let lower = $0.lowercased()
                return lower.contains("mmproj") || lower.hasSuffix(".gguf")
            }
            if let path = mmprojPath, FileManager.default.fileExists(atPath: path) {
                return path
            }
            return nil
        }

        let stem = familyStem(from: model.name)
        let quantTag = quantizationTag(from: model.name)

        let allDependencyModels = ModelData.allModels().filter { $0.isDependencyOnly && $0.inferenceFramework == model.inferenceFramework }
        let candidates = allDependencyModels.filter { isModelAvailableLocally($0) }

        print("🔍 [LLMBackend] resolveVisionProjectorPath model=\(model.name) stem='\(stem)' quantTag=\(quantTag ?? "nil") totalDeps=\(allDependencyModels.count) downloadedDeps=\(candidates.count) downloadedNames=\(candidates.map(\.name))")

        let scored = candidates.compactMap { candidate -> (score: Int, path: String)? in
            let candidateName = candidate.name.lowercased()
            var score = 0

            if candidateName.contains(stem) {
                score += 3
            }
            if let quantTag,
               candidateName.contains(quantTag) || candidate.url.lowercased().contains(quantTag) {
                score += 3
            }
            if candidateName.contains("vision projector") || candidateName.contains("mmproj") {
                score += 1
            }

            guard let folderURL = try? SimplifiedFileManager.shared.getModelFolderURL(modelId: candidate.id, framework: candidate.inferenceFramework) else {
                return nil
            }

            let files = listGGUFFiles(in: folderURL)
            guard let mmprojFile = files.first(where: { $0.lastPathComponent.lowercased().contains("mmproj") }) ?? files.first else {
                return nil
            }

            return (score, mmprojFile.path)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.path < rhs.path
            }
            return lhs.score > rhs.score
        }

        print("🔍 [LLMBackend] resolveVisionProjectorPath scored=\(scored.map { "score=\($0.score) path=\($0.path)" })")
        // Require a minimum score of 3 (stem match) to avoid cross-family projector matches.
        // A score of 1 (only mmproj keyword) is not enough — the projector must belong to the same model family.
        return scored.first(where: { $0.score >= 3 })?.path
    }

    func isVisionProjectorAvailable(for model: AIModel) -> Bool {
        let path = resolveVisionProjectorPath(for: model)
        print("🔍 [LLMBackend] isVisionProjectorAvailable model=\(model.name) result=\(path != nil) path=\(path ?? "nil")")
        return path != nil
    }

    private func ensureVLMLoaded(for model: AIModel) async throws {
        let modelPath = try resolveModelGGUFPath(for: model)
        let mmprojPath = resolveVisionProjectorPath(for: model)

        guard let mmprojPath, !mmprojPath.isEmpty else {
            throw NSError(
                domain: "LLMBackend",
                code: -102,
                userInfo: [NSLocalizedDescriptionKey: "Vision projector (mmproj) is missing for \(model.name)"]
            )
        }

        let modelSummary = fileSummary(at: modelPath)
        let projectorSummary = fileSummary(at: mmprojPath)
        let modelHeader = ggufHeaderSummary(at: modelPath)
        let projectorHeader = ggufHeaderSummary(at: mmprojPath)

        print("ℹ️ [LLMBackend] VLM prepare model=\(model.id) main={\(modelSummary)} header={\(modelHeader)} mmproj={\(projectorSummary)} header={\(projectorHeader)}")

        guard modelHeader == "GGUF" else {
            throw NSError(
                domain: "LLMBackend",
                code: -103,
                userInfo: [NSLocalizedDescriptionKey: "Main model file is invalid: \(modelSummary) header=\(modelHeader)"]
            )
        }

        guard projectorHeader == "GGUF" else {
            throw NSError(
                domain: "LLMBackend",
                code: -104,
                userInfo: [NSLocalizedDescriptionKey: "Vision projector file is invalid: \(projectorSummary) header=\(projectorHeader)"]
            )
        }

        let shouldReload = !((await RunAnywhere.isVLMModelLoaded)
            && loadedVLMModelId == model.id
            && loadedVLMProjectorPath == mmprojPath)

        guard shouldReload else { return }

        if await RunAnywhere.isModelLoaded {
            do {
                try await RunAnywhere.unloadModel()
                loadedLLMModelId = nil
                print("ℹ️ [LLMBackend] Unloaded text LLM before VLM load to avoid duplicate model residency")
            } catch {
                print("❌ [LLMBackend] Failed to unload text LLM before VLM load: \(error)")
            }
        }

        await RunAnywhere.unloadVLMModel()
        do {
            try await RunAnywhere.loadVLMModel(modelPath, mmprojPath: mmprojPath, modelId: model.id, modelName: model.name)
        } catch {
            let details = "main={\(modelSummary)} header={\(modelHeader)} mmproj={\(projectorSummary)} header={\(projectorHeader)}"
            throw NSError(
                domain: "LLMBackend",
                code: -111,
                userInfo: [NSLocalizedDescriptionKey: "VLM load failed for \(model.name): \(error.localizedDescription). \(details)"]
            )
        }
        loadedVLMModelId = model.id
        loadedVLMProjectorPath = mmprojPath
    }

    private func ensureTextModelLoaded(for model: AIModel) async throws {
        if await RunAnywhere.isVLMModelLoaded {
            await RunAnywhere.unloadVLMModel()
            loadedVLMModelId = nil
            loadedVLMProjectorPath = nil
            print("ℹ️ [LLMBackend] Unloaded VLM before text generation to avoid duplicate model residency")
        }

        let shouldLoad = !((await RunAnywhere.isModelLoaded) && loadedLLMModelId == model.id)
        guard shouldLoad else { return }

        try await RunAnywhere.loadModel(model.id)
        loadedLLMModelId = model.id
    }

    private func fileSummary(at path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent

        guard FileManager.default.fileExists(atPath: path) else {
            return "\(name) missing"
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        let sizeLabel = size >= 0 ? formatter.string(fromByteCount: size) : "unknown"

        return "\(name) \(sizeLabel)"
    }

    private func ggufHeaderSummary(at path: String) -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else { return "unreadable" }
        defer {
            try? handle.close()
        }

        let data = handle.readData(ofLength: 4)
        guard data.count == 4, let header = String(data: data, encoding: .ascii) else {
            return "invalid"
        }
        return header
    }

#if canImport(UIKit)
    private func downsampledUIImage(from imageURL: URL, maxDimension: CGFloat = 1024) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, sourceOptions) else {
            return nil
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
#endif

    private func vlmImage(from imageURL: URL) -> VLMImage {
        #if canImport(UIKit)
        if let uiImage = downsampledUIImage(from: imageURL) {
            return VLMImage(image: uiImage)
        }
        #endif
        return VLMImage(filePath: imageURL.path)
    }

    private func modelMaxContextWindow(for model: AIModel) -> Int {
        let advertised = model.contextWindowSize > 0 ? model.contextWindowSize : 2048
        return max(1, advertised)
    }

    func clampedContextWindow(_ requested: Int, for model: AIModel) -> Int {
        min(max(1, requested), modelMaxContextWindow(for: model))
    }

    private func registerModel(_ model: AIModel, contextLengthOverride: Int? = nil) {
        // Custom models store an absolute file path in model.url — use file:// URL.
        let primaryURL: URL
        if model.source == "Custom" {
            primaryURL = URL(fileURLWithPath: model.url)
        } else {
            guard let url = URL(string: model.url) else { return }
            primaryURL = url
        }
        let contextLength = contextLengthOverride ?? model.contextWindowSize

        if model.additionalFiles.isEmpty {
            RunAnywhere.registerModel(
                id: model.id,
                name: model.name,
                url: primaryURL,
                framework: framework(for: model),
                modality: model.supportsVision ? .multimodal : .language,
                memoryRequirement: model.sizeBytes,
                supportsThinking: model.supportsThinking
            )
            return
        }

        let descriptors = model.allDownloadURLs.map {
            ModelFileDescriptor(url: $0, filename: filename(from: $0), isRequired: true)
        }

        RunAnywhere.registerMultiFileModel(
            id: model.id,
            name: model.name,
            files: descriptors,
            framework: framework(for: model),
            modality: model.supportsVision ? .multimodal : .language,
            memoryRequirement: model.sizeBytes
        )
    }

    private func ensureSDKReady() async throws {
        if !isSDKInitialized {
            try RunAnywhere.initialize(environment: .development)
            LlamaCPP.register()
            isSDKInitialized = true
        }

        if !areModelsRegistered {
            for model in ModelData.allModels() {
                registerModel(model)
            }
            areModelsRegistered = true
        }

        // Ensure model path APIs are configured before storage checks/migration.
        try await RunAnywhere.completeServicesInitialization()
    }

    func loadModel(_ model: AIModel) async throws {
        isBackendLoading = true
        defer { isBackendLoading = false }

        print("ℹ️ [LLMBackend] loadModel name=\(model.name) visionEnabled=\(enableVision) audioEnabled=\(enableAudio)")

        try await ensureSDKReady()
        let effectiveContext = clampedContextWindow(contextWindow, for: model)
        let runAnywhereModelId = activeRunAnywhereModelId(for: model)

        if isAppleFoundationAlias(model) {
            // Apple Foundation model is built in; no download or registration required.
            try await RunAnywhere.loadModel(runAnywhereModelId)
        } else {
            registerModel(model, contextLengthOverride: effectiveContext)
            await RunAnywhere.flushPendingRegistrations()
            _ = try? migrateCustomModelIfNeeded(model)
            _ = try? migrateLegacyModelIfNeeded(model)

            // Only local load here. Downloads are handled by the model download screen.
            guard isModelAvailableLocally(model) else {
                throw NSError(domain: "LLMBackend", code: -100, userInfo: [NSLocalizedDescriptionKey: "Model is not downloaded locally"])
            }

            // The C++ backend looks up context_length from the registry using the absolute
            // file path as the identifier. Re-register the model under its absolute path so
            // the C++ ID lookup succeeds and uses effectiveContext (e.g. 2048) instead of
            // auto-detecting a larger value (e.g. 4096) which causes OOM on <8 GB devices.
            if model.source == "Custom",
               let folderURL = runAnywhereModelDirectory(for: model),
               let ggufFile = listGGUFFiles(in: folderURL).first {
                let ggufURL = ggufFile
                let registeredModelInfo = ModelInfo(
                    id: runAnywhereModelId,
                    name: model.name,
                    category: model.supportsVision ? .multimodal : .language,
                    format: .gguf,
                    framework: framework(for: model),
                    downloadURL: ggufURL,
                    localPath: folderURL,
                    contextLength: effectiveContext,
                    supportsThinking: model.supportsThinking
                )
                try? await CppBridge.ModelRegistry.shared.save(registeredModelInfo)

                let pathModelInfo = ModelInfo(
                    id: ggufURL.path,
                    name: model.name,
                    category: model.supportsVision ? .multimodal : .language,
                    format: .gguf,
                    framework: framework(for: model),
                    downloadURL: ggufURL,
                    localPath: folderURL,
                    contextLength: effectiveContext,
                    supportsThinking: model.supportsThinking
                )
                try? await CppBridge.ModelRegistry.shared.save(pathModelInfo)
            } else if let folderURL = try? SimplifiedFileManager.shared.getModelFolderURL(
                modelId: runAnywhereModelId,
                framework: framework(for: model)
            ), let ggufFile = listGGUFFiles(in: folderURL).first {
                let registeredModelInfo = ModelInfo(
                    id: runAnywhereModelId,
                    name: model.name,
                    category: model.supportsVision ? .multimodal : .language,
                    format: .gguf,
                    framework: framework(for: model),
                    downloadURL: URL(string: model.url),
                    localPath: folderURL,
                    contextLength: effectiveContext,
                    supportsThinking: model.supportsThinking
                )
                try? await CppBridge.ModelRegistry.shared.save(registeredModelInfo)

                let pathModelInfo = ModelInfo(
                    id: ggufFile.path,
                    name: model.name,
                    category: model.supportsVision ? .multimodal : .language,
                    format: .gguf,
                    framework: framework(for: model),
                    downloadURL: URL(string: model.url),
                    localPath: folderURL,
                    contextLength: effectiveContext,
                    supportsThinking: model.supportsThinking
                )
                try? await CppBridge.ModelRegistry.shared.save(pathModelInfo)
            }

            try await RunAnywhere.loadModel(runAnywhereModelId)
        }

        isLoaded = true
        currentlyLoadedModel = model.name
        loadedContextWindow = effectiveContext
        loadedLLMModelId = runAnywhereModelId
        loadedVLMModelId = nil
        loadedVLMProjectorPath = nil
    }

    func unloadModel() {
        Task {
            do {
                try await RunAnywhere.unloadModel()
            } catch {
                print("❌ [LLMBackend] unloadModel error=\(error)")
            }
            await RunAnywhere.unloadVLMModel()
            await MainActor.run {
                self.isLoaded = false
                self.currentlyLoadedModel = nil
                self.loadedContextWindow = nil
                self.loadedLLMModelId = nil
                self.loadedVLMModelId = nil
                self.loadedVLMProjectorPath = nil
            }
        }
    }

    func generate(
        prompt: String,
        imageURL: URL? = nil,
        audioURL: URL? = nil,
        systemPrompt: String? = nil,
        maxTokensOverride: Int? = nil,
        stopSequences: [String] = [],
        onUpdate: @escaping (String, Int, Double) -> Void
    ) async throws {
        _ = imageURL
        _ = audioURL

        try await ensureSDKReady()

        let effectiveMaxTokens: Int = {
            if let override = maxTokensOverride { return max(1, override) }
            if let model = loadedAIModel() {
                let effectiveContext = clampedContextWindow(contextWindow, for: model)
                return min(max(1, maxTokens), effectiveContext)
            }
            return max(1, maxTokens)
        }()

        let options = LLMGenerationOptions(
            maxTokens: effectiveMaxTokens,
            temperature: temperature,
            topP: topP,
            stopSequences: stopSequences,
            streamingEnabled: true,
            systemPrompt: systemPrompt
        )

        if let imageURL,
           enableVision,
           let model = loadedAIModel(),
           model.supportsVision,
           isVisionProjectorAvailable(for: model) {
            try await ensureVLMLoaded(for: model)

            let image = vlmImage(from: imageURL)
            let streamResult = try await RunAnywhere.processImageStream(
                image,
                prompt: prompt,
                maxTokens: Int32(effectiveMaxTokens),
                temperature: temperature,
                topP: topP
            )

            var currentOutput = ""
            for try await token in streamResult.stream {
                currentOutput += token
                onUpdate(currentOutput, 0, 0)
            }

            let result = try await streamResult.metrics.value
            onUpdate(currentOutput, result.completionTokens, result.tokensPerSecond)
            return
        }

        if let model = loadedAIModel(), model.id == Self.appleFoundationAliasId || loadedLLMModelId == Self.runAnywhereFoundationModelId {
            // Foundation models may not stream in exact per-token order; generate non-stream and emulate incremental updates for UX.
            let result = try await RunAnywhere.generate(prompt, options: options)
            let fullText = result.text

            var currentOutput = ""
            let tokens = fullText.split(separator: " ", omittingEmptySubsequences: false)
            for (index, token) in tokens.enumerated() {
                if index > 0 { currentOutput += " " }
                currentOutput += String(token)
                onUpdate(currentOutput, result.tokensUsed, result.tokensPerSecond)
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms for smoother perception
            }

            if currentOutput.isEmpty {
                onUpdate(fullText, result.tokensUsed, result.tokensPerSecond)
            }
            return
        }

        if let model = loadedAIModel() {
            try await ensureTextModelLoaded(for: model)
        }

        print("ℹ️ [LLMBackend] generate visionEnabled=\(enableVision) audioEnabled=\(enableAudio) images=0 videos=0")

        let streamResult = try await RunAnywhere.generateStream(prompt, options: options)
        var currentOutput = ""

        for try await token in streamResult.stream {
            currentOutput += token
            onUpdate(currentOutput, 0, 0)
        }

        let result = try await streamResult.result.value
        onUpdate(currentOutput, result.tokensUsed, result.tokensPerSecond)
    }
}
