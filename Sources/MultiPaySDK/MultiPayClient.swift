import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct FieldError: Decodable, Sendable, Equatable {
    public let field: String
    public let message: String
}

/// Erro devolvido pela API (`{ error: { code, message, details, traceId } }`) ou falha de rede (`status == 0`).
public struct MultiPayError: Error, LocalizedError, Sendable {
    public let status: Int
    public let code: String
    public let message: String
    public let details: [FieldError]
    public let traceId: String?

    public var errorDescription: String? {
        var text = "\(message) (\(code))"
        for d in details { text += "\n- \(d.field): \(d.message)" }
        return text
    }
}

public struct Customer: Encodable, Sendable {
    public var name: String?
    public var email: String?
    public var phone: String?
    public init(name: String? = nil, email: String? = nil, phone: String? = nil) {
        self.name = name; self.email = email; self.phone = phone
    }
}

public struct CreatePaymentRequest: Encodable, Sendable {
    public var referenceId: String
    /// Centavos. R$ 150,00 = 15000.
    public var amountCents: Int64
    public var cpf: String
    public var callbackUrl: String
    public var returnUrl: String
    public var message: String?
    public var customer: Customer?
    public var expiresAt: String?
    public var expiresInMinutes: Int?

    public init(referenceId: String, amountCents: Int64, cpf: String, callbackUrl: String, returnUrl: String,
                message: String? = nil, customer: Customer? = nil, expiresAt: String? = nil, expiresInMinutes: Int? = nil) {
        self.referenceId = referenceId; self.amountCents = amountCents; self.cpf = cpf
        self.callbackUrl = callbackUrl; self.returnUrl = returnUrl; self.message = message
        self.customer = customer; self.expiresAt = expiresAt; self.expiresInMinutes = expiresInMinutes
    }
}

public struct Payment: Decodable, Sendable, Equatable {
    public let referenceId: String
    public let paymentUrl: String
    /// pending | paid | expired | canceled
    public let status: String
    public let amountCents: Int64
    public let currency: String?
    public let livemode: Bool?
    public let createdAt: String?
    public let expiresAt: String?
    public let paidAt: String?
    public let canceledAt: String?
    public let transactionId: String?

    public var checkoutStatus: CheckoutStatus { CheckoutStatus(apiValue: status) }
    public var checkoutURL: URL? { URL(string: paymentUrl) }
}

public struct CreatedPayment: Sendable {
    public let payment: Payment
    /// true se o mesmo `referenceId` já existia (idempotência): o link devolvido é o original.
    public let replayed: Bool
}

public struct Me: Decodable, Sendable, Equatable {
    public let merchantId: Int
    public let merchantName: String
    public let livemode: Bool
}

public struct PaymentPage: Decodable, Sendable {
    public let data: [Payment]
    public let nextCursor: String?
}

private struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String?
        let message: String?
        let details: [FieldError]?
        let traceId: String?
    }
    let error: Body?
}

