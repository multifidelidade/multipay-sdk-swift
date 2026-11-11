import Foundation

/// Situação de um pagamento.
///
/// IMPORTANTE: o status que volta pelo deep link do checkout é só uma DICA para a interface
/// (o usuário pode editar a URL). Quem libera o pedido é o SEU backend, após o webhook assinado ou um GET.
public enum CheckoutStatus: String, Sendable, Equatable {
    case paid, pending, expired, canceled, unknown

    public init(apiValue: String?) {
        switch apiValue?.lowercased() {
        case "paid": self = .paid
        case "pending": self = .pending
        case "expired": self = .expired
        case "canceled", "cancelled": self = .canceled
        default: self = .unknown
        }
    }
}

/// Retorno do checkout (a `returnUrl` recebe `?referenceId=...&status=...`).
public struct CheckoutResult: Sendable, Equatable {
    public let referenceId: String?
    public let status: CheckoutStatus
    /// URL completa recebida, para depuração.
    public let rawURL: URL
}

public enum CheckoutReturn {
    /// Interpreta a URL de retorno. Nunca lança.
    public static func parse(_ url: URL?) -> CheckoutResult? {
        guard let url else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        return CheckoutResult(
            referenceId: value("referenceId"),
            status: CheckoutStatus(apiValue: value("status")),
            rawURL: url
        )
    }
}

/// Valida a URL do checkout ANTES de abri-la: só https e só hosts da MultiPay (ou os que você autorizar).
public enum CheckoutURL {
    private static let defaultHosts: Set<String> = ["multifidelidade.app"]

    /// - Parameter extraHosts: hosts adicionais (ex.: seu ambiente de testes). Subdomínios são aceitos.
    public static func isSafe(_ url: URL?, extraHosts: Set<String> = []) -> Bool {
        guard let url, url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased() else { return false }
        let allowed = defaultHosts.union(extraHosts.map { $0.lowercased() })
        return allowed.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
