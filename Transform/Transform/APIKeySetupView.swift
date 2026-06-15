import SwiftUI

enum APIKeySetupPresentation: String, Identifiable {
    case startup
    case settings

    var id: String { rawValue }
}

struct APIKeySetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var errorMessage: String?
    @FocusState private var isKeyFocused: Bool

    let presentation: APIKeySetupPresentation
    let onSaved: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Anthropic API Key") {
                    SecureField("sk-ant-...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isKeyFocused)

                    Text("The key is stored in this device's Keychain. It is not written to the project or sent to GitHub.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(TFColor.danger)
                    }
                }

                Section {
                    Button("Save API Key") {
                        save()
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(presentation == .startup ? "Enable AI Features" : "API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                isKeyFocused = true
            }
        }
    }

    private func save() {
        do {
            try AnthropicAPIKeyStore.save(apiKey)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