/// Impede seguir redirects: a chave está no header Authorization.
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Cliente da MultiPay API v2.
///
/// SEGURANÇA: chaves de produção (`mp_live_`) **não podem** ficar em app — qualquer pessoa extrai do binário.
/// No app use apenas `mp_test_` (demo/sandbox); em produção o app fala com o SEU backend, que cria o pagamento.
/// Backends Swift (Vapor...) usam `forBackend`.
public struct MultiPayClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.multifidelidade.app")!

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    private init(apiKey: String, baseURL: URL, session: URLSession) {
        self.apiKey = apiKey; self.baseURL = baseURL; self.session = session
    }

    /// Para APPS: aceita somente chave de teste (`mp_test_`).
    public static func forApp(testApiKey: String, baseURL: URL = defaultBaseURL, session: URLSession = .shared) throws -> MultiPayClient {
        guard testApiKey.hasPrefix("mp_test_") else {
            throw MultiPayError(status: 0, code: "live_key_not_allowed_in_app",
                                message: "Chave de produção não pode ficar em app. Use mp_test_ no app e crie os pagamentos reais no seu backend.",
                                details: [], traceId: nil)
        }
        return try make(apiKey: testApiKey, baseURL: baseURL, session: session)
    }

    /// Para BACKENDS Swift (aceita mp_live_ e mp_test_). Indisponível em iOS.
    @available(iOS, unavailable, message: "Nunca use chaves de produção dentro de um app iOS.")
    public static func forBackend(apiKey: String, baseURL: URL = defaultBaseURL, session: URLSession = .shared) throws -> MultiPayClient {
        try make(apiKey: apiKey, baseURL: baseURL, session: session)
    }

    private static func make(apiKey: String, baseURL: URL, session: URLSession) throws -> MultiPayClient {
        let valid = apiKey.range(of: "^mp_(live|test)_[A-Za-z0-9_-]{16,}$", options: .regularExpression) != nil
        guard valid else {
            throw MultiPayError(status: 0, code: "invalid_api_key", message: "API key inválida: deve começar com mp_live_ ou mp_test_.", details: [], traceId: nil)
        }
        let local = ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "")
        guard baseURL.scheme == "https" || local else {
            throw MultiPayError(status: 0, code: "insecure_base_url", message: "baseURL precisa ser https (a chave trafega no header).", details: [], traceId: nil)
        }
        return MultiPayClient(apiKey: apiKey, baseURL: baseURL, session: session)
    }

    // MARK: - Endpoints

    public func whoami() async throws -> Me {
        try await send("GET", "/v2/me").decoded()
    }

    /// Idempotente por `referenceId`: repetir a mesma requisição devolve o mesmo link (`replayed == true`).
    public func createPayment(_ request: CreatePaymentRequest) async throws -> CreatedPayment {
        let body = try JSONEncoder().encode(request)
        let res = try await send("POST", "/v2/payments", body: body)
        let payment: Payment = try res.decoded()
        return CreatedPayment(payment: payment, replayed: res.header("Idempotent-Replayed") == "true")
    }

    public func getPayment(referenceId: String) async throws -> Payment {
        try await send("GET", "/v2/payments/\(Self.escape(referenceId))").decoded()
    }

    public func listPayments(limit: Int = 20, cursor: String? = nil) async throws -> PaymentPage {
        var path = "/v2/payments?limit=\(limit)"
        if let cursor { path += "&cursor=\(Self.escape(cursor))" }
        return try await send("GET", path).decoded()
    }

    public func cancelPayment(referenceId: String) async throws -> Payment {
        try await send("POST", "/v2/payments/\(Self.escape(referenceId))/cancel").decoded()
    }

    /// Somente chave de teste: marca o pagamento de teste como "paid" ou "expired".
    public func simulatePayment(referenceId: String, outcome: String) async throws -> Payment {
        guard apiKey.hasPrefix("mp_test_"), outcome == "paid" || outcome == "expired" else {
            throw MultiPayError(status: 0, code: "invalid_request", message: "simulate exige chave mp_test_ e outcome 'paid' ou 'expired'.", details: [], traceId: nil)
        }
        let body = try JSONSerialization.data(withJSONObject: ["outcome": outcome])
        return try await send("POST", "/v2/sandbox/payments/\(Self.escape(referenceId))/simulate", body: body).decoded()
    }

    // MARK: - HTTP

    private struct Response {
        let data: Data
        let http: HTTPURLResponse
        func header(_ name: String) -> String? { http.value(forHTTPHeaderField: name) }
        func decoded<T: Decodable>() throws -> T {
            do { return try JSONDecoder().decode(T.self, from: data) }
            catch {
                throw MultiPayError(status: http.statusCode, code: "invalid_response", message: "Resposta da API em formato inesperado.", details: [], traceId: nil)
            }
        }
    }

    private static func escape(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "/?&=+#%")   // referenceId com '/' ou '?' não pode virar outro caminho
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func send(_ method: String, _ path: String, body: Data? = nil) async throws -> Response {
        guard let url = URL(string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            throw MultiPayError(status: 0, code: "invalid_request", message: "URL inválida.", details: [], traceId: nil)
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("multipay-sdk-swift/0.1", forHTTPHeaderField: "User-Agent")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            #if canImport(FoundationNetworking)
            // Linux (Vapor/testes): FoundationNetworking não tem data(for:delegate:).
            (data, response) = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Data, URLResponse), Error>) in
                session.dataTask(with: req) { d, r, e in
                    if let e { cont.resume(throwing: e) }
                    else if let d, let r { cont.resume(returning: (d, r)) }
                    else { cont.resume(throwing: URLError(.badServerResponse)) }
                }.resume()
            }
            #else
            (data, response) = try await session.data(for: req, delegate: NoRedirect())
            #endif
        } catch {
            throw MultiPayError(status: 0, code: "network_error", message: "Falha de rede ao chamar a MultiPay API: \(error.localizedDescription)", details: [], traceId: nil)
        }
        guard let http = response as? HTTPURLResponse else {
            throw MultiPayError(status: 0, code: "invalid_response", message: "Resposta inválida.", details: [], traceId: nil)
        }
        if (200..<300).contains(http.statusCode) { return Response(data: data, http: http) }

        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
        throw MultiPayError(
            status: http.statusCode,
            code: envelope?.error?.code ?? "http_\(http.statusCode)",
            message: envelope?.error?.message ?? "Resposta inesperada da API (HTTP \(http.statusCode)).",
            details: envelope?.error?.details ?? [],
            traceId: envelope?.error?.traceId
        )
    }
}
