import CryptoKit
import Foundation
import Photos
import UniformTypeIdentifiers

enum MediaLibrary {
    @MainActor
    static func fetch() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = true
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        return PHAsset.fetchAssets(with: options)
    }

    @MainActor
    static func isReadable(_ asset: PHAsset) -> Bool {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = true
        guard let current = PHAsset.fetchAssets(
            withLocalIdentifiers: [asset.localIdentifier], options: options
        ).firstObject else {
            return false
        }
        return !current.isHidden && isStandardMedia(current)
    }

    @MainActor
    static func resources(for asset: PHAsset) -> [Resource] {
        let available = PHAssetResource.assetResources(for: asset)
        let availableTypes = Set(available.map(\.type))
        let preferredTypes: [PHAssetResourceType]
        switch asset.mediaType {
        case .image:
            // Keep original image data, the Live Photo movie, and a RAW/alternate original.
            let photoType: PHAssetResourceType = availableTypes.contains(.photo) ? .photo : .fullSizePhoto
            var imageTypes = [photoType]
            if availableTypes.contains(.pairedVideo) {
                imageTypes.append(.pairedVideo)
            } else if availableTypes.contains(.fullSizePairedVideo) {
                imageTypes.append(.fullSizePairedVideo)
            }
            if availableTypes.contains(.alternatePhoto) {
                imageTypes.append(.alternatePhoto)
            }
            preferredTypes = imageTypes
        case .video:
            preferredTypes = [availableTypes.contains(.video) ? .video : .fullSizeVideo]
        default:
            return []
        }

        let selected = preferredTypes.flatMap { type in
            available.filter { $0.type == type }
        }

        return selected.enumerated().map { ordinal, resource in
            Resource(resource: resource, assetIdentifier: asset.localIdentifier, ordinal: ordinal)
        }
    }

    private static func isStandardMedia(_ asset: PHAsset) -> Bool {
        asset.mediaType == .image || asset.mediaType == .video
    }

    struct Resource {
        var key: String
        var isVideo: Bool

        private let resource: PHAssetResource

        fileprivate init(resource: PHAssetResource, assetIdentifier: String, ordinal: Int) {
            self.resource = resource
            let isVideoResource = resource.type == .video
                || resource.type == .fullSizeVideo
                || resource.type == .pairedVideo
                || resource.type == .fullSizePairedVideo
            self.isVideo = isVideoResource
                || UTType(resource.uniformTypeIdentifier)?.conforms(to: .movie) == true

            let material = [
                assetIdentifier,
                String(ordinal),
                String(resource.type.rawValue),
                resource.originalFilename
            ].joined(separator: "\u{0}")
            self.key = SHA256.hash(data: Data(material.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
        }

        func export() async throws -> ExportedFile {
            try Task.checkCancellation()

            let type = UTType(resource.uniformTypeIdentifier)
            let fileExtension = Self.safeExtension(for: resource, type: type)
            guard !fileExtension.isEmpty else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }

            let fileManager = FileManager.default
            let directory = fileManager.temporaryDirectory
                .appendingPathComponent("pulso-resource-\(UUID())", isDirectory: true)
            let url = directory.appendingPathComponent("resource").appendingPathExtension(fileExtension)

            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
                guard fileManager.createFile(atPath: url.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try Task.checkCancellation()

                let file = try FileHandle(forWritingTo: url)
                do {
                    try await ResourceDataWriter(resource: resource, file: file).write()
                    try Task.checkCancellation()
                    try file.close()
                } catch {
                    try? file.close()
                    throw error
                }

                return ExportedFile(
                    url: url,
                    directory: directory,
                    fileExtension: fileExtension,
                    contentType: type?.preferredMIMEType
                        ?? UTType(filenameExtension: fileExtension)?.preferredMIMEType
                        ?? "application/octet-stream",
                    isVideo: isVideo
                )
            } catch {
                try? fileManager.removeItem(at: directory)
                throw error
            }
        }

        private static func safeExtension(for resource: PHAssetResource, type: UTType?) -> String {
            let filenameExtension = (resource.originalFilename as NSString).pathExtension.lowercased()
            let candidates = [filenameExtension, type?.preferredFilenameExtension?.lowercased()]
            for candidate in candidates.compactMap({ $0 }) {
                guard !candidate.isEmpty, candidate.count <= 10,
                      candidate.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) }) else {
                    continue
                }
                return candidate
            }
            return ""
        }
    }

    final class ExportedFile {
        let url: URL
        let fileExtension: String
        let contentType: String
        let isVideo: Bool

        private let directory: URL

        fileprivate init(
            url: URL,
            directory: URL,
            fileExtension: String,
            contentType: String,
            isVideo: Bool
        ) {
            self.url = url
            self.directory = directory
            self.fileExtension = fileExtension
            self.contentType = contentType
            self.isVideo = isVideo
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

private final class ResourceDataWriter: @unchecked Sendable {
    private let manager = PHAssetResourceManager.default()
    private let resource: PHAssetResource
    private let file: FileHandle
    private let lock = NSLock()

    private var requestID: PHAssetResourceDataRequestID?
    private var continuation: CheckedContinuation<Void, Error>?
    private var isCancelled = false
    private var isFinished = false
    private var shouldCancelRequest = false

    init(resource: PHAssetResource, file: FileHandle) {
        self.resource = resource
        self.file = file
    }

    func write() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(continuation)
            }
        } onCancel: {
            cancel()
        }
    }

    private func start(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        let identifier = manager.requestData(
            for: resource,
            options: options,
            dataReceivedHandler: { [weak self] data in self?.receive(data) },
            completionHandler: { [weak self] error in self?.finish(error) }
        )
        register(identifier)
    }

    private func register(_ identifier: PHAssetResourceDataRequestID) {
        lock.lock()
        let shouldCancel = shouldCancelRequest
        if !isFinished && !shouldCancel {
            requestID = identifier
        }
        lock.unlock()

        if shouldCancel {
            manager.cancelDataRequest(identifier)
        }
    }

    private func receive(_ data: Data) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }

        do {
            try file.write(contentsOf: data)
            lock.unlock()
        } catch {
            isFinished = true
            shouldCancelRequest = true
            let identifier = requestID
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()

            if let identifier { manager.cancelDataRequest(identifier) }
            continuation?.resume(throwing: error)
        }
    }

    private func finish(_ error: Error?) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }

    private func cancel() {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isCancelled = true
        isFinished = true
        shouldCancelRequest = true
        let identifier = requestID
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        if let identifier { manager.cancelDataRequest(identifier) }
        continuation?.resume(throwing: CancellationError())
    }
}
