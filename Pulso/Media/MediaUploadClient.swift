import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum MediaUploadError: LocalizedError {
    case invalidDestination
    case invalidFile
    case invalidFormat
    case temporaryFileFailed
    case connectionFailed
    case serverRejected(Int)
    case videoStateConflict
    case videoNotConfirmed
    case partFailed(Int, Int?)

    var errorDescription: String? {
        switch self {
        case .invalidDestination: "La dirección de carga no es válida."
        case .invalidFile: "No se pudo abrir el archivo seleccionado."
        case .invalidFormat: "El tipo o la extensión del archivo no es válido."
        case .temporaryFileFailed: "No se pudo preparar el archivo para enviarlo."
        case .connectionFailed: "No se pudo completar la solicitud de carga."
        case .serverRejected(let code): "El servidor rechazó la carga (HTTP \(code))."
        case .videoStateConflict: "El estado guardado del video no coincide con este archivo."
        case .videoNotConfirmed: "El servidor no confirmó que el video se recibió completo."
        case .partFailed(let index, let code):
            if let code { "No se pudo enviar la parte \(index + 1) del video (HTTP \(code))." }
            else { "No se pudo enviar la parte \(index + 1) del video." }
        }
    }
}

final class MediaUploadClient {
    private let session: URLSession
    private let baseURL: URL
    private let device: String
    private let deviceName: String
    private let files = FileManager.default
    private let partSize: Int64 = 4 * 1024 * 1024
    private let maxPartAttempts = 3

    init(session: URLSession, baseURL: URL, device: String, deviceName: String) {
        self.session = session
        self.baseURL = baseURL
        self.device = device
        self.deviceName = deviceName
    }

