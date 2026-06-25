import Foundation
import SwiftUI

@Observable
@MainActor
final class SidebarViewModel {
    var bookmarks: [Bookmark] = []
    var pinnedFolders: [PinnedFolder] = []   // user-picked via UIDocumentPickerViewController
    var expandedSections: Set<String> = ["local", "cloud", "network", "bookmarks"]

    private let bookmarkKey = "atlas.bookmarks"
    private let pinnedFoldersKey = "atlas.pinnedFolders"

    init() {
        loadBookmarks()
        loadPinnedFolders()
    }

    var localLocations: [(name: String, path: String, icon: String)] {
        LocalFileProvider.sidebarLocations()
    }

    // MARK: - Pinned Folders (security-scoped bookmarks from UIDocumentPickerViewController)

    func addPinnedFolder(url: URL) {
        guard !pinnedFolders.contains(where: { $0.path == url.path }) else { return }
        // On iOS, persist access with minimalBookmark (no security-scoped bookmark needed)
        let bookmarkData = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let folder = PinnedFolder(name: url.lastPathComponent, path: url.path, bookmarkData: bookmarkData)
        pinnedFolders.append(folder)
        savePinnedFolders()
    }

    func removePinnedFolder(at offsets: IndexSet) {
        pinnedFolders.remove(atOffsets: offsets)
        savePinnedFolders()
    }

    func removePinnedFolder(path: String) {
        pinnedFolders.removeAll { $0.path == path }
        savePinnedFolders()
    }

    func resolveURL(for folder: PinnedFolder) -> URL? {
        guard let data = folder.bookmarkData else {
            return URL(fileURLWithPath: folder.path)
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return URL(fileURLWithPath: folder.path) }
        if isStale, let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil),
           let idx = pinnedFolders.firstIndex(where: { $0.path == folder.path }) {
            pinnedFolders[idx].bookmarkData = fresh
            savePinnedFolders()
        }
        return url
    }

    private func savePinnedFolders() {
        if let data = try? JSONEncoder().encode(pinnedFolders) {
            UserDefaults.standard.set(data, forKey: pinnedFoldersKey)
        }
    }

    private func loadPinnedFolders() {
        guard let data = UserDefaults.standard.data(forKey: pinnedFoldersKey),
              let saved = try? JSONDecoder().decode([PinnedFolder].self, from: data) else { return }
        pinnedFolders = saved
    }

    // MARK: - Regular Bookmarks

    func addBookmark(item: FileItem) {
        guard !bookmarks.contains(where: { $0.path == item.path }) else { return }
        let bookmark = Bookmark(name: item.name, path: item.path, providerID: item.providerID, icon: item.isDirectory ? "folder.fill.badge.plus" : item.fileType.systemImage)
        bookmarks.append(bookmark)
        saveBookmarks()
    }

    func removeBookmark(at offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        saveBookmarks()
    }

    func removeBookmark(path: String) {
        bookmarks.removeAll { $0.path == path }
        saveBookmarks()
    }

    func isBookmarked(path: String) -> Bool {
        bookmarks.contains { $0.path == path }
    }

    func reorderBookmarks(from: IndexSet, to: Int) {
        bookmarks.move(fromOffsets: from, toOffset: to)
        saveBookmarks()
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }

    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey),
              let saved = try? JSONDecoder().decode([Bookmark].self, from: data) else { return }
        bookmarks = saved
    }
}

struct PinnedFolder: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let path: String
    var bookmarkData: Data?

    init(name: String, path: String, bookmarkData: Data?) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.bookmarkData = bookmarkData
    }
}

struct Bookmark: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let providerID: String
    let icon: String
    var createdAt: Date

    init(name: String, path: String, providerID: String, icon: String) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.providerID = providerID
        self.icon = icon
        self.createdAt = Date()
    }
}

@Observable
@MainActor
final class TransfersViewModel {
    static let shared = TransfersViewModel()
    var engine: FileOperationEngine { FileOperationEngine.shared }

    var activeOperations: [FileOperation] { engine.operations.filter { $0.isActive } }
    var completedOperations: [FileOperation] { engine.operations.filter { $0.status.isFinished } }
    var totalProgress: Double {
        let active = activeOperations
        guard !active.isEmpty else { return 0 }
        return active.map { $0.progress }.reduce(0, +) / Double(active.count)
    }
    var hasActive: Bool { !activeOperations.isEmpty }
}
