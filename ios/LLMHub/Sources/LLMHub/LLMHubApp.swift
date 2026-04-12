import Foundation
import SwiftUI
import UIKit

@main
struct LLMHubApp: App {
    @StateObject private var settings = AppSettings.shared

    init() {
        let line = "[LLMHub] App launched\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
        NSLog("[LLMHub] App launched")
        UISwitch.appearance().onTintColor = UIColor(ApolloPalette.accentStrong)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .environment(\.locale, settings.selectedLanguage.locale)
                .environment(\.layoutDirection, settings.selectedLanguage.isRTL ? .rightToLeft : .leftToRight)
                .task {
                    // Boot embedding / RAG if a model was previously selected.
                    await RagServiceManager.shared.initialize(modelId: settings.selectedEmbeddingModelId)
                }
        }
    }
}
