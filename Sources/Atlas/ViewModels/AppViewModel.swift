import Foundation
import SwiftUI

@Observable
@MainActor
final class AppViewModel {
    static let shared = AppViewModel()

    // Active providers registry
    var providers: [any StorageProvider] = []

    // Navigation
    var selectedProviderID: String? = "local"
    var showingConnections: Bool = false
    var showingTransfers: Bool = false
    var showingSearch: Bool = false

    // Clipboard for copy/paste
    var clipboard: ClipboardContents?

    // Error handling
    var currentError: AppError?
    var showingError: Bool = false

    // Settings
    var showHiddenFiles: Bool = false
    var defaultSortOption: SortOption = .nameAscending
    var defaultViewMode: ViewMode = .list
    var foldersFirst: Bool = true
    var confirmDelete: Bool = true

    private init() {
        setupDefaultProviders()
    }

    private func setupDefaultProviders() {
        // Local file provider is always present
        providers.append(LocalFileProvider())

        // iCloud (if available)
        let icloud = iCloudProvider()
        providers.append(icloud)

        // Load saved connections
        for config in ConnectionStore.shared.connections {
            if let provider = makeProvider(for: config) {
                providers.append(provider)
            }
        }
    }

    func makeProvider(for config: ConnectionConfig) -> (any StorageProvider)? {
        switch config.type {
        case .ftp, .ftps:
            return FTPProvider(config: config)
        case .webdav, .webdavs:
            return WebDAVProvider(config: config)
        case .sftp:
            return nil // SFTP: Phase 2
        case .smb:
            return nil // SMB: Phase 2
        case .iCloud:
            return iCloudProvider()
        case .googleDrive:
            return nil // Requires app-specific clientID; configure in Settings
        case .dropbox:
            return nil
        case .oneDrive:
            return nil
        }
    }

    func addProvider(_ provider: any StorageProvider) {
        providers.append(provider)
    }

    func removeProvider(id: String) {
        providers.removeAll { $0.id == id }
    }

    func provider(for id: String) -> (any StorageProvider)? {
        providers.first { $0.id == id }
    }

    func setError(_ error: Error) {
        currentError = AppError(message: error.localizedDescription)
        showingError = true
    }

    func setClipboard(items: [FileItem], mode: ClipboardMode) {
        clipboard = ClipboardContents(items: items, mode: mode)
    }

    func clearClipboard() {
        clipboard = nil
    }
}

enum ViewMode: String, CaseIterable {
    case list = "List"
    case grid = "Grid"
    case columns = "Columns"

    var systemImage: String {
        switch self {
        case .list:    return "list.bullet"
        case .grid:    return "square.grid.2x2"
        case .columns: return "rectangle.split.3x1"
        }
    }
}

enum ClipboardMode: Sendable {
    case copy, cut
}

struct ClipboardContents: Sendable {
    let items: [FileItem]
    let mode: ClipboardMode
    let sourceProviderID: String

    init(items: [FileItem], mode: ClipboardMode) {
        self.items = items
        self.mode = mode
        self.sourceProviderID = items.first?.providerID ?? "local"
    }
}

struct AppError: Identifiable {
    let id = UUID()
    let message: String
}
