import Foundation
import SwiftUI

@Observable
@MainActor
final class FileBrowserViewModel {
    // Content
    var items: [FileItem] = []
    var isLoading: Bool = false
    var error: Error?

    // Navigation
    var currentPath: String
    var navigationStack: [String] = []
    var provider: any StorageProvider

    // Selection
    var selectedItems: Set<FileItem> = []
    var isSelecting: Bool = false

    // View options
    var sortOption: SortOption = .nameAscending
    var viewMode: ViewMode = .list
    var showHidden: Bool = false
    var searchQuery: String = ""

    // UI state
    var itemToRename: FileItem?
    var renameText: String = ""
    var itemToShowInfo: FileItem?
    var itemsToDelete: [FileItem] = []
    var showingDeleteConfirmation: Bool = false
    var itemForActions: FileItem?
    var showingNewFolderDialog: Bool = false
    var newFolderName: String = ""

    var filteredItems: [FileItem] {
        var result = items
        if !showHidden {
            result = result.filter { !$0.isHidden }
        }
        if !searchQuery.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        }
        return sortFileItems(result, by: sortOption, foldersFirst: true)
    }

    var hasSelection: Bool { !selectedItems.isEmpty }
    var selectionCount: Int { selectedItems.count }

    var pathComponents: [(name: String, path: String)] {
        var components: [(String, String)] = []
        var current = currentPath
        while !current.isEmpty && current != "/" {
            components.insert((URL(fileURLWithPath: current).lastPathComponent, current), at: 0)
            current = (current as NSString).deletingLastPathComponent
        }
        components.insert(("/", "/"), at: 0)
        return components
    }

    var canGoBack: Bool { !navigationStack.isEmpty }

    init(provider: any StorageProvider, path: String? = nil) {
        self.provider = provider
        self.currentPath = path ?? provider.rootPath
    }

    // MARK: - Navigation

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            if !provider.isConnected {
                try await provider.connect()
            }
            items = try await provider.listDirectory(at: currentPath)
        } catch {
            self.error = error
        }
    }

    func navigate(to item: FileItem) async {
        guard item.isDirectory else { return }
        navigationStack.append(currentPath)
        currentPath = item.path
        selectedItems.removeAll()
        isSelecting = false
        await load()
    }

    func navigate(toPath path: String) async {
        navigationStack.append(currentPath)
        currentPath = path
        selectedItems.removeAll()
        await load()
    }

    func goBack() async {
        guard let prev = navigationStack.popLast() else { return }
        currentPath = prev
        selectedItems.removeAll()
        await load()
    }

    func refresh() async {
        await load()
    }

    // MARK: - Selection

    func toggleSelection(of item: FileItem) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
    }

    func selectAll() {
        selectedItems = Set(filteredItems)
    }

    func deselectAll() {
        selectedItems.removeAll()
        isSelecting = false
    }

    // MARK: - File Operations

    func createFolder(named name: String) async {
        do {
            let newItem = try await provider.createDirectory(named: name, in: currentPath)
            items.append(newItem)
        } catch {
            self.error = error
        }
    }

    func rename(item: FileItem, to newName: String) async {
        do {
            let renamed = try await provider.rename(item: item, to: newName)
            if let idx = items.firstIndex(of: item) {
                items[idx] = renamed
            }
        } catch {
            self.error = error
        }
    }

    func delete(items: [FileItem]) async {
        let engine = FileOperationEngine.shared
        engine.delete(items: items, using: provider)
        self.items.removeAll { items.contains($0) }
        self.selectedItems.removeAll()
    }

    func paste(clipboard: ClipboardContents) async {
        guard let sourceProvider = AppViewModel.shared.provider(for: clipboard.sourceProviderID) else { return }
        let engine = FileOperationEngine.shared

        switch clipboard.mode {
        case .copy:
            engine.copy(items: clipboard.items, to: currentPath, using: sourceProvider)
        case .cut:
            engine.move(items: clipboard.items, to: currentPath, using: sourceProvider)
            AppViewModel.shared.clearClipboard()
        }
        // Refresh after a delay to show new items
        try? await Task.sleep(nanoseconds: 500_000_000)
        await load()
    }

    func download(items: [FileItem]) {
        FileOperationEngine.shared.download(items: items, using: provider)
    }

    func compress(items: [FileItem], name: String) {
        let op = FileOperation(kind: .compress(items: items, destinationPath: currentPath, archiveName: name), provider: provider)
        FileOperationEngine.shared.enqueue(op)
    }

    func decompress(item: FileItem) {
        let op = FileOperation(kind: .decompress(item: item, destinationPath: currentPath), provider: provider)
        FileOperationEngine.shared.enqueue(op)
    }
}
