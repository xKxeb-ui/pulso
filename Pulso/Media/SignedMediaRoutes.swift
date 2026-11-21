import CryptoKit
import Foundation

struct MediaDestination: Equatable {
    let url: URL
    let ip: String
    let pins: Set<Data>
}

enum MediaRoutingError: LocalizedError {
    case unavailable, invalid, disabled, changed

    var errorDescription: String? {
        switch self {
        case .unavailable: "No se pudo consultar el destino. Revisa tu conexión e inténtalo de nuevo."
        case .invalid: "La política del servidor no es válida o ha vencido."
        case .disabled: "La transferencia está pausada o no hay un servidor autorizado."
        case .changed: "El destino cambió. Revisa y confirma el nuevo servidor antes de continuar."
        }
    }
}

struct SignedMediaRoutes {
    static let maxEnvelopeBytes = 32 * 1024
    private static let p256KeyPrefix = Data([
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
        0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00
    ])

    let revision: Int64
    let expiresAt: Int64
    let digest: String
    let destinations: [MediaDestination]

    var isCurrent: Bool { expiresAt > Self.millisecondsNow }

    static var millisecondsNow: Int64 { Int64(Date.now.timeIntervalSince1970 * 1000) }

    static func verify(_ envelope: Data, publicKey: String, now: Int64) throws -> Self {
        guard envelope.count <= maxEnvelopeBytes, now >= 0 else { throw MediaRoutingError.invalid }
        let lines = try asciiLines(envelope)
        guard lines.count == 3, lines[0] == "WINGY-SIGNED-ROUTING-1",
              let payload = base64(lines[1]), let signature = base64(lines[2]),
              let encodedKey = base64(Substring(publicKey)), encodedKey.starts(with: p256KeyPrefix),
              let key = try? P256.Signing.PublicKey(x963Representation: Data(encodedKey.dropFirst(p256KeyPrefix.count))),
              let der = try? P256.Signing.ECDSASignature(derRepresentation: signature),
              key.isValidSignature(der, for: payload) else {
            throw MediaRoutingError.invalid
        }

        let fields = try asciiLines(payload)
        guard fields.count >= 5, fields[0] == "WINGY-ROUTING-1",
              let revision = try? number(fields[1], prefix: "revision="), revision > 0,
              let issued = try? number(fields[2], prefix: "issued_at="),
              let expiry = try? number(fields[3], prefix: "expires_at="),
              expiry > now, expiry > issued, expiry - issued <= 86_400_000,
              issued <= now || issued - now <= 300_000 else {
            throw MediaRoutingError.invalid
        }

        var endpoints: [MediaDestination] = []
        var revoked = Set<String>()
        for line in fields.dropFirst(5) {
            if line.hasPrefix("endpoint="), revoked.isEmpty {
                let destination = try endpoint(line.dropFirst("endpoint=".count))
                guard endpoints.count < 4, !endpoints.contains(where: { $0.url == destination.url }) else {
                    throw MediaRoutingError.invalid
                }
                endpoints.append(destination)
            } else if line.hasPrefix("revoked_ip=") {
                let ip = String(line.dropFirst("revoked_ip=".count))
                guard revoked.count < 8, ipv4(ip) != nil, revoked.insert(ip).inserted else {
                    throw MediaRoutingError.invalid
                }
            } else {
                throw MediaRoutingError.invalid
            }
        }

        let eligible: [MediaDestination]
        switch fields[4] {
        case "mode=auto": eligible = endpoints
        case "mode=force": eligible = Array(endpoints.prefix(1))
        case "mode=paused": eligible = []
        default: throw MediaRoutingError.invalid
        }
        return Self(
            revision: revision,
            expiresAt: expiry,
            digest: Data(SHA256.hash(data: payload)).base64EncodedString(),
            destinations: eligible.filter { !revoked.contains($0.ip) }
        )
    }

    private static func asciiLines(_ data: Data) throws -> [Substring] {
        guard data.last == 10, data.allSatisfy({ $0 <= 127 && $0 != 13 }),
              let text = String(data: data, encoding: .ascii) else {
            throw MediaRoutingError.invalid
        }
        return Array(text.split(separator: "\n", omittingEmptySubsequences: false).dropLast())
    }

    private static func base64(_ text: Substring) -> Data? {
        guard !text.isEmpty, let data = Data(base64Encoded: String(text)),
              data.base64EncodedString() == text else { return nil }
        return data
    }

    private static func number(_ line: Substring, prefix: String) throws -> Int64 {
        let text = line.dropFirst(prefix.count)
        guard line.hasPrefix(prefix), let value = Int64(text), value >= 0,
              String(value) == text else {
            throw MediaRoutingError.invalid
        }
        return value
    }

    private static func ipv4(_ host: String) -> [Int]? {
        let fields = host.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = fields.compactMap { field -> Int? in
            guard let value = UInt8(field), String(value) == field else { return nil }
            return Int(value)
        }
        return fields.count == 4 && numbers.count == 4 ? numbers : nil
    }

    private static func isPublic(_ octets: [Int]) -> Bool {
        let a = octets[0], b = octets[1], c = octets[2]
        switch (a, b, c) {
        case (0, _, _), (10, _, _), (127, _, _), (224...255, _, _),
             (100, 64...127, _), (169, 254, _), (172, 16...31, _), (192, 168, _),
             (192, 0, 0), (192, 0, 2), (192, 88, 99), (198, 18...19, _),
             (198, 51, 100), (203, 0, 113):
            return false
        default:
            return true
        }
    }

    private static func endpoint(_ field: Substring) throws -> MediaDestination {
        let parts = field.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count <= 256,
              let components = URLComponents(string: String(parts[0])),
              components.scheme == "https", components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let ip = components.host, let octets = ipv4(ip), isPublic(octets),
              (1...65535).contains(components.port ?? 443),
              let url = components.url else {
            throw MediaRoutingError.invalid
        }
        let path = components.percentEncodedPath
        let segments = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard path.range(of: "^(?:/[A-Za-z0-9._~-]+)*$", options: .regularExpression) != nil,
              !segments.contains("."), !segments.contains("..") else {
            throw MediaRoutingError.invalid
        }
        let port = components.port.map { ":\($0)" } ?? ""
        guard "https://\(ip)\(port)\(path)" == parts[0] else { throw MediaRoutingError.invalid }

        let pinFields = parts[1].split(separator: ",", omittingEmptySubsequences: false)
        let pins = Set(pinFields.compactMap { pin -> Data? in
            guard pin.hasPrefix("sha256/"), let data = base64(pin.dropFirst(7)), data.count == 32 else {
                return nil
            }
            return data
        })
        guard (1...2).contains(pinFields.count), pins.count == pinFields.count else {
            throw MediaRoutingError.invalid
        }
        return MediaDestination(url: url, ip: ip, pins: pins)
    }
}
