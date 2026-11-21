import CryptoKit
import Foundation

func runChecks() throws {
    let now: Int64 = 1_800_000_000_000
    let signingKey = P256.Signing.PrivateKey()
    let prefix = Data([0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
                       0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00])
    let publicKey = (prefix + signingKey.publicKey.x963Representation).base64EncodedString()
    let pin = Data(repeating: 19, count: 32).base64EncodedString()
    let primary = "endpoint=https://8.8.4.4:8443/wingy sha256/\(pin)"
    let alternative = "endpoint=https://1.0.0.1/wingy sha256/\(pin)"

    func envelope(
        mode: String = "force", endpoints: [String] = [primary, alternative],
        issued: Int64 = now - 1000, expires: Int64 = now + 1000, tamper: Bool = false
    ) throws -> Data {
        let fields = ["WINGY-ROUTING-1", "revision=42", "issued_at=\(issued)", "expires_at=\(expires)", "mode=\(mode)"]
        let payload = Data(((fields + endpoints).joined(separator: "\n") + "\n").utf8)
        let signature = try signingKey.signature(for: payload).derRepresentation.base64EncodedString()
        let data = tamper ? payload + Data([10]) : payload
        return Data("WINGY-SIGNED-ROUTING-1\n\(data.base64EncodedString())\n\(signature)\n".utf8)
    }

    func verify(_ envelope: Data) throws -> SignedMediaRoutes {
        try SignedMediaRoutes.verify(envelope, publicKey: publicKey, now: now)
    }

    func expectInvalid(_ envelope: Data) throws {
        do {
            _ = try verify(envelope)
            fatalError("Se aceptó una política inválida")
        } catch MediaRoutingError.invalid {}
    }

    let forced = try verify(envelope())
    precondition(forced.revision == 42 && forced.destinations.map(\.ip) == ["8.8.4.4"])
    let ordered = try verify(envelope(mode: "auto", endpoints: [primary, alternative, "revoked_ip=8.8.4.4"]))
    precondition(ordered.destinations.map(\.ip) == ["1.0.0.1"])
    let revoked = try verify(envelope(endpoints: [primary, alternative, "revoked_ip=8.8.4.4"]))
    precondition(revoked.destinations.isEmpty)
    let paused = try verify(envelope(mode: "paused"))
    precondition(paused.destinations.isEmpty)
    try expectInvalid(envelope(expires: now))
    try expectInvalid(envelope(issued: now + 300_001, expires: now + 600_000))
    try expectInvalid(envelope(tamper: true))
    try expectInvalid(envelope(endpoints: [primary, primary]))
    try expectInvalid(envelope(endpoints: ["revoked_ip=1.0.0.1", primary]))
    try expectInvalid(envelope(endpoints: ["endpoint=https://127.0.0.1/wingy sha256/\(pin)"]))
    try expectInvalid(envelope(endpoints: ["endpoint=https://8.8.4.4/a/../wingy sha256/\(pin)"]))
    try expectInvalid(envelope(endpoints: ["endpoint=https://8.8.4.4:0443/wingy sha256/\(pin)"]))

    print("OK: rutas firmadas")
}

try runChecks()
