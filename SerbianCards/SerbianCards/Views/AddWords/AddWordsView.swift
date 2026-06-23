import PhotosUI
import SwiftUI
import SwiftData

enum AddWordsTab: String, CaseIterable {
    case text = "Text"
    case photo = "Photo"
    case camera = "Camera"
}

struct AddWordsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: AddWordsTab = .text
    @State private var textInput: String = ""
    @State private var parseStatus: String = ""
    @State private var previewEntries: [PreviewEntry] = []
    @State private var showPreview: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveProgress: Double = 0
    @State private var saveStatusText: String = ""
    @State private var savedWords: [WordEntry] = []
    @State private var savingWords: [SavingWord] = []
    @State private var enrichmentTask: Task<Void, Never>?

    // Photo picker
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCamera: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Input Method", selection: $selectedTab) {
                    ForEach(AddWordsTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                ScrollView {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case .text:
                            textInputSection
                        case .photo:
                            photoInputSection
                        case .camera:
                            cameraInputSection
                        }

                        // Preview section
                        if showPreview {
                            previewSection
                        }

                        // Saved words grid
                        if !savedWords.isEmpty {
                            savedWordsSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Add Words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") {
                        appState.navigateTo(.home)
                    }
                }
            }
        }
    }

    // MARK: - Text input

    private var textInputSection: some View {
        VStack(spacing: 12) {
            TextEditor(text: $textInput)
                .frame(height: 200)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )

            HStack(spacing: 12) {
                Button("Parse with GPT") {
                    Task { await parseTextGPT() }
                }
                .buttonStyle(.borderedProminent)

                Button("Simple Split") {
                    parseTextNaive()
                }
                .buttonStyle(.bordered)
            }

            if !parseStatus.isEmpty {
                Text(parseStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Photo input

    private var photoInputSection: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("Select Photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task { await processPhoto(newItem) }
            }
        }
    }

    // MARK: - Camera input

    private var cameraInputSection: some View {
        VStack(spacing: 12) {
            Button {
                showCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showCamera) {
                CameraView { image in
                    showCamera = false
                    if let data = image.jpegData(compressionQuality: 0.8) {
                        Task { await processImageData(data) }
                    }
                }
            }
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview (\(previewEntries.filter(\.isSelected).count) selected)")
                .font(.headline)

            ForEach($previewEntries) { $entry in
                HStack(spacing: 8) {
                    Toggle("", isOn: $entry.isSelected)
                        .labelsHidden()

                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Word", text: $entry.word)
                            .textFieldStyle(.roundedBorder)
                        TextField("Translation", text: $entry.translation)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }

                    if entry.isDuplicate {
                        Text("duplicate")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Save button with progress
            VStack(spacing: 8) {
                Button {
                    enrichmentTask = Task { await saveSelectedWords() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save \(previewEntries.filter(\.isSelected).count) Words")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || previewEntries.filter(\.isSelected).isEmpty)

                if !savingWords.isEmpty {
                    VStack(spacing: 4) {
                        ProgressView(value: saveProgress)
                        Text(saveStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(savingWords) { item in
                            HStack(spacing: 6) {
                                statusIcon(item.status)
                                Text(item.word)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                statusLabel(item.status)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: SaveWordStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.secondary).font(.caption2)
        case .saved:
            Image(systemName: "checkmark.circle").foregroundStyle(.blue).font(.caption2)
        case .enriching:
            ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption2)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).font(.caption2)
        }
    }

    @ViewBuilder
    private func statusLabel(_ status: SaveWordStatus) -> some View {
        switch status {
        case .pending: Text("pending").font(.caption2).foregroundStyle(.secondary)
        case .saved: Text("saved").font(.caption2).foregroundStyle(.blue)
        case .enriching: Text("enriching...").font(.caption2).foregroundStyle(.orange)
        case .done: Text("done").font(.caption2).foregroundStyle(.green)
        case .failed(let msg): Text(msg).font(.caption2).foregroundStyle(.red).lineLimit(1)
        }
    }

    // MARK: - Saved words grid

    private var savedWordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Added (\(savedWords.count))")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                ForEach(savedWords, id: \.id) { word in
                    VStack(spacing: 4) {
                        if let image = MediaStorageService.loadImage(path: word.imagePath) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Text(word.wordCyr)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(word.translation)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Actions

    @Query private var existingWords: [WordEntry]

    private func parseTextGPT() async {
        guard !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        parseStatus = "Extracting with GPT..."
        do {
            let config = loadConfig()
            let entries = try await OpenAIService.shared.extractPhrasesFromText(
                text: textInput, config: config
            )
            let existingKeys = Set(existingWords.map {
                NormalizeService.normalizeForMatch($0.wordLat)
            })
            previewEntries = entries.map { entry in
                let key = NormalizeService.normalizeForMatch(entry.word)
                let isDup = existingKeys.contains(key)
                return PreviewEntry(
                    word: entry.word,
                    translation: entry.translation ?? "",
                    isDuplicate: isDup,
                    isSelected: !isDup
                )
            }
            let dupCount = previewEntries.filter(\.isDuplicate).count
            parseStatus = "Found: \(entries.count)\(dupCount > 0 ? ", duplicates: \(dupCount)" : "")"
            showPreview = true
        } catch {
            parseStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func parseTextNaive() {
        let lines = textInput.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        let existingKeys = Set(existingWords.map {
            NormalizeService.normalizeForMatch($0.wordLat)
        })

        let numberPrefix = /^\d+[\.\)\-]\s*/

        previewEntries = lines.compactMap { line in
            var cleaned = line.replacing(numberPrefix, with: "")
            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty else { return nil }

            let parts = cleaned.split(separator: "|", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let word = parts[0]
            let translation = parts.count > 1 ? parts[1] : ""
            let key = NormalizeService.normalizeForMatch(word)
            let isDup = existingKeys.contains(key)
            return PreviewEntry(
                word: word,
                translation: translation,
                isDuplicate: isDup,
                isSelected: !isDup
            )
        }
        let dupCount = previewEntries.filter(\.isDuplicate).count
        parseStatus = "Found: \(previewEntries.count)\(dupCount > 0 ? ", duplicates: \(dupCount)" : "")"
        showPreview = true
    }

    private func processPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            parseStatus = "Failed to load photo"
            return
        }
        await processImageData(data)
    }

    private func processImageData(_ data: Data) async {
        parseStatus = "Recognizing..."
        do {
            let config = loadConfig()
            let entries = try await OpenAIService.shared.extractWordsFromImage(
                imageData: data, config: config
            )
            let existingKeys = Set(existingWords.map {
                NormalizeService.normalizeForMatch($0.wordLat)
            })
            previewEntries = entries.map { entry in
                let key = NormalizeService.normalizeForMatch(entry.word)
                let isDup = existingKeys.contains(key)
                return PreviewEntry(
                    word: entry.word,
                    translation: entry.translation ?? "",
                    isDuplicate: isDup,
                    isSelected: !isDup
                )
            }
            parseStatus = "Found words: \(entries.count)"
            showPreview = true
        } catch {
            parseStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func saveSelectedWords() async {
        let selected = previewEntries.filter { $0.isSelected && !$0.word.isEmpty }
        guard !selected.isEmpty else { return }

        isSaving = true
        saveProgress = 0
        savedWords = []
        let config = loadConfig()

        // Step 1: Save all skeletons to SwiftData immediately
        var wordEntries: [WordEntry] = []
        var trackingItems: [SavingWord] = []
        for entry in selected {
            let (cyr, lat) = NormalizeService.toBoth(entry.word)
            let word = WordEntry(wordCyr: cyr, wordLat: lat, translation: entry.translation)
            modelContext.insert(word)
            wordEntries.append(word)
            trackingItems.append(SavingWord(id: word.id, word: entry.word, status: .saved))
        }
        do {
            try modelContext.save()
        } catch {
            parseStatus = "Save failed: \(error.localizedDescription)"
            isSaving = false
            return
        }
        savingWords = trackingItems
        saveStatusText = "Saved \(selected.count) words, enriching..."

        // Step 2: Enrich each word via individual Tasks (inherits @MainActor,
        // so @Model access is safe; network awaits free the main actor for UI)
        var enrichTasks: [(WordEntry, Task<Void, Never>)] = []
        for word in wordEntries {
            let task = Task {
                await self.enrichWord(word: word, config: config)
            }
            enrichTasks.append((word, task))
        }

        var completed = 0
        for (word, task) in enrichTasks {
            await task.value
            completed += 1
            saveProgress = Double(completed) / Double(selected.count)
            saveStatusText = "\(completed)/\(selected.count) enriched"
            savedWords.append(word)
            if let i = savingWords.firstIndex(where: { $0.id == word.id }) {
                if case .failed = savingWords[i].status {
                    // keep failed status
                } else {
                    savingWords[i].status = .done
                }
            }
        }

        isSaving = false
        showPreview = false
        textInput = ""
        appState.showToast("Added: \(savedWords.count)")
    }

    private func enrichWord(word: WordEntry, config: AppConfig) async {
        if let i = savingWords.firstIndex(where: { $0.id == word.id }) {
            savingWords[i].status = .enriching
        }

        do {
            let needsTranslation = word.translation.isEmpty
            let result = try await OpenAIService.shared.generateTranslationAndExample(
                word: word.wordCyr, config: config
            )
            if needsTranslation { word.translation = result.translation }
            word.exampleCyr = result.exampleCyr
            word.exampleLat = result.exampleLat
            word.exampleTranslation = result.exampleTranslation
            word.pos = result.pos
            word.verbGroup = result.verbGroup
            try? modelContext.save()

            if result.pos == "verb" {
                if let conj = try? await OpenAIService.shared.generateConjugations(
                    wordLat: word.wordLat, translation: word.translation, config: config
                ) {
                    word.conjugations = conj
                    try? modelContext.save()
                }
            }
        } catch {
            if let i = savingWords.firstIndex(where: { $0.id == word.id }) {
                savingWords[i].status = .failed("enrichment failed")
            }
        }

        if let path = await ImageSearchService.shared.searchAndSave(
            wordSerbian: word.wordLat,
            translation: word.translation,
            wordId: word.id,
            config: config,
            evalEnabled: config.imageEvalEnabled
        ) {
            word.imagePath = path
            try? modelContext.save()
        }
    }

    private func loadConfig() -> AppConfig {
        let descriptor = FetchDescriptor<AppConfig>()
        return (try? modelContext.fetch(descriptor))?.first ?? AppConfig()
    }
}

// MARK: - Preview entry model

struct PreviewEntry: Identifiable {
    let id = UUID()
    var word: String
    var translation: String
    var isDuplicate: Bool
    var isSelected: Bool
}

enum SaveWordStatus: Equatable {
    case pending
    case saved
    case enriching
    case done
    case failed(String)
}

struct SavingWord: Identifiable {
    let id: String
    let word: String
    var status: SaveWordStatus
}

// MARK: - Camera view

import UIKit

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void

        init(onCapture: @escaping (UIImage) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
