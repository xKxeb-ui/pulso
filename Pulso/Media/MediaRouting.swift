import CryptoKit
import Foundation
import Security

@MainActor
final class MediaRouting {
    private static let source = URL(string: "https://raw.githubusercontent.com/xKxeb-ui/wingy-routing/main/wingy-routing.signed")!
    private static let publicKey = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEMWzmY4kCBm15mp0r3e4BwkXrcY90Gdkj9uLIk+ctoXpXncTGNVtFDJGIdt+ldHzZhYCkpGAXd2+b6YpcmnsXvw=="
    private static let revisionKey = "pulso.media.routingVersion"

    private var current: SignedMediaRoutes?
    private var lastCheck: ContinuousClock.Instant?
    private var refreshTask: Task<SignedMediaRoutes, Error>?

    func resolve() async throws -> MediaDestination {
        let policy = try await fetchShared()
        guard let destination = policy.destinations.first else {
            throw MediaRoutingError.disabled
        }
        return destination
    }

    func validate(_ destination: MediaDestination, refresh: Bool = false) async throws {
        let policy: SignedMediaRoutes
        if !refresh, let current, current.isCurrent, let lastCheck,
           lastCheck.duration(to: .now) < .seconds(20) {
            policy = current
        } else {
            policy = try await fetchShared()
        }
        guard policy.destinations.contains(destination) else {
            throw policy.destinations.isEmpty ? MediaRoutingError.disabled : MediaRoutingError.changed
        }
    }

    func cancelRefresh() {
        refreshTask?.cancel()
    }

    private func fetchShared() async throws -> SignedMediaRoutes {
        try Task.checkCancellation()
        if let refreshTask {
            let policy = try await refreshTask.value
            try Task.checkCancellation()
            return policy
        }
        let task = Task { try await self.fetch() }
        refreshTask = task
        defer { refreshTask = nil }
        let policy = try await task.value
        try Task.checkCancellation()
        return policy
    }

    private func fetch() async throws -> SignedMediaRoutes {
        let session = MediaServerSession.make()
        defer { session.invalidateAndCancel() }

        let envelope: Data
        do {
            var source = URLComponents(url: Self.source, resolvingAgainstBaseURL: false)!
            source.queryItems = [URLQueryItem(name: "cache", value: String(SignedMediaRoutes.millisecondsNow / 60_000))]
            var request = URLRequest(url: source.url!, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
            let (bytes, response) = try await session.bytes(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw MediaRoutingError.unavailable
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < SignedMediaRoutes.maxEnvelopeBytes else { throw MediaRoutingError.invalid }
                data.append(byte)
            }
            envelope = data
        } catch {
            try Task.checkCancellation()
            throw error as? MediaRoutingError ?? MediaRoutingError.unavailable
        }

        let policy = try SignedMediaRoutes.verify(
            envelope, publicKey: Self.publicKey, now: SignedMediaRoutes.millisecondsNow
        )
        try Task.checkCancellation()

        let defaults = UserDefaults.standard
        let version = "\(policy.revision):\(policy.digest)"
        if let record = defaults.string(forKey: Self.revisionKey) {
            guard let prefix = record.split(separator: ":", maxSplits: 1).first,
                  let revision = Int64(prefix), policy.revision >= revision,
                  policy.revision != revision || record == version else {
                throw MediaRoutingError.invalid
            }
        }
        defaults.set(version, forKey: Self.revisionKey)
        current = policy
        lastCheck = .now
        return policy
    }
}

final class MediaServerSession: NSObject, URLSessionTaskDelegate {
    private let destination: MediaDestination?

    private init(destination: MediaDestination?) { self.destination = destination }

    static func make(for destination: MediaDestination? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = destination == nil ? 10 : 60
        configuration.timeoutIntervalForResource = destination == nil ? 20 : 300
        if destination != nil { configuration.httpMaximumConnectionsPerHost = 5 }
        return URLSession(configuration: configuration, delegate: MediaServerSession(destination: destination),
                          delegateQueue: nil)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let destination else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              space.host == destination.ip, space.port == (destination.url.port ?? 443),
              let trust = space.serverTrust,
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, destination.ip as CFString)) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil),
              let certificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
              let publicKey = CertificateSPKI.extract(SecCertificateCopyData(certificate) as Data),
              destination.pins.contains(Data(SHA256.hash(data: publicKey))) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
