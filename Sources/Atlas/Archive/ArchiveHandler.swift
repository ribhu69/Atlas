import Foundation
import Compression

final class ArchiveHandler: Sendable {

    func compress(items: [FileItem], archiveName: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        let archiveName = archiveName.hasSuffix(".zip") ? archiveName : archiveName + ".zip"
        let archiveURL = tmpDir.appendingPathComponent(archiveName)

        try await Task.detached(priority: .userInitiated) {
            try self.createZIP(from: items.map { $0.url }, to: archiveURL, progress: progress)
        }.value

        return archiveURL
    }

    func decompress(archiveURL: URL, to destinationURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let ext = archiveURL.pathExtension.lowercased()
        try await Task.detached(priority: .userInitiated) {
            switch ext {
            case "zip":
                try self.extractZIP(from: archiveURL, to: destinationURL, progress: progress)
            case "gz", "tgz":
                if archiveURL.path.hasSuffix(".tar.gz") || ext == "tgz" {
                    try self.extractTarGZ(from: archiveURL, to: destinationURL, progress: progress)
                } else {
                    try self.decompressGzip(from: archiveURL, to: destinationURL, progress: progress)
                }
            default:
                throw ProviderError.unsupported("Archive format .\(ext) is not supported")
            }
        }.value
    }

    func listContents(of archiveURL: URL) async throws -> [ArchiveEntry] {
        let ext = archiveURL.pathExtension.lowercased()
        return try await Task.detached(priority: .userInitiated) {
            switch ext {
            case "zip":
                return try self.listZIPContents(of: archiveURL)
            default:
                return []
            }
        }.value
    }

    // MARK: - ZIP Implementation using Compression framework

    private func createZIP(from urls: [URL], to destination: URL, progress: @escaping @Sendable (Double) -> Void) throws {
        let fm = FileManager.default
        var allFiles: [(source: URL, relativePath: String)] = []

        for url in urls {
            if url.hasDirectoryPath {
                let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
                while let fileURL = enumerator?.nextObject() as? URL {
                    guard !(try fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false) else { continue }
                    let relative = url.lastPathComponent + "/" + fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
                    allFiles.append((fileURL, relative))
                }
            } else {
                allFiles.append((url, url.lastPathComponent))
            }
        }

        // Write local ZIP file format manually
        var centralDirectory = Data()
        var localFileData = Data()
        var offsets: [UInt32] = []
        let total = Double(allFiles.count)

        for (i, (src, relPath)) in allFiles.enumerated() {
            guard let fileData = try? Data(contentsOf: src) else { continue }
            offsets.append(UInt32(localFileData.count))

            let pathData = relPath.data(using: .utf8)!
            let crc = crc32(data: fileData)
            let compressed = compressDeflate(fileData) ?? fileData
            let useCompression = compressed.count < fileData.count
            let method: UInt16 = useCompression ? 8 : 0
            let compData = useCompression ? compressed : fileData

            // Local file header
            localFileData.append(zipLocalHeader(
                name: pathData,
                method: method,
                crc32: crc,
                compressedSize: UInt32(compData.count),
                uncompressedSize: UInt32(fileData.count)
            ))
            localFileData.append(compData)

            // Central directory entry
            centralDirectory.append(zipCentralEntry(
                name: pathData,
                method: method,
                crc32: crc,
                compressedSize: UInt32(compData.count),
                uncompressedSize: UInt32(fileData.count),
                offset: offsets[i]
            ))

            progress(Double(i + 1) / total * 0.9)
        }

        var result = Data()
        result.append(localFileData)
        let cdOffset = UInt32(result.count)
        result.append(centralDirectory)
        result.append(zipEndOfCentralDirectory(
            entryCount: UInt16(allFiles.count),
            cdSize: UInt32(centralDirectory.count),
            cdOffset: cdOffset
        ))

        try result.write(to: destination)
        progress(1.0)
    }

    private func extractZIP(from source: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        // Use Process to call unzip if available, fallback to manual parsing
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", source.path, "-d", destination.path]
        try process.run()
        process.waitUntilExit()
        progress(1.0)
    }

    private func extractTarGZ(from source: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", source.path, "-C", destination.path]
        try process.run()
        process.waitUntilExit()
        progress(1.0)
    }

    private func decompressGzip(from source: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) throws {
        let data = try Data(contentsOf: source)
        let destName = source.deletingPathExtension().lastPathComponent
        let destURL = destination.appendingPathComponent(destName)

        guard let decompressed = decompress(data: data, algorithm: COMPRESSION_ZLIB) else {
            throw ProviderError.operationFailed("Failed to decompress gzip file")
        }
        try decompressed.write(to: destURL)
        progress(1.0)
    }

