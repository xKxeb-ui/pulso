import CoreTransferable
import Foundation
import UniformTypeIdentifiers

final class PickedMedia: Transferable, Sendable {
    let url: URL
    let type: UTType
    private let directory: URL

    var isVideo: Bool { type.conforms(to: .movie) }
    var fileExtension: String { url.pathExtension }
    var contentType: String { type.preferredMIMEType ?? "application/octet-stream" }

    private init(copying source: URL, as category: UTType) throws {
        let suffix = source.pathExtension.lowercased()
        guard !suffix.isEmpty, suffix.count <= 10,
              suffix.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) }),
              let type = UTType(filenameExtension: suffix), type.conforms(to: category) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("pulso-media-\(UUID())", isDirectory: true)
        let copy = folder.appendingPathComponent("archivo").appendingPathExtension(suffix)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            try manager.copyItem(at: source, to: copy)
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
        self.directory = folder
        self.type = type
        self.url = copy
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            try Self(copying: received.file, as: .movie)
        }
        FileRepresentation(importedContentType: .image) { received in
            try Self(copying: received.file, as: .image)
        }
    }
}
