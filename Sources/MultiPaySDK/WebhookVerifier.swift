#if canImport(CryptoKit)
import CryptoKit
import Foundation

/// Verificador de webhooks para BACKENDS Swift (Vapor...). Não use em app.
/// Header: `MultiPay-Signature: t=<unix>,v1=<hex>`; v1 = HMAC-SHA256(segredo, "<t>." + corpoBruto).
public enum WebhookVerifier {
    public static let headerName = "MultiPay-Signature"
    public static let defaultToleranceSeconds: TimeInterval = 300

    public enum Failure: Sendable, Equatable {
        case missingHeader, malformedHeader, timestampOutOfTolerance, signatureMismatch
    }

    public enum Result: Sendable, Equatable {
        case valid
        case invalid(Failure)
    }

    public static func sign(secret: String, timestamp: Int, rawBody: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data("\(timestamp).\(rawBody)".utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(
        secret: String,
        header: String?,
        rawBody: String,
        now: Date = Date(),
        tolerance: TimeInterval = defaultToleranceSeconds
    ) -> Result {
        guard let header, !header.isEmpty else { return .invalid(.missingHeader) }

        var timestamp: Int?
        var signature: String?
        for part in header.split(separator: ",") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            if kv[0] == "t" { timestamp = Int(kv[1]) }
            if kv[0] == "v1" { signature = kv[1] }
        }
        guard let timestamp, let signature else { return .invalid(.malformedHeader) }
        guard abs(now.timeIntervalSince1970 - TimeInterval(timestamp)) <= tolerance else {
            return .invalid(.timestampOutOfTolerance)
        }

        let expected = Array(sign(secret: secret, timestamp: timestamp, rawBody: rawBody).utf8)
        let received = Array(signature.utf8)
        guard expected.count == received.count else { return .invalid(.signatureMismatch) }
        // comparação em tempo constante
        var diff: UInt8 = 0
        for (a, b) in zip(expected, received) { diff |= a ^ b }
        return diff == 0 ? .valid : .invalid(.signatureMismatch)
    }
}
#endif