    /// Uploads only the caller-selected URL. The session and destination checks
    /// are supplied by the caller so this client cannot choose another host.
    func upload(
        file: URL,
        id: UUID,
        fileExtension: String,
        contentType: String,
        isVideo: Bool,
        validateDestination: () async throws -> Void
    ) async throws {
        let ext = String(fileExtension.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(16)).lowercased()
        guard !ext.isEmpty,
              contentType.range(of: #"^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$"#, options: .regularExpression) != nil,
              !device.isEmpty, !device.contains("\r"), !device.contains("\n"),
              isSafeHeaderValue(deviceName) else {
            throw MediaUploadError.invalidFormat
        }
        _ = try endpoint("upload")
        let source = try sourceInfo(file)
        guard source.size > 0 else { throw MediaUploadError.invalidFile }
        let filename = "\(id.uuidString.lowercased()).\(ext)"

        if isVideo {
            try await uploadVideo(
                file: file,
                source: source,
                id: id,
                filename: filename,
                validateDestination: validateDestination
            )
        } else {
            let (body, boundary) = try multipartFile(
                fields: [("device", device), ("kind", "media"), ("category", "others")],
                source: file,
                expectedSource: source,
                filename: filename,
                mediaType: contentType,
                range: 0..<source.size
            )
            defer { try? files.removeItem(at: body) }

            var request = URLRequest(url: try endpoint("upload"))
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue(device, forHTTPHeaderField: "X-Device-Code")
            request.setValue(deviceName, forHTTPHeaderField: "X-Device-Name")
            request.setValue(device, forHTTPHeaderField: "X-Device-Id")
            request.setValue("others", forHTTPHeaderField: "X-Category")
            request.setValue(id.uuidString.lowercased(), forHTTPHeaderField: "X-Pulso-Upload-ID")

            try Task.checkCancellation()
            try await validateDestination()
            let response = try await uploadRequest(request, body: body)
            guard (200..<300).contains(response.statusCode) else {
                throw MediaUploadError.serverRejected(response.statusCode)
            }
        }
    }

    private func uploadVideo(
        file: URL,
        source: SourceInfo,
        id: UUID,
        filename: String,
        validateDestination: () async throws -> Void
    ) async throws {
        let videoID = id.uuidString.replacingOccurrences(of: "-", with: "").lowercased() + "00000000"
        let count64 = source.size / partSize + (source.size % partSize == 0 ? 0 : 1)
        guard count64 > 0, count64 <= Int64(Int32.max) else { throw MediaUploadError.invalidFile }
        let count = Int(count64)
        var status = try await fetchStatus(
            videoID: videoID,
            size: source.size,
            count: count,
            allowMissing: true,
            validateDestination: validateDestination
        )
        if status.complete { return }

        for index in 0..<count where !status.complete && !status.parts.contains(index) {
            let start = Int64(index) * partSize
            let end = min(start + partSize, source.size)
            var sent = false
            var lastCode: Int?

            for attempt in 0..<maxPartAttempts {
                try Task.checkCancellation()
                try ensureUnchanged(file, source)
                var request = URLRequest(url: try endpoint("upload_part"))
                let (body, boundary) = try multipartFile(
                    fields: [
                        ("device", device),
                        ("video_id", videoID),
                        ("part_index", String(index)),
                        ("total_parts", String(count)),
                        ("total_size", String(source.size)),
                        ("filename", filename),
                        ("category", "others"),
                        ("kind", "media")
                    ],
                    source: file,
                    expectedSource: source,
                    filename: "part_\(index).bin",
                    mediaType: "application/octet-stream",
                    range: start..<end
                )

                request.httpMethod = "POST"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                request.setValue(device, forHTTPHeaderField: "X-Device-Code")
                request.setValue(deviceName, forHTTPHeaderField: "X-Device-Name")
                request.setValue(device, forHTTPHeaderField: "X-Device-Id")
                request.setValue("others", forHTTPHeaderField: "X-Category")
                request.setValue(videoID, forHTTPHeaderField: "X-Video-Id")
                request.setValue(String(index), forHTTPHeaderField: "X-Part-Index")
                request.setValue(String(count), forHTTPHeaderField: "X-Part-Total")
                request.setValue(String(source.size), forHTTPHeaderField: "X-Total-Size")
                request.setValue(filename, forHTTPHeaderField: "X-Original-Name")
                request.setValue("chunked_original", forHTTPHeaderField: "X-Video-Mode")

                let responseCode: Int?
                do {
                    defer { try? files.removeItem(at: body) }
                    try await validateDestination()
                    let response = try await uploadRequest(request, body: body)
                    responseCode = response.statusCode
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as MediaUploadError {
                    if case .connectionFailed = error { responseCode = nil }
                    else { throw error }
                }

                if let code = responseCode {
                    lastCode = code
                    if (200..<300).contains(code) {
                        sent = true
                        break
                    }
                    guard retryable(code) else { throw MediaUploadError.serverRejected(code) }
                }

                // The POST may have succeeded while its response was lost.
                try Task.checkCancellation()
                try await validateDestination()
                do {
                    status = try await readStatus(videoID: videoID, size: source.size, count: count, allowMissing: true)
                } catch let error as MediaUploadError {
                    if case .connectionFailed = error { /* Retry the same idempotent part. */ }
                    else { throw error }
                }
                if status.complete || status.parts.contains(index) {
                    sent = true
                    break
                }
                if attempt + 1 < maxPartAttempts {
                    try await Task.sleep(nanoseconds: UInt64(500_000_000 * (attempt + 1)))
                }
            }

            guard sent else { throw MediaUploadError.partFailed(index, lastCode) }
            status.parts.insert(index)
        }

        try ensureUnchanged(file, source)
        let finalStatus = try await fetchStatus(
            videoID: videoID,
            size: source.size,
            count: count,
            allowMissing: false,
            validateDestination: validateDestination
        )
        guard finalStatus.complete else { throw MediaUploadError.videoNotConfirmed }
    }

    private func fetchStatus(
        videoID: String,
        size: Int64,
        count: Int,
        allowMissing: Bool,
        validateDestination: () async throws -> Void
    ) async throws -> UploadStatus {
        try Task.checkCancellation()
        try await validateDestination()
        return try await readStatus(videoID: videoID, size: size, count: count, allowMissing: allowMissing)
    }

    private func readStatus(videoID: String, size: Int64, count: Int, allowMissing: Bool) async throws -> UploadStatus {
        try Task.checkCancellation()
        var components = URLComponents(url: try endpoint("upload_status"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "device", value: device), URLQueryItem(name: "video_id", value: videoID)]
        guard let url = components?.url else { throw MediaUploadError.invalidDestination }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(device, forHTTPHeaderField: "X-Device-Code")

        let data: Data
        let response: HTTPURLResponse
        do {
            let result = try await session.data(for: request)
            guard let http = result.1 as? HTTPURLResponse else { throw MediaUploadError.invalidFormat }
            data = result.0
            response = http
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MediaUploadError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw MediaUploadError.connectionFailed
        }
        if response.statusCode == 404 && allowMissing { return .empty }
        guard (200..<300).contains(response.statusCode) else { throw MediaUploadError.serverRejected(response.statusCode) }
        guard data.count <= 64 * 1024,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MediaUploadError.invalidFormat
        }

        let rawParts = json["received_parts"] as? [NSNumber] ?? []
        guard rawParts.count <= count else { throw MediaUploadError.videoStateConflict }
        let parts = rawParts.map(\.intValue)
        guard parts.allSatisfy({ (0..<count).contains($0) }) else { throw MediaUploadError.videoStateConflict }
        let totalSize = (json["total_size"] as? NSNumber)?.int64Value ?? 0
        let totalParts = (json["total_parts"] as? NSNumber)?.intValue ?? 0
        let complete = (json["complete"] as? NSNumber)?.boolValue ?? false
        if totalSize == 0 && totalParts == 0 && !complete && parts.isEmpty { return .empty }
        guard totalSize == size, totalParts == count else { throw MediaUploadError.videoStateConflict }
        return UploadStatus(parts: Set(parts), complete: complete)
    }

    private func uploadRequest(_ request: URLRequest, body: URL) async throws -> HTTPURLResponse {
        try Task.checkCancellation()
        do {
            let (_, response) = try await session.upload(for: request, fromFile: body)
            guard let http = response as? HTTPURLResponse else { throw MediaUploadError.invalidFormat }
            return http
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MediaUploadError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw MediaUploadError.connectionFailed
        }
    }

    private func multipartFile(
        fields: [(String, String)],
        source: URL,
        expectedSource: SourceInfo,
        filename: String,
        mediaType: String,
        range: Range<Int64>
    ) throws -> (URL, String) {
        let boundary = "Pulso-\(UUID().uuidString)"
        let body = files.temporaryDirectory.appendingPathComponent("pulso-\(UUID().uuidString).multipart")
        guard files.createFile(atPath: body.path, contents: nil) else { throw MediaUploadError.temporaryFileFailed }
        do {
            let output = try FileHandle(forWritingTo: body)
            let input = try FileHandle(forReadingFrom: source)
            defer { try? output.close(); try? input.close() }
            for (name, value) in fields {
                try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
            }
            try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(mediaType)\r\n\r\n".utf8))
            try input.seek(toOffset: UInt64(range.lowerBound))
            var remaining = range.upperBound - range.lowerBound
            while remaining > 0 {
                try Task.checkCancellation()
                let part = try input.read(upToCount: Int(min(64 * 1024, remaining)))
                guard let part, !part.isEmpty else { throw MediaUploadError.invalidFile }
                try output.write(contentsOf: part)
                remaining -= Int64(part.count)
            }
            try ensureUnchanged(source, expectedSource)
            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            return (body, boundary)
        } catch {
            try? files.removeItem(at: body)
            if error is CancellationError { throw CancellationError() }
            if let uploadError = error as? MediaUploadError { throw uploadError }
            throw MediaUploadError.temporaryFileFailed
        }
    }

    private func sourceInfo(_ file: URL) throws -> SourceInfo {
        guard file.isFileURL else { throw MediaUploadError.invalidFile }
        do {
            let attributes = try files.attributesOfItem(atPath: file.path)
            guard (attributes[.type] as? FileAttributeType) == .typeRegular,
                  let size = (attributes[.size] as? NSNumber)?.int64Value else {
                throw MediaUploadError.invalidFile
            }
            return SourceInfo(size: size, modified: attributes[.modificationDate] as? Date)
        } catch let error as MediaUploadError {
            throw error
        } catch {
            throw MediaUploadError.invalidFile
        }
    }

    private func ensureUnchanged(_ file: URL, _ expected: SourceInfo) throws {
        let current = try sourceInfo(file)
        guard current.size == expected.size, current.modified == expected.modified else {
            throw MediaUploadError.invalidFile
        }
    }

    private func endpoint(_ name: String) throws -> URL {
        guard var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              parts.host != nil, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { throw MediaUploadError.invalidDestination }
        var path = parts.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        let endsInUpload = path == "upload" || path.hasSuffix("/upload")
        if name == "upload" && endsInUpload { parts.path = path }
        else {
            if endsInUpload { path = String(path.dropLast("/upload".count)) }
            if path == "/" { path = "" }
            parts.path = path + "/" + name
        }
        guard let url = parts.url else { throw MediaUploadError.invalidDestination }
        return url
    }

    private func retryable(_ code: Int) -> Bool {
        code == 408 || code == 409 || code == 429 || (500..<600).contains(code)
    }

    private func isSafeHeaderValue(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0)
        }
    }

    private struct SourceInfo {
        let size: Int64
        let modified: Date?
    }

    private struct UploadStatus {
        var parts: Set<Int>
        let complete: Bool
        static let empty = UploadStatus(parts: [], complete: false)
    }
}
