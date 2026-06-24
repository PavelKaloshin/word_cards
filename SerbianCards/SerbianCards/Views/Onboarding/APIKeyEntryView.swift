import SwiftUI

struct APIKeyEntryView: View {
    @Environment(AppState.self) private var appState
    @State private var apiKey: String = ""
    @State private var showError: Bool = false
    @State private var isSaving: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "key.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("OpenAI API Key")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Enter your OpenAI API key to enable word enrichment, translations, and image generation.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 32)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if showError {
                    Text("Please enter a valid API key starting with \"sk-\"")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    saveKey()
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save & Continue")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                .disabled(apiKey.isEmpty || isSaving)

                Spacer()
                Spacer()
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("sk-") else {
            showError = true
            return
        }
        showError = false
        isSaving = true
        let saved = KeychainService.saveAPIKey(trimmed)
        isSaving = false
        if saved {
            appState.navigateTo(.home)
        } else {
            showError = true
        }
    }
}
