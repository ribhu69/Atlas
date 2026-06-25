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
        let data = try Data(contentsOf: source)
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        var entries: [(dataOffset: Int, compressedSize: Int, uncompressedSize: Int, method: Int, name: String)] = []
        var offset = 0

        while offset + 30 <= data.count {
            guard data.zipU32LE(at: offset) == 0x04034b50 else { offset += 1; continue }
            let method = Int(data.zipU16LE(at: offset + 8))
            let compressedSize = Int(data.zipU32LE(at: offset + 18))
            let uncompressedSize = Int(data.zipU32LE(at: offset + 22))
            let nameLen = Int(data.zipU16LE(at: offset + 26))
            let extraLen = Int(data.zipU16LE(at: offset + 28))
            guard offset + 30 + nameLen <= data.count else { break }
            let nameBytes = data[(offset + 30)..<(offset + 30 + nameLen)]
            let name = String(data: nameBytes, encoding: .utf8) ?? String(data: nameBytes, encoding: .isoLatin1) ?? ""
            let dataOffset = offset + 30 + nameLen + extraLen
            entries.append((dataOffset, compressedSize, uncompressedSize, method, name))
            offset = dataOffset + compressedSize
        }

        for (i, entry) in entries.enumerated() {
            let name = entry.name
            guard !name.isEmpty else { continue }
            if name.hasSuffix("/") {
                try? fm.createDirectory(at: destination.appendingPathComponent(name), withIntermediateDirectories: true)
            } else {
                let fileURL = destination.appendingPathComponent(name)
                try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let end = min(entry.dataOffset + entry.compressedSize, data.count)
                let compData = Data(data[entry.dataOffset..<end])
                switch entry.method {
                case 0:
                    try compData.write(to: fileURL)
                case 8:
                    try zlibInflate(compData, windowBits: -15).write(to: fileURL)
                default:
                    break
                }
            }
            progress(Double(i + 1) / Double(max(entries.count, 1)))
        }
    }

    private func extractTarGZ(from source: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let compressed = try Data(contentsOf: source)
        let tarData = try zlibInflate(compressed, windowBits: 31)
        try parseTar(tarData, to: destination)
        progress(1.0)
    }

    private func parseTar(_ data: Data, to destination: URL) throws {
        let fm = FileManager.default
        var pos = 0
        var pendingLongName: String? = nil
        while pos + 512 <= data.count {
            if data[pos..<pos + 512].allSatisfy({ $0 == 0 }) { break }
            let rawName = String(bytes: data[pos..<pos + 100].prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
            let prefix = String(bytes: data[pos + 345..<min(pos + 500, data.count)].prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
            let typeFlag = data[pos + 156]
            let sizeStr = String(bytes: data[pos + 124..<pos + 136].prefix(while: { $0 != 0 }), encoding: .utf8)?.trimmingCharacters(in: .whitespaces) ?? "0"
            let fileSize = Int(sizeStr, radix: 8) ?? 0
            pos += 512
            let name: String
            if let ln = pendingLongName { name = ln; pendingLongName = nil }
            else if !prefix.isEmpty { name = prefix + "/" + rawName }
            else { name = rawName }
            switch typeFlag {
            case 48, 0:
                if !name.isEmpty {
                    let fu = destination.appendingPathComponent(name)
                    try? fm.createDirectory(at: fu.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let end = min(pos + fileSize, data.count)
                    try Data(data[pos..<end]).write(to: fu)
                }
            case 53:
                try? fm.createDirectory(at: destination.appendingPathComponent(name), withIntermediateDirectories: true)
            case 76:
                if fileSize > 0 {
                    let end = min(pos + fileSize, data.count)
                    pendingLongName = String(data: Data(data[pos..<end]), encoding: .utf8)?.trimmingCharacters(in: .init(charactersIn: "\0"))
                }
            default: break
            }
            pos += ((fileSize + 511) / 512) * 512
        }
    }

    private func zlibInflate(_ compressed: Data, windowBits: Int32) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ProviderError.operationFailed("zlib init failed")
        }
        defer { inflateEnd(&stream) }

        let inputBytes = [UInt8](compressed)
        var output = Data()
        var status: Int32 = Z_OK

        inputBytes.withUnsafeBufferPointer { inBuf in
            stream.next_in = UnsafeMutablePointer(mutating: inBuf.baseAddress!)
            stream.avail_in = uInt(inBuf.count)
            var chunk = [UInt8](repeating: 0, count: 65536)
            repeat {
                chunk.withUnsafeMutableBufferPointer { outBuf in
                    stream.next_out = outBuf.baseAddress!
                    stream.avail_out = uInt(outBuf.count)
                    status = inflate(&stream, Z_NO_FLUSH)
                    let produced = outBuf.count - Int(stream.avail_out)
                    if produced > 0 {
                        output.append(contentsOf: outBuf.prefix(produced))
                    }
                }
            } while status == Z_OK
        }

        guard status == Z_STREAM_END else {
            throw ProviderError.operationFailed("inflate failed with status \(status)")
        }
        return output
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
        let data = try Data(contentsOf: source)
        var entries: [ArchiveEntry] = []
        var offset = 0
        while offset + 30 <= data.count {
            let sig = data.zipU32LE(at: offset)
            if sig == 0x04034b50 {
                let compressedSize = Int(data.zipU32LE(at: offset + 18))
                let uncompressedSize = Int(data.zipU32LE(at: offset + 22))
                let nameLen = Int(data.zipU16LE(at: offset + 26))
                let extraLen = Int(data.zipU16LE(at: offset + 28))
                guard offset + 30 + nameLen <= data.count else { break }
                let nameBytes = data[(offset + 30)..<(offset + 30 + nameLen)]
                let name = String(data: nameBytes, encoding: .utf8) ?? String(data: nameBytes, encoding: .isoLatin1) ?? ""
                let ratio = uncompressedSize > 0 ? 1.0 - Double(compressedSize) / Double(uncompressedSize) : 0
                entries.append(ArchiveEntry(name: name, size: Int64(uncompressedSize), isDirectory: name.hasSuffix("/"), compressionRatio: ratio))
                offset += 30 + nameLen + extraLen + compressedSize
            } else if sig == 0x02014b50 || sig == 0x06054b50 {
                break
            } else {
                offset += 1
            }
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

    func zipU16LE(at index: Int) -> UInt16 {
        guard index + 2 <= count else { return 0 }
        return UInt16(self[index]) | (UInt16(self[index + 1]) << 8)
    }

    func zipU32LE(at index: Int) -> UInt32 {
        guard index + 4 <= count else { return 0 }
        return UInt32(self[index])
            | (UInt32(self[index + 1]) << 8)
            | (UInt32(self[index + 2]) << 16)
            | (UInt32(self[index + 3]) << 24)
    }
}

struct ArchiveEntry: Sendable {
    let name: String
    let size: Int64
    let isDirectory: Bool
    let compressionRatio: Double
}
