import Foundation
import UniformTypeIdentifiers
import QuickLook

final class FileTypeDetector {

    static func utType(for item: FileItem) -> UTType? {
        if item.isDirectory { return .folder }
        let ext = item.fileExtension
        return UTType(filenameExtension: ext) ?? UTType(mimeType: mimeType(for: ext))
    }

    static func mimeType(for ext: String) -> String {
        let map: [String: String] = [
            "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png",
            "gif": "image/gif", "webp": "image/webp", "svg": "image/svg+xml",
            "mp4": "video/mp4", "mov": "video/quicktime", "mkv": "video/x-matroska",
            "mp3": "audio/mpeg", "m4a": "audio/mp4", "flac": "audio/flac",
            "wav": "audio/wav", "ogg": "audio/ogg",
            "pdf": "application/pdf",
            "zip": "application/zip", "tar": "application/x-tar",
            "gz": "application/gzip", "7z": "application/x-7z-compressed",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "ppt": "application/vnd.ms-powerpoint",
            "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "json": "application/json", "xml": "application/xml",
            "html": "text/html", "css": "text/css", "js": "text/javascript",
            "txt": "text/plain", "md": "text/markdown",
            "swift": "text/x-swift", "py": "text/x-python"
        ]
        return map[ext.lowercased()] ?? "application/octet-stream"
    }

    static func isQuickLookPreviewable(_ item: FileItem) -> Bool {
        guard let utType = utType(for: item) else { return false }
        // QLPreviewController can handle these
        return utType.conforms(to: .image)
            || utType.conforms(to: .pdf)
            || utType.conforms(to: .audio)
            || utType.conforms(to: .video)
            || utType.conforms(to: .text)
            || utType.conforms(to: .spreadsheet)
            || utType.conforms(to: .presentation)
            || utType.conforms(to: .wordProcessingDocument)
    }

    static func syntaxLanguage(for ext: String) -> String? {
        let map: [String: String] = [
            "swift": "swift", "py": "python", "js": "javascript",
            "ts": "typescript", "jsx": "jsx", "tsx": "tsx",
            "html": "html", "css": "css", "json": "json",
            "xml": "xml", "yaml": "yaml", "yml": "yaml",
            "sh": "bash", "bash": "bash", "zsh": "bash",
            "c": "c", "cpp": "cpp", "h": "c", "hpp": "cpp",
            "java": "java", "kt": "kotlin", "rs": "rust",
            "go": "go", "rb": "ruby", "php": "php",
            "md": "markdown", "sql": "sql", "r": "r",
            "dart": "dart", "scala": "scala", "lua": "lua"
        ]
        return map[ext.lowercased()]
    }

    static func thumbnailURL(for item: FileItem) async -> URL? {
        guard item.fileType == .image || item.fileType == .video else { return nil }
        return item.url
    }
}