    private func listZIPContents(of source: URL) throws -> [ArchiveEntry] {
        // Simplified: use `unzip -l` output parsing
        var entries: [ArchiveEntry] = []
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-l", source.path]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lines = output.components(separatedBy: "\n").dropFirst(3).dropLast(3)
        for line in lines {
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
            guard parts.count >= 4 else { continue }
            let name = parts[3...].joined(separator: " ")
            let size = Int64(parts[0]) ?? 0
            let isDir = name.hasSuffix("/")
            entries.append(ArchiveEntry(name: name, size: size, isDirectory: isDir, compressionRatio: 0))
        }
        return entries
    }

    // MARK: - Compression helpers

    private func compressDeflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var result = Data(count: data.count + 64)
        let written = result.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(
                    dst.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    dst.count,
                    src.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        result.count = written
        return result
    }

    private func decompress(data: Data, algorithm: compression_algorithm) -> Data? {
        var result = Data(count: data.count * 4)
        let written = result.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(
                    dst.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    dst.count,
                    src.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    nil,
                    algorithm
                )
            }
        }
        guard written > 0 else { return nil }
        result.count = written
        return result
    }

    private func crc32(data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            var b = crc ^ UInt32(byte)
            for _ in 0..<8 {
                if b & 1 != 0 { b = (b >> 1) ^ 0xEDB88320 }
                else { b >>= 1 }
            }
            crc = b
        }
        return crc ^ 0xFFFFFFFF
    }

    // MARK: - ZIP binary helpers

    private func zipLocalHeader(name: Data, method: UInt16, crc32: UInt32, compressedSize: UInt32, uncompressedSize: UInt32) -> Data {
        var d = Data()
        d.append(littleEndian32: 0x04034b50) // signature
        d.append(littleEndian16: 20)          // version needed
        d.append(littleEndian16: 0)           // flags
        d.append(littleEndian16: method)      // compression method
        d.append(littleEndian16: 0)           // mod time
        d.append(littleEndian16: 0)           // mod date
        d.append(littleEndian32: crc32)
        d.append(littleEndian32: compressedSize)
        d.append(littleEndian32: uncompressedSize)
        d.append(littleEndian16: UInt16(name.count))
        d.append(littleEndian16: 0)           // extra field length
        d.append(name)
        return d
    }

    private func zipCentralEntry(name: Data, method: UInt16, crc32: UInt32, compressedSize: UInt32, uncompressedSize: UInt32, offset: UInt32) -> Data {
        var d = Data()
        d.append(littleEndian32: 0x02014b50) // central dir signature
        d.append(littleEndian16: 0)           // version made by
        d.append(littleEndian16: 20)          // version needed
        d.append(littleEndian16: 0)           // flags
        d.append(littleEndian16: method)
        d.append(littleEndian16: 0)           // mod time
        d.append(littleEndian16: 0)           // mod date
        d.append(littleEndian32: crc32)
        d.append(littleEndian32: compressedSize)
        d.append(littleEndian32: uncompressedSize)
        d.append(littleEndian16: UInt16(name.count))
        d.append(littleEndian16: 0)           // extra field length
        d.append(littleEndian16: 0)           // comment length
        d.append(littleEndian16: 0)           // disk number start
        d.append(littleEndian16: 0)           // internal attrs
        d.append(littleEndian32: 0)           // external attrs
        d.append(littleEndian32: offset)
        d.append(name)
        return d
    }

    private func zipEndOfCentralDirectory(entryCount: UInt16, cdSize: UInt32, cdOffset: UInt32) -> Data {
        var d = Data()
        d.append(littleEndian32: 0x06054b50) // end of central dir signature
        d.append(littleEndian16: 0)           // disk number
        d.append(littleEndian16: 0)           // disk with central dir start
        d.append(littleEndian16: entryCount)  // entries on disk
        d.append(littleEndian16: entryCount)  // total entries
        d.append(littleEndian32: cdSize)
        d.append(littleEndian32: cdOffset)
        d.append(littleEndian16: 0)           // comment length
        return d
    }
}

private extension Data {
    mutating func append(littleEndian16 value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }
    mutating func append(littleEndian32 value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}

struct ArchiveEntry: Sendable {
    let name: String
    let size: Int64
    let isDirectory: Bool
    let compressionRatio: Double
}
