import Foundation

public enum StableID {
    /// Deterministic name-based UUID; byte-identical to the former CryptoKit implementation so existing record IDs never change.
    public static func make(_ namespace: String, _ value: String) -> UUID {
        var bytes = Array(SHA256Digest.hash(Data((namespace + "\u{0}" + value).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
