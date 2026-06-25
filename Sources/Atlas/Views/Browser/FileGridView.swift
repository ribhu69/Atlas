import SwiftUI

struct FileGridView: View {
    @State var vm: FileBrowserViewModel
    let onAction: (BrowserAction, FileItem) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(vm.filteredItems) { item in
                    FileGridItemView(item: item, isSelected: vm.selectedItems.contains(item))
                        .onTapGesture {
                            if vm.isSelecting {
                                vm.toggleSelection(of: item)
                            } else {
                                onAction(.open, item)
                            }
                        }
                        .onLongPressGesture {
                            vm.isSelecting = true
                            vm.selectedItems.insert(item)
                        }
                        .contextMenu {
                            gridContextMenu(for: item)
                        } preview: {
                            FileContextPreview(item: item)
                        }
                }
            }
            .padding()
        }
        .animation(.default, value: vm.filteredItems.map { $0.id })
    }

    @ViewBuilder
    private func gridContextMenu(for item: FileItem) -> some View {
        if item.isDirectory {
            Button { onAction(.open, item) } label: { Label("Open", systemImage: "folder") }
        } else {
            if item.fileType.isPlayable {
                Button { onAction(.play, item) } label: { Label("Play", systemImage: "play.fill") }
            }
            Button { onAction(.preview, item) } label: { Label("Quick Look", systemImage: "eye") }
        }
        Divider()
        Button { onAction(.rename, item) } label: { Label("Rename", systemImage: "pencil") }
        Button { onAction(.copyTo, item) } label: { Label("Copy", systemImage: "doc.on.doc") }
        Button { onAction(.moveTo, item) } label: { Label("Move", systemImage: "folder.badge.plus") }
        Button { onAction(.share, item) } label: { Label("Share", systemImage: "square.and.arrow.up") }
        Button { onAction(.info, item) } label: { Label("Get Info", systemImage: "info.circle") }
        Divider()
        Button(role: .destructive) { onAction(.delete, item) } label: { Label("Delete", systemImage: "trash") }
    }
}

struct FileGridItemView: View {
    let item: FileItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                FileIconView(item: item, size: 60)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .background(Color.white, in: Circle())
                        .offset(x: 4, y: -4)
                }
            }

            Text(item.displayName)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            if !item.isDirectory {
                Text(item.formattedSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 100)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }
}
