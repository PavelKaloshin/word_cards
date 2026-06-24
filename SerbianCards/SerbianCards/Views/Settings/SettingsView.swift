import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var configs: [AppConfig]

    @State private var showAPIKeyAlert: Bool = false
    @State private var newAPIKey: String = ""
    @State private var showDeleteConfirmation: Bool = false
    @State private var showExportSheet: Bool = false
    @State private var showImportPicker: Bool = false
    @State private var exportURL: URL?
    @State private var gptCheckStatus: String = ""
    @State private var isCheckingGPT: Bool = false

    private var config: AppConfig {
        configs.first ?? AppConfig()
    }

    var body: some View {
        NavigationStack {
            Form {
                // SRS Algorithm
                Section("Spaced Repetition") {
                    IntSlider(
                        label: "Mastery Threshold",
                        value: Binding(get: { config.masteredThreshold }, set: { config.masteredThreshold = $0; save() }),
                        range: 1...7
                    )
                    IntSlider(
                        label: "Review Session Size",
                        value: Binding(get: { config.reviewSessionSize }, set: { config.reviewSessionSize = $0; save() }),
                        range: 10...500,
                        step: 10
                    )
                    DoubleSlider(
                        label: "Error Factor Alpha",
                        value: Binding(get: { config.errorFactorAlpha }, set: { config.errorFactorAlpha = $0; save() }),
                        range: 1...10,
                        step: 0.5
                    )
                    DoubleSlider(
                        label: "Reverse Card Probability",
                        value: Binding(get: { config.reverseProbability }, set: { config.reverseProbability = $0; save() }),
                        range: 0...1,
                        step: 0.05
                    )
                    DoubleSlider(
                        label: "Forget Decay Alpha",
                        value: Binding(get: { config.forgetDecayAlpha }, set: { config.forgetDecayAlpha = $0; save() }),
                        range: 0...1,
                        step: 0.05
                    )
                    DoubleSlider(
                        label: "Hard Modifier",
                        value: Binding(get: { config.hardModifier }, set: { config.hardModifier = $0; save() }),
                        range: 0.1...1,
                        step: 0.1
                    )
                }

                // Typing Mode
                Section("Typing Mode") {
                    Toggle("Typing Mode Enabled", isOn: Binding(
                        get: { config.typingModeEnabled },
                        set: { config.typingModeEnabled = $0; save() }
                    ))
                    Toggle("Relaxed Diacritics", isOn: Binding(
                        get: { config.typingRelaxedDiacritics },
                        set: { config.typingRelaxedDiacritics = $0; save() }
                    ))
                    IntSlider(
                        label: "Hard Levenshtein Threshold",
                        value: Binding(get: { config.typingHardLevenshteinThreshold }, set: { config.typingHardLevenshteinThreshold = $0; save() }),
                        range: 1...5
                    )
                }

                // Content Generation
                Section("Content Generation") {
                    Toggle("Always Regenerate Example", isOn: Binding(
                        get: { config.alwaysRegenerateExample },
                        set: { config.alwaysRegenerateExample = $0; save() }
                    ))
                    ModelPicker(
                        label: "Text Model",
                        selection: Binding(get: { config.openaiModelText }, set: { config.openaiModelText = $0; save() }),
                        options: Self.textModelOptions
                    )
                    ModelPicker(
                        label: "Vision Model",
                        selection: Binding(get: { config.openaiModelVision }, set: { config.openaiModelVision = $0; save() }),
                        options: Self.textModelOptions
                    )
                    ModelPicker(
                        label: "Extract Model",
                        selection: Binding(get: { config.openaiModelExtract }, set: { config.openaiModelExtract = $0; save() }),
                        options: Self.fullModelOptions
                    )
                    ModelPicker(
                        label: "Image Model",
                        selection: Binding(get: { config.openaiModelImage }, set: { config.openaiModelImage = $0; save() }),
                        options: Self.imageModelOptions
                    )
                    TextRow(
                        label: "Image Search Language",
                        value: Binding(get: { config.imageSearchLang }, set: { config.imageSearchLang = $0; save() })
                    )
                    Picker("Default Alphabet", selection: Binding(
                        get: { config.defaultAlphabetView },
                        set: { config.defaultAlphabetView = $0; save() }
                    )) {
                        Text("Cyrillic").tag("cyr")
                        Text("Latin").tag("lat")
                        Text("Both").tag("both")
                    }
                }

                // API Key
                Section("API Key") {
                    if KeychainService.hasAPIKey() {
                        HStack {
                            Text("OpenAI API Key")
                            Spacer()
                            if let key = KeychainService.loadAPIKey(), key.count >= 2 {
                                Text("...\(String(key.suffix(4)))")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            Text("Configured")
                                .foregroundStyle(.green)
                        }
                        Button("Change API Key") {
                            showAPIKeyAlert = true
                        }
                        Button {
                            Task { await checkGPTConnection() }
                        } label: {
                            HStack {
                                Text("Test GPT Connection")
                                Spacer()
                                if isCheckingGPT {
                                    ProgressView()
                                } else if !gptCheckStatus.isEmpty {
                                    Text(gptCheckStatus)
                                        .font(.caption)
                                        .foregroundStyle(gptCheckStatus.starts(with: "OK") ? .green : .red)
                                }
                            }
                        }
                        .disabled(isCheckingGPT)
                        Button("Delete API Key", role: .destructive) {
                            KeychainService.deleteAPIKey()
                            appState.navigateTo(.apiKeyEntry)
                        }
                    } else {
                        Button("Set API Key") {
                            showAPIKeyAlert = true
                        }
                    }
                }

                // Data Management
                Section("Data") {
                    Button("Export Data") {
                        Task { await exportData() }
                    }
                    Button("Import Data") {
                        showImportPicker = true
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") {
                        appState.navigateTo(.home)
                    }
                }
            }
            .alert("API Key", isPresented: $showAPIKeyAlert) {
                SecureField("sk-...", text: $newAPIKey)
                Button("Save") {
                    if !newAPIKey.isEmpty {
                        KeychainService.saveAPIKey(newAPIKey)
                        newAPIKey = ""
                        appState.showToast("API key saved")
                    }
                }
                Button("Cancel", role: .cancel) { newAPIKey = "" }
            }
            .sheet(isPresented: $showExportSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.zip, .json]) { result in
                if case .success(let url) = result {
                    Task { await importData(from: url) }
                }
            }
        }
    }

    static let textModelOptions = [
        "gpt-5.4-mini", "gpt-5.4", "gpt-4.1-mini", "gpt-4.1", "gpt-4.1-nano",
    ]

    static let fullModelOptions = [
        "gpt-5.4", "gpt-5.4-mini", "gpt-4.1", "gpt-4.1-mini",
    ]

    static let imageModelOptions = [
        "gpt-image-2", "dall-e-3", "dall-e-2",
    ]

    private func save() {
        try? modelContext.save()
    }

    private func checkGPTConnection() async {
        await MainActor.run {
            isCheckingGPT = true
            gptCheckStatus = ""
        }
        do {
            let result = try await OpenAIService.shared.healthCheck(config: config)
            await MainActor.run {
                gptCheckStatus = "OK — \(result)"
                isCheckingGPT = false
            }
        } catch {
            await MainActor.run {
                gptCheckStatus = error.localizedDescription
                isCheckingGPT = false
            }
        }
    }

    private func exportData() async {
        do {
            let url = try await ExportImportService.shared.exportData(modelContext: modelContext)
            await MainActor.run {
                exportURL = url
                showExportSheet = true
            }
        } catch {
            await MainActor.run {
                appState.showToast("Export failed: \(error.localizedDescription)")
            }
        }
    }

    private func importData(from url: URL) async {
        do {
            try await ExportImportService.shared.importData(
                from: url,
                modelContext: modelContext,
                merge: true
            )
            await MainActor.run {
                appState.showToast("Import successful")
            }
        } catch {
            await MainActor.run {
                appState.showToast("Import failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Helper views

struct IntSlider: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value)")
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
        }
    }
}

struct DoubleSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.2f", value))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

struct ModelPicker: View {
    let label: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(options, id: \.self) { model in
                Text(model).tag(model)
            }
            if !options.contains(selection) {
                Text(selection).tag(selection)
            }
        }
    }
}

struct TextRow: View {
    let label: String
    @Binding var value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", text: $value)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 160)
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
