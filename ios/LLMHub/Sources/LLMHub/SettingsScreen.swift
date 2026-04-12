import SwiftUI
import RunAnywhere

// MARK: - Settings Screen (mirroring Android SettingsScreen.kt)
struct SettingsScreen: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.openURL) var openURL

    var onNavigateBack: () -> Void
    var onNavigateToModels: () -> Void

    @State private var showLanguageDialog = false
    @State private var showMemoryDialog = false
    @State private var memoryPasteText = ""
    @State private var showMemoryDocPicker = false
    @State private var showMemoryClearConfirm = false
    @State private var memoryStatusMessage: String? = nil
    @StateObject private var ragManager = RagServiceManager.shared

    var body: some View {
        ZStack {
            ApolloLiquidBackground()

            List {
                // MARK: Models Section
                Section {
                    SettingsRow(
                        icon: "square.and.arrow.down.fill",
                        iconColor: ApolloPalette.accentStrong,
                        titleKey: "download_models",
                        subtitleKey: "browse_download_models"
                    ) {
                        onNavigateToModels()
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                    .listRowBackground(Color.clear)
                } header: {
                    SectionHeader(titleKey: "models", icon: "cpu")
                }

                // MARK: RAG / Embedding Section
                Section {
                    // Embedding model selector
                    EmbeddingModelSelectorRow(onNavigateToModels: onNavigateToModels)
                        .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                        .listRowBackground(Color.clear)

                    // RAG toggle
                    SettingsToggleRow(
                        icon: "doc.text.magnifyingglass",
                        iconColor: ApolloPalette.accentStrong,
                        title: settings.localized("rag_enabled"),
                        subtitle: settings.selectedEmbeddingModelId != nil
                            ? settings.localized("ai_can_reference_documents")
                            : settings.localized("no_embedding_model_selected"),
                        isOn: Binding(
                            get: { settings.ragEnabled && settings.selectedEmbeddingModelId != nil },
                            set: { newValue in
                                guard settings.selectedEmbeddingModelId != nil else { return }
                                settings.ragEnabled = newValue
                                if !newValue { settings.memoryEnabled = false }
                            }
                        )
                    )
                    .disabled(settings.selectedEmbeddingModelId == nil)
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                    .listRowBackground(Color.clear)

                    // Memory toggle (requires RAG)
                    SettingsToggleRow(
                        icon: "brain",
                        iconColor: ApolloPalette.accentStrong,
                        title: settings.localized("memory"),
                        subtitle: settings.ragEnabled && settings.selectedEmbeddingModelId != nil
                            ? settings.localized("memory_description_enabled")
                            : settings.localized("memory_requires_rag"),
                        isOn: Binding(
                            get: { settings.memoryEnabled && settings.ragEnabled && settings.selectedEmbeddingModelId != nil },
                            set: { newValue in
                                guard settings.ragEnabled && settings.selectedEmbeddingModelId != nil else { return }
                                settings.memoryEnabled = newValue
                            }
                        )
                    )
                    .disabled(!(settings.ragEnabled && settings.selectedEmbeddingModelId != nil))
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                    .listRowBackground(Color.clear)

                    // Memory manager row (only when memory enabled)
                    if settings.memoryEnabled && settings.ragEnabled {
                        SettingsRow(
                            icon: "tray.full",
                            iconColor: ApolloPalette.accentStrong,
                            titleKey: "manage_memory",
                            subtitleKey: "manage_memory_subtitle"
                        ) {
                            showMemoryDialog = true
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    SectionHeader(titleKey: "embedding_models", icon: "link.circle")
                }

                // MARK: Appearance Section
                Section {
                    SettingsToggleRow(
                        icon: "speaker.wave.2.fill",
                        iconColor: ApolloPalette.accentStrong,
                        title: settings.localized("auto_readout"),
                        subtitle: settings.localized("auto_readout_description"),
                        isOn: $settings.autoReadoutEnabled
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                    .listRowBackground(Color.clear)

                    SettingsRow(
                        icon: "globe",
                        iconColor: ApolloPalette.accentStrong,
                        titleKey: "language",
                        subtitleString: settings.localized(settings.selectedLanguage.displayNameKey)
                    ) {
                        showLanguageDialog = true
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                    .listRowBackground(Color.clear)
                } header: {
                    SectionHeader(titleKey: "appearance", icon: "paintbrush")
                }

                // MARK: Information Section
                Section {
                    SettingsRow(
                        icon: "info.circle.fill",
                        iconColor: ApolloPalette.accentStrong,
                        titleKey: "about",
                        subtitleKey: "app_information_contact"
                    ) { }
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                    .listRowBackground(Color.clear)

                    SettingsRow(
                        icon: "doc.text.fill",
                        iconColor: ApolloPalette.accentStrong,
                        titleKey: "terms_of_service",
                        subtitleKey: "legal_terms_conditions"
                    ) { }
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                    .listRowBackground(Color.clear)
                } header: {
                    SectionHeader(titleKey: "information", icon: "info.circle")
                }

                // MARK: Source Code Section
                Section {
                    SettingsRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        iconColor: ApolloPalette.accentStrong,
                        titleKey: "github_repository",
                        subtitleKey: "view_source_contribute"
                    ) {
                        if let url = URL(string: "https://github.com/timmyy123/LLM-Hub") {
                            openURL(url)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                    .listRowBackground(Color.clear)
                } header: {
                    SectionHeader(titleKey: "source_code_section", icon: "curlybraces")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(settings.localized("feature_settings_title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    onNavigateBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(settings.localized("back"))
                    }
                }
            }
        }
        // Language Dialog
        .sheet(isPresented: $showLanguageDialog) {
            LanguagePickerSheet()
                .environmentObject(settings)
        }
        // Memory Manager Sheet
        .sheet(isPresented: $showMemoryDialog) {
            MemoryManagerSheet(onDismiss: { showMemoryDialog = false })
                .environmentObject(settings)
        }
        .onChange(of: settings.selectedEmbeddingModelId) { _, newId in
            Task {
                await RagServiceManager.shared.initialize(modelId: newId)
            }
        }
    }
}

// MARK: - Embedding Model Selector Row

private struct EmbeddingModelSelectorRow: View {
    @EnvironmentObject var settings: AppSettings
    let onNavigateToModels: () -> Void
    @State private var showPicker = false

    private var downloadedEmbeddingModels: [AIModel] {
        ModelData.models.filter { model in
            model.category == .embedding
                && RunAnywhere.isModelDownloaded(model.id, framework: model.inferenceFramework)
        }
    }

    private var selectedModel: AIModel? {
        guard let id = settings.selectedEmbeddingModelId else { return nil }
        return ModelData.models.first { $0.id == id }
    }

    var body: some View {
        Button {
            if downloadedEmbeddingModels.isEmpty {
                onNavigateToModels()
            } else {
                showPicker = true
            }
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [ApolloPalette.accentSoft, ApolloPalette.accentMuted], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.localized("embedding_model"))
                        .font(.subheadline).foregroundColor(.white)
                    Text(selectedModel?.name ?? settings.localized("no_embedding_model_selected"))
                        .font(.caption).foregroundColor(.white.opacity(0.65)).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold()).foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .confirmationDialog(settings.localized("select_embedding_model"), isPresented: $showPicker, titleVisibility: .visible) {
            ForEach(downloadedEmbeddingModels) { model in
                Button(model.name) {
                    settings.selectedEmbeddingModelId = model.id
                    settings.ragEnabled = true
                    Task {
                        await RagServiceManager.shared.initialize(modelId: model.id)
                    }
                }
            }
            if settings.selectedEmbeddingModelId != nil {
                Button(settings.localized("disable_embeddings"), role: .destructive) {
                    settings.selectedEmbeddingModelId = nil
                    settings.ragEnabled = false
                    settings.memoryEnabled = false
                }
            }
            Button(settings.localized("cancel"), role: .cancel) {}
        }
    }
}

// MARK: - Memory Manager Sheet

struct MemoryManagerSheet: View {
    @EnvironmentObject var settings: AppSettings
    let onDismiss: () -> Void

    @State private var pasteText = ""
    @State private var showDocPicker = false
    @State private var statusMessage: String? = nil
    @State private var showClearConfirm = false
    @State private var isSaving = false
    @StateObject private var memoryStore = MemoryStore.shared
    @StateObject private var ragManager = RagServiceManager.shared

    var body: some View {
        NavigationView {
            ZStack {
                ApolloLiquidBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        // Paste text field
                        VStack(alignment: .leading, spacing: 8) {
                            Text(settings.localized("paste_or_upload_to_memory"))
                                .font(.subheadline).foregroundColor(.white.opacity(0.8))
                            TextEditor(text: $pasteText)
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.16), lineWidth: 1))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal)

                        HStack(spacing: 12) {
                            // Upload file button
                            Button {
                                showDocPicker = true
                            } label: {
                                Label(settings.localized("upload_file"), systemImage: "doc.badge.plus")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                            }

                            // Save pasted text button
                            Button {
                                let trimmed = pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                isSaving = true
                                Task {
                                    let ok = await RagServiceManager.shared.addGlobalMemory(
                                        text: trimmed,
                                        fileName: settings.localized("paste_memory_placeholder")
                                    )
                                    await MainActor.run {
                                        isSaving = false
                                        statusMessage = ok
                                            ? settings.localized("memory_save_success")
                                            : settings.localized("memory_save_failed")
                                        if ok { pasteText = "" }
                                    }
                                }
                            } label: {
                                if isSaving {
                                    ProgressView().tint(.white)
                                } else {
                                    Label(settings.localized("save_to_memory"), systemImage: "brain")
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(ApolloPalette.accentStrong)
                            .clipShape(Capsule())
                            .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                        }
                        .padding(.horizontal)

                        // Status
                        if let msg = statusMessage {
                            Text(msg)
                                .font(.caption).foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal)
                        }

                        Divider().background(Color.white.opacity(0.12))

                        // Saved memories list
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(settings.localized("saved_memories"))
                                    .font(.headline).foregroundColor(.white)
                                Spacer()
                                if !memoryStore.chunks.isEmpty {
                                    Button {
                                        showClearConfirm = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red.opacity(0.8))
                                    }
                                }
                            }
                            .padding(.horizontal)

                            if memoryStore.chunks.isEmpty {
                                Text(settings.localized("no_memories"))
                                    .font(.caption).foregroundColor(.white.opacity(0.55))
                                    .padding(.horizontal)
                            } else {
                                let fileGroups = Dictionary(grouping: memoryStore.chunks, by: { $0.fileName })
                                ForEach(fileGroups.keys.sorted(), id: \.self) { fileName in
                                    let count = fileGroups[fileName]?.count ?? 0
                                    HStack {
                                        Image(systemName: "doc.text")
                                            .foregroundColor(ApolloPalette.accentStrong)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(fileName).font(.subheadline).foregroundColor(.white).lineLimit(1)
                                            Text(String(format: settings.localized("documents_available_format"), count))
                                                .font(.caption).foregroundColor(.white.opacity(0.6))
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal).padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle(settings.localized("manage_memory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.localized("done")) { onDismiss() }
                        .foregroundColor(.white)
                }
            }
            .confirmationDialog(settings.localized("memory_cleared"), isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button(settings.localized("memory_cleared"), role: .destructive) {
                    Task { await RagServiceManager.shared.clearGlobalMemory() }
                    statusMessage = settings.localized("memory_cleared")
                }
                Button(settings.localized("cancel"), role: .cancel) {}
            }
            .fileImporter(
                isPresented: $showDocPicker,
                allowedContentTypes: DocumentTextExtractor.supportedTypes,
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let fileName = url.lastPathComponent
                isSaving = true
                Task {
                    let text: String
                    do {
                        text = try DocumentTextExtractor.extract(from: url)
                    } catch {
                        await MainActor.run {
                            isSaving = false
                            statusMessage = error.localizedDescription
                        }
                        return
                    }
                    let ok = await RagServiceManager.shared.addGlobalMemory(text: text, fileName: fileName)
                    await MainActor.run {
                        isSaving = false
                        statusMessage = ok
                            ? settings.localized("memory_upload_success")
                            : settings.localized("memory_upload_failed")
                    }
                }
            }
        }
    }
}

// MARK: - Language Picker Sheet
struct LanguagePickerSheet: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            ApolloLiquidBackground()

            List {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        settings.selectedLanguage = lang
                        dismiss()
                    } label: {
                        HStack {
                            Text(settings.localized(lang.displayNameKey))
                                .foregroundColor(.white)
                                .environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight)
                            Spacer()
                            if settings.selectedLanguage == lang {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(ApolloPalette.accentStrong)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(settings.localized("select_language"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(settings.localized("done")) { dismiss() }
            }
        }
    }
}


// MARK: - Reusable Components

struct SectionHeader: View {
    @EnvironmentObject var settings: AppSettings
    let titleKey: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(ApolloPalette.accentStrong)
            Text(settings.localized(titleKey))
        }

        .font(.footnote.bold())
        .foregroundColor(.white.opacity(0.74))
        .textCase(nil)
    }
}

struct SettingsRow: View {
    @EnvironmentObject var settings: AppSettings
    let icon: String
    let iconColor: Color
    let titleKey: String
    var subtitleKey: String? = nil
    var subtitleString: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [ApolloPalette.accentSoft, ApolloPalette.accentMuted],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.localized(titleKey))
                        .font(.subheadline)
                        .foregroundColor(.white)
                    if let sk = subtitleKey {
                        Text(settings.localized(sk))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                    } else if let ss = subtitleString {
                        Text(verbatim: ss)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [ApolloPalette.accentSoft, ApolloPalette.accentMuted],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(ApolloPalette.accentStrong)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}
