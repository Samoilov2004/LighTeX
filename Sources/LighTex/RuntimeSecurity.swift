import CryptoKit
import Foundation

enum RuntimeSecurity {
    static func verifyManifest(
        _ manifestData: Data,
        signature: Data,
        publicKey: Data
    ) throws {
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        guard key.isValidSignature(signature, for: manifestData) else {
            throw RuntimeError.invalidManifestSignature
        }
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
