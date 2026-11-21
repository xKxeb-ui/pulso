import CryptoKit
import Foundation

/// Local, append-only record of media keys confirmed by the backup server.
/// Keep one instance on the coordinator's single-writer MainActor.
struct MediaBackupLog {
    private let logURL: URL
    private let scopeHash: String
    private var recordedHashes: Set<String>
    private var validFileLength: UInt64

    init(destination: URL, device: String) throws {
        let fileManager = FileManager.default
        let supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = supportDirectory.appendingPathComponent("mediaBackup", isDirectory: true)
        try self.init(destination: destination, device: device, directory: directory)
    }

    init(destination: URL, device: String, directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var scopeData = Data("Pulso.MediaBackup.scope.v1".utf8)
        Self.appendField(Data(destination.absoluteString.utf8), to: &scopeData)
        Self.appendField(Data(device.utf8), to: &scopeData)
        let scopeHash = Self.sha256Hex(scopeData)
        let logURL = directory.appendingPathComponent("\(scopeHash).log", isDirectory: false)

        if !fileManager.fileExists(atPath: logURL.path) {
            let created = fileManager.createFile(atPath: logURL.path, contents: Data())
            guard created || fileManager.fileExists(atPath: logURL.path) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }

        let loaded = try Self.load(fileURL: logURL)
        self.logURL = logURL
        self.scopeHash = scopeHash
        self.recordedHashes = loaded.hashes
        self.validFileLength = loaded.validLength
    }

    func contains(_ key: String) -> Bool {
        recordedHashes.contains(Self.resourceHash(key))
    }

    /// Returns the same server upload ID after relaunch for this key, device,
    /// and destination. Only a digest of each input contributes to the UUID.
    func uploadID(for key: String) -> UUID {
        var idData = Data("Pulso.MediaBackup.upload-id.v1".utf8)
        Self.appendField(Data(scopeHash.utf8), to: &idData)
        Self.appendField(Data(Self.resourceHash(key).utf8), to: &idData)

        var bytes = Array(SHA256.hash(data: idData).prefix(16))
        // RFC 9562 version 8 custom UUID, with the RFC variant bits set.
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Call only after the server confirms the upload. A trailing incomplete
    /// write is removed before appending so it can never count as success.
    mutating func record(_ key: String) throws {
        let hash = Self.resourceHash(key)
        guard !recordedHashes.contains(hash) else { return }

        let line = Data((hash + "\n").utf8)
        let handle = try FileHandle(forUpdating: logURL)
        do {
            try handle.truncate(atOffset: validFileLength)
            try handle.seek(toOffset: validFileLength)
            try handle.write(contentsOf: line)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        recordedHashes.insert(hash)
        validFileLength += UInt64(line.count)
    }

    private static func load(fileURL: URL) throws -> (hashes: Set<String>, validLength: UInt64) {
        let data = try Data(contentsOf: fileURL)
        var hashes = Set<String>()
        var lineStart = 0

        for index in data.indices where data[index] == 0x0a {
            let lineBytes = data[lineStart..<index]
            if let line = String(bytes: lineBytes, encoding: .ascii), isSHA256Hex(line) {
                hashes.insert(line)
            }
            lineStart = index + 1
        }

        // Only newline-terminated hashes are committed entries. Any partial
        // tail is ignored here and truncated before the next append.
        return (hashes, UInt64(lineStart))
    }

    private static func resourceHash(_ key: String) -> String {
        sha256Hex(Data(key.utf8))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", Int($0)) }.joined()
    }

    private static func isSHA256Hex(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    private static func appendField(_ field: Data, to data: inout Data) {
        let length = UInt64(field.count)
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((length >> shift) & 0xff))
        }
        data.append(field)
    }
}
