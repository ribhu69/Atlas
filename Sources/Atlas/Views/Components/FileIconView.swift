import SwiftUI

struct FileIconView: View {
    let item: FileItem
    let size: CGFloat

    var body: some View {
        ZStack {
            if item.fileType == .image {
                AsyncImage(url: item.url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
                } placeholder: {
                    iconFallback
                }
            } else {
                iconFallback
            }
        }
        .frame(width: size, height: size)
    }

    private var iconFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.15)
                .fill(item.fileType.accentColor.opacity(0.15))
                .frame(width: size, height: size)

            Image(systemName: item.fileType.systemImage)
                .font(.system(size: size * 0.45))
                .foregroundStyle(item.fileType.accentColor)
        }
    }
}

// MARK: - Info View

struct FileInfoView: View {
    let item: FileItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            FileIconView(item: item, size: 72)
                            Text(item.name)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Details") {
                    InfoRow(label: "Type", value: item.fileType.description)
                    if !item.isDirectory {
                        InfoRow(label: "Size", value: item.formattedSize)
                    }
                    InfoRow(label: "Path", value: item.path)
                    if let date = item.modificationDate {
                        InfoRow(label: "Modified", value: item.formattedAbsoluteDate)
                    }
                    if !item.fileExtension.isEmpty {
                        InfoRow(label: "Extension", value: ".\(item.fileExtension)")
                    }
                }

                if let permissions = item.permissions {
                    Section("Permissions") {
                        InfoRow(label: "Symbolic", value: permissions.symbolicString)
                        InfoRow(label: "Octal", value: "0\(permissions.octalString)")
                        InfoRow(label: "Owner", value: permissions.owner.rwxString)
                        InfoRow(label: "Group", value: permissions.group.rwxString)
                        InfoRow(label: "Others", value: permissions.other.rwxString)
                    }
                }

                Section {
                    Button {
                        UIPasteboard.general.string = item.path
                    } label: {
                        Label("Copy Path", systemImage: "link")
                    }
                    Button {
                        UIPasteboard.general.string = item.name
                    } label: {
                        Label("Copy Name", systemImage: "doc.on.doc")
                    }
                }
            }
            .navigationTitle("File Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.trailing)
                .font(.caption)
        }
    }
}

// MARK: - Activity View (Share Sheet)

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
