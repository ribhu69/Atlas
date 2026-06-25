import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum FileType: Hashable, Sendable {
    case directory
    case image
    case video
    case audio
    case pdf
    case document         // Word, Pages, RTF, etc.
    case spreadsheet      // Excel, Numbers, CSV
    case presentation     // PowerPoint, Keynote
    case archive          // zip, tar, gz, bz2, 7z, rar
    case code             // source code files
    case text             // plain text, markdown
    case font
    case executable
    case disk             // .dmg, .iso
    case database         // .sqlite, .db
    case unknown

    static func detect(from name: String, extension ext: String) -> FileType {
        switch ext {
        // Images
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif",
             "webp", "svg", "ico", "raw", "cr2", "nef", "arw", "dng", "avif":
            return .image
        // Video
        case "mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "3gp",
             "mpeg", "mpg", "ts", "mts", "m2ts", "vob":
            return .video
        // Audio
        case "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "wma", "aiff",
             "aif", "caf", "mid", "midi":
            return .audio
        // PDF
        case "pdf":
            return .pdf
        // Documents
        case "doc", "docx", "odt", "rtf", "pages", "wpd", "wps":
            return .document
        // Spreadsheets
        case "xls", "xlsx", "csv", "ods", "numbers", "tsv":
            return .spreadsheet
        // Presentations
        case "ppt", "pptx", "odp", "key":
            return .presentation
        // Archives
        case "zip", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "7z", "rar",
             "z", "lz", "lzma", "cab", "ar", "cpio", "jar", "apk", "ipa":
            return .archive
        // Code / source files
        case "swift", "kt", "kts", "java", "py", "js", "ts", "jsx", "tsx",
             "c", "cpp", "cc", "cxx", "h", "hpp", "cs", "go", "rs", "rb",
             "php", "lua", "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd",
             "html", "htm", "css", "scss", "sass", "less", "xml", "json",
             "yaml", "yml", "toml", "ini", "cfg", "conf", "env", "gitignore",
             "dockerfile", "makefile", "gradle", "plist", "entitlements",
             "dart", "r", "m", "mm", "scala", "clj", "ex", "exs", "elm",
             "vue", "svelte", "astro", "tf", "hcl":
            return .code
        // Plain text
        case "txt", "md", "markdown", "rst", "log", "readme", "changelog",
             "license", "authors", "contributing", "notice":
            return .text
        // Fonts
        case "ttf", "otf", "woff", "woff2", "eot":
            return .font
        // Executables / Disk Images
        case "dmg", "iso", "img":
            return .disk
        // Database
        case "sqlite", "sqlite3", "db", "dbf", "realm":
            return .database
        default:
            if name.lowercased() == "makefile" || name.lowercased() == "dockerfile" {
                return .code
            }
            return .unknown
        }
    }

    var systemImage: String {
        switch self {
        case .directory:      return "folder.fill"
        case .image:          return "photo.fill"
        case .video:          return "film.fill"
        case .audio:          return "music.note"
        case .pdf:            return "doc.richtext.fill"
        case .document:       return "doc.text.fill"
        case .spreadsheet:    return "tablecells.fill"
        case .presentation:   return "rectangle.on.rectangle.fill"
        case .archive:        return "archivebox.fill"
        case .code:           return "chevron.left.forwardslash.chevron.right"
        case .text:           return "doc.plaintext.fill"
        case .font:           return "textformat"
        case .executable:     return "terminal.fill"
        case .disk:           return "opticaldiscdrive.fill"
        case .database:       return "cylinder.split.1x2.fill"
        case .unknown:        return "doc.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .directory:      return .blue
        case .image:          return .green
        case .video:          return .purple
        case .audio:          return .pink
        case .pdf:            return .red
        case .document:       return .blue
        case .spreadsheet:    return .green
        case .presentation:   return .orange
        case .archive:        return .brown
        case .code:           return .cyan
        case .text:           return .gray
        case .font:           return .indigo
        case .executable:     return .mint
        case .disk:           return .gray
        case .database:       return .teal
        case .unknown:        return .secondary
        }
    }

    var isPreviewable: Bool {
        switch self {
        case .image, .video, .audio, .pdf, .document, .text, .code, .spreadsheet, .presentation:
            return true
        default:
            return false
        }
    }

    var isEditable: Bool {
        switch self {
        case .text, .code:
            return true
        default:
            return false
        }
    }

    var isPlayable: Bool {
        switch self {
        case .video, .audio:
            return true
        default:
            return false
        }
    }
}

extension FileType: CustomStringConvertible {
    var description: String {
        switch self {
        case .directory:      return "Folder"
        case .image:          return "Image"
        case .video:          return "Video"
        case .audio:          return "Audio"
        case .pdf:            return "PDF Document"
        case .document:       return "Document"
        case .spreadsheet:    return "Spreadsheet"
        case .presentation:   return "Presentation"
        case .archive:        return "Archive"
        case .code:           return "Source Code"
        case .text:           return "Text File"
        case .font:           return "Font"
        case .executable:     return "Executable"
        case .disk:           return "Disk Image"
        case .database:       return "Database"
        case .unknown:        return "File"
        }
    }
}
