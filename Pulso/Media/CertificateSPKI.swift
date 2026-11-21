import Foundation

enum CertificateSPKI {
    // X.509 signs TBSCertificate, which contains the exact DER SubjectPublicKeyInfo
    // used by the Android receiver pins, including its algorithm identifier.
    static func extract(_ certificate: Data) -> Data? {
        guard let outer = node(in: certificate, at: 0), outer.tag == 0x30,
              outer.body.upperBound == certificate.count,
              let tbs = node(in: certificate, at: outer.body.lowerBound), tbs.tag == 0x30,
              tbs.body.upperBound <= outer.body.upperBound else { return nil }

        var cursor = tbs.body.lowerBound
        if let version = node(in: certificate, at: cursor), version.tag == 0xa0 {
            cursor = version.body.upperBound
        }
        for tag: UInt8 in [0x02, 0x30, 0x30, 0x30, 0x30] {
            guard let field = node(in: certificate, at: cursor), field.tag == tag,
                  field.body.upperBound <= tbs.body.upperBound else { return nil }
            cursor = field.body.upperBound
        }
        guard let spki = node(in: certificate, at: cursor), spki.tag == 0x30,
              spki.body.upperBound <= tbs.body.upperBound else { return nil }
        return certificate.subdata(in: cursor..<spki.body.upperBound)
    }

    private static func node(in bytes: Data, at offset: Int) -> (tag: UInt8, body: Range<Int>)? {
        guard offset >= 0, offset < bytes.count - 1 else { return nil }
        let tag = bytes[offset]
        let lengthByte = Int(bytes[offset + 1])
        var start = offset + 2
        var size = lengthByte
        if lengthByte >= 128 {
            let count = lengthByte & 127
            guard (1...4).contains(count), count <= bytes.count - start,
                  bytes[start] != 0 else { return nil }
            size = 0
            for byte in bytes[start..<start + count] {
                size = size * 256 + Int(byte)
            }
            start += count
            guard size >= 128 else { return nil }
        }
        guard size <= bytes.count - start else { return nil }
        return (tag, start..<start + size)
    }
}
