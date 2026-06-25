import SwiftUI

struct TextEditorView: View {
    let item: FileItem
    let provider: any StorageProvider

    @State private var text: String = ""
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var hasChanges: Bool = false
    @State private var showingDiscardAlert: Bool = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let language: String?

    init(item: FileItem, provider: any StorageProvider) {
        self.item = item
        self.provider = provider
        self.language = FileTypeDetector.syntaxLanguage(for: item.fileExtension)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorMessage {
                    ContentUnavailableView("Cannot Open File", systemImage: "doc.text.magnifyingglass", description: Text(err))
                } else {
                    editorArea
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if hasChanges {
                            showingDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!hasChanges || isSaving)
                }
            }
            .alert("Discard Changes?", isPresented: $showingDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
        }
        .task { await loadContent() }
    }

    private var editorArea: some View {
        ScrollView {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 400)
                .padding()
                .onChange(of: text) { hasChanges = true }
        }
    }

    private func loadContent() async {
        isLoading = true
        defer { isLoading = false }

        // Try to read content if it's a local file
        if let data = try? Data(contentsOf: item.url),
           let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            text = content
        } else {
            // Download from remote provider
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(item.name)
            do {
                try await provider.download(item: item, to: tmpURL, progress: { _ in })
                if let data = try? Data(contentsOf: tmpURL),
                   let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                    text = content
                } else {
                    errorMessage = "File contains binary data and cannot be displayed as text."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        guard let data = text.data(using: .utf8) else { return }
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(item.name)
        do {
            try data.write(to: tmpURL)
            _ = try await provider.upload(from: tmpURL, to: (item.path as NSString).deletingLastPathComponent, progress: { _ in })
            hasChanges = false
        } catch {
            errorMessage = error.localizedDescription
        }
        try? FileManager.default.removeItem(at: tmpURL)
    }
}
