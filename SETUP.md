# Atlas Files — Xcode Setup

## Xcode Project Setup

Since this is a Swift Package, you need to wrap it in an Xcode app target.

### Steps

1. Open Xcode → **File → New → Project**
2. Choose **iOS → App**
3. Set:
   - **Product Name**: Atlas Files
   - **Bundle ID**: `com.yourname.atlasfiles`
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Minimum iOS**: 17.0
4. Delete the generated `ContentView.swift` and `<AppName>App.swift` files
5. In Xcode → **File → Add Files to "Atlas Files"**, add all files from `Sources/Atlas/`

Alternatively: open `Package.swift` in Xcode directly (Xcode 15+) for a quick preview, but you'll need a full app target for device deployment.

---

## Required Xcode Capabilities & Info.plist Keys

In the **Signing & Capabilities** tab, add:
- **iCloud** → enable "CloudKit" and "iCloud Documents"
- **Background Modes** → enable "Background fetch" + "Background processing"
- **Network** → (automatic with iCloud)

In `Info.plist`, add:
```xml
<key>NSUbiquitousContainers</key>
<dict>
    <key>iCloud.com.yourname.atlasfiles</key>
    <dict>
        <key>NSUbiquitousContainerIsDocumentScopePublic</key>
        <true/>
        <key>NSUbiquitousContainerName</key>
        <string>Atlas Files</string>
        <key>NSUbiquitousContainerSupportedFolderLevels</key>
        <string>Any</string>
    </dict>
</dict>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
<key>UIFileSharingEnabled</key>
<true/>
<key>NSCameraUsageDescription</key>
<string>Used to capture photos to save to your files</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Used to import photos from your library</string>
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.atlas.files</string>
        </array>
    </dict>
</array>
```

---

## Cloud Provider API Keys

To enable cloud providers, you need to register apps with each service and add your API credentials:

### Google Drive
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a project → Enable Google Drive API
3. Create OAuth 2.0 credentials (iOS app)
4. In `AppViewModel.swift`, instantiate `GoogleDriveProvider(clientID: "YOUR_ID", clientSecret: "YOUR_SECRET")`

### Dropbox
1. Register at [Dropbox App Console](https://www.dropbox.com/developers/apps)
2. In `AppViewModel.swift`, instantiate `DropboxProvider(appKey: "YOUR_KEY", appSecret: "YOUR_SECRET")`

### OneDrive / Microsoft
1. Register at [Azure Portal](https://portal.azure.com)
2. In `AppViewModel.swift`, instantiate `OneDriveProvider(clientID: "YOUR_CLIENT_ID")`

---

## Architecture Overview

```
Atlas/
├── Models/
│   ├── FileItem         — Core file/folder model (name, size, date, type, permissions)
│   ├── FileType         — 15 file types with SF Symbol icons + colors
│   └── ConnectionConfig — Serializable server connection settings
│
├── Providers/           — Protocol-based storage backend
│   ├── StorageProvider  — Protocol: list, copy, move, delete, upload, download
│   ├── LocalFileProvider— On-device FileManager
│   ├── iCloudProvider   — NSFileCoordinator + NSMetadataQuery
│   ├── FTPProvider      — Full FTP/FTPS client on NWConnection (passive + active)
│   ├── WebDAVProvider   — WebDAV (PROPFIND/PUT/MOVE/COPY/DELETE)
│   └── Cloud/
│       ├── GoogleDriveProvider  — Drive REST API v3 + OAuth2
│       ├── DropboxProvider      — Dropbox API v2 + OAuth2
│       └── OneDriveProvider     — Microsoft Graph + OAuth2
│
├── Operations/
│   └── FileOperationEngine — Actor-based queue, max 3 concurrent, Background-safe
│
├── Archive/
│   └── ArchiveHandler   — ZIP create/extract, tar.gz extract, gzip decompress
│
├── FileTypes/
│   ├── FileTypeDetector — UTType-based MIME detection
│   └── FileActionProvider — Context menu actions per file type
│
├── ViewModels/          — @Observable / iOS 17
│   ├── AppViewModel     — Root state: providers, clipboard, settings
│   ├── FileBrowserViewModel — Directory listing, navigation, selection, ops
│   ├── SidebarViewModel — Bookmarks, sidebar sections
│   └── TransfersViewModel — Live transfer progress
│
└── Views/
    ├── ContentView      — NavigationSplitView (sidebar + content + detail)
    ├── Sidebar/         — iCloud/local/network/bookmarks sidebar
    ├── Browser/         — List + Grid views, context menus, swipe actions
    ├── Preview/         — QuickLook, text editor, AVKit media player
    ├── Operations/      — Transfer progress sheet
    └── Connections/     — Connection manager + add/edit FTP/WebDAV
```

## Key Features
- **Dual-pane support** (iPad) via NavigationSplitView detail column
- **Breadcrumb navigation** bar at bottom
- **Multi-select** with long press, batch operations
- **Swipe actions**: left = share/bookmark, right = delete/rename
- **Context menus** with type-specific actions + preview thumbnail
- **Background transfers** via FileOperationEngine actor (max 3 concurrent)
- **ZIP create/extract** using Compression framework (no dependencies)
- **FTP/FTPS** full implementation: MLSD listing, PASV/EPSV, binary transfer
- **WebDAV** PROPFIND XML parser, MOVE/COPY/MKCOL
- **iCloud** NSFileCoordinator-based safe writes, NSMetadataQuery search
- **OAuth2** via ASWebAuthenticationSession for Google/Dropbox/OneDrive
- **Keychain** token storage for cloud credentials
- **File info sheet** with permissions (rwx + octal), size, dates, path copy
- **Search** per-directory with live filter
- **Sort**: name/date/size/type, folders-first toggle
