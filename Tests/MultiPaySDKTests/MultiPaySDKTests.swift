import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MultiPaySDK

final class CheckoutReturnTests: XCTestCase {
    func testParsesReferenceAndStatus() {
        let r = CheckoutReturn.parse(URL(string: "meuapp://pagamento/retorno?referenceId=PED%201&status=paid"))
        XCTAssertEqual(r?.referenceId, "PED 1")
        XCTAssertEqual(r?.status, .paid)
    }

    func testUnknownOrMissingStatus() {
        XCTAssertEqual(CheckoutReturn.parse(URL(string: "meuapp://x?status=banana"))?.status, .unknown)
        XCTAssertEqual(CheckoutReturn.parse(URL(string: "meuapp://x"))?.status, .unknown)
        XCTAssertNil(CheckoutReturn.parse(nil))
    }
}

final class CheckoutURLTests: XCTestCase {
    func testAcceptsOnlyHttpsMultiPayHosts() {
        XCTAssertTrue(CheckoutURL.isSafe(URL(string: "https://multifidelidade.app/site/pay/checkout?idP=abc")))
        XCTAssertTrue(CheckoutURL.isSafe(URL(string: "https://api.multifidelidade.app/v2/sandbox/checkout/x")))
        XCTAssertFalse(CheckoutURL.isSafe(URL(string: "http://multifidelidade.app/x")))
        XCTAssertFalse(CheckoutURL.isSafe(URL(string: "https://multifidelidade.app.evil.com/x")))
        XCTAssertFalse(CheckoutURL.isSafe(URL(string: "https://user:pass@multifidelidade.app/x")))
        XCTAssertFalse(CheckoutURL.isSafe(URL(string: "javascript:alert(1)")))
        XCTAssertFalse(CheckoutURL.isSafe(nil))
        XCTAssertTrue(CheckoutURL.isSafe(URL(string: "https://pay.minhaloja.com/x"), extraHosts: ["minhaloja.com"]))
    }
}

#if canImport(CryptoKit)
final class WebhookVerifierTests: XCTestCase {
    private let secret = "whsec_vetor_de_teste"
    private let body = #"{"id":"evt_test_1_paid","type":"payment.paid"}"#

    func testVectorMatchesServerAndMCP() {
        // mesmo vetor do .NET (WebhookSignerTests), do MCP (Node) e do SDK Kotlin
        XCTAssertEqual(
            WebhookVerifier.sign(secret: secret, timestamp: 1731323700, rawBody: body),
            "6935acef1b3f9ab0883c8079b3cad5aefd921ac25a6142e463ce823b6ee75b19"
        )
    }

    func testVerifyAndReject() {
        let t = 1731323700
        let now = Date(timeIntervalSince1970: TimeInterval(t + 10))
        let header = "t=\(t),v1=\(WebhookVerifier.sign(secret: secret, timestamp: t, rawBody: body))"
        XCTAssertEqual(WebhookVerifier.verify(secret: secret, header: header, rawBody: body, now: now), .valid)
        XCTAssertEqual(WebhookVerifier.verify(secret: secret, header: header, rawBody: body + " ", now: now), .invalid(.signatureMismatch))
        XCTAssertEqual(WebhookVerifier.verify(secret: "outro", header: header, rawBody: body, now: now), .invalid(.signatureMismatch))
        XCTAssertEqual(WebhookVerifier.verify(secret: secret, header: header, rawBody: body, now: now.addingTimeInterval(3600)), .invalid(.timestampOutOfTolerance))
        XCTAssertEqual(WebhookVerifier.verify(secret: secret, header: nil, rawBody: body), .invalid(.missingHeader))
        XCTAssertEqual(WebhookVerifier.verify(secret: secret, header: "lixo", rawBody: body), .invalid(.malformedHeader))
    }
}
#endif

/// URLProtocol que responde sem rede.
final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data, [String: String]))?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let (status, data, headers) = Self.handler?(request) ?? (500, Data(), [:])
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ClientTests: XCTestCase {
    private let testKey = "mp_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    private let liveKey = "mp_live_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

    private func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    private func payment(_ ref: String, status: String = "pending") -> Data {
        Data(#"{"referenceId":"\#(ref)","paymentUrl":"https://multifidelidade.app/c/\#(ref)","status":"\#(status)","amountCents":1500,"currency":"BRL","livemode":false,"campoNovo":1}"#.utf8)
    }

    private func request(_ ref: String = "PED-1") -> CreatePaymentRequest {
        CreatePaymentRequest(referenceId: ref, amountCents: 1500, cpf: "52998224725",
                             callbackUrl: "https://loja.test/hook", returnUrl: "meuapp://pagamento/retorno")
    }

    override func setUp() {
        MockURLProtocol.requests = []
        MockURLProtocol.handler = nil
    }

    func testAppRejectsLiveKey() {
        XCTAssertThrowsError(try MultiPayClient.forApp(testApiKey: liveKey, session: session())) {
            XCTAssertEqual(($0 as? MultiPayError)?.code, "live_key_not_allowed_in_app")
        }
    }

    func testRejectsInvalidKeyAndInsecureBaseURL() {
        XCTAssertThrowsError(try MultiPayClient.forApp(testApiKey: "mp_test_curta", session: session()))
        XCTAssertThrowsError(try MultiPayClient.forApp(testApiKey: testKey, baseURL: URL(string: "http://api.exemplo.com")!, session: session()))
    }

    func testCreateSendsBearerAndReportsReplay() async throws {
        MockURLProtocol.handler = { _ in (201, self.payment("PED-1"), [:]) }
        let client = try MultiPayClient.forApp(testApiKey: testKey, session: session())
        let created = try await client.createPayment(request())
        XCTAssertFalse(created.replayed)
        XCTAssertEqual(created.payment.checkoutStatus, .pending)
        XCTAssertEqual(MockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer \(testKey)")

        MockURLProtocol.handler = { _ in (200, self.payment("PED-1"), ["Idempotent-Replayed": "true"]) }
        let replay = try await client.createPayment(request())
        XCTAssertTrue(replay.replayed)
    }

    func testErrorEnvelopeIsDecoded() async throws {
        let body = #"{"error":{"code":"validation_error","message":"invalido","details":[{"field":"cpf","message":"CPF invalido."}],"traceId":"t-1"}}"#
        MockURLProtocol.handler = { _ in (422, Data(body.utf8), [:]) }
        let client = try MultiPayClient.forApp(testApiKey: testKey, session: session())
        do {
            _ = try await client.createPayment(request())
            XCTFail("deveria lançar")
        } catch let e as MultiPayError {
            XCTAssertEqual(e.status, 422)
            XCTAssertEqual(e.code, "validation_error")
            XCTAssertEqual(e.details.first?.field, "cpf")
            XCTAssertEqual(e.traceId, "t-1")
        }
    }

    func testReferenceIdIsEscapedInPath() async throws {
        MockURLProtocol.handler = { _ in (200, self.payment("x"), [:]) }
        let client = try MultiPayClient.forApp(testApiKey: testKey, session: session())
        _ = try await client.getPayment(referenceId: "a/b c")
        XCTAssertEqual(MockURLProtocol.requests.last?.url?.absoluteString.hasSuffix("/v2/payments/a%2Fb%20c"), true)
    }

    func testSimulateOnlyWithTestKey() async throws {
        let client = try MultiPayClient.forApp(testApiKey: testKey, session: session())
        MockURLProtocol.handler = { _ in (200, self.payment("PED-1", status: "paid"), [:]) }
        let p = try await client.simulatePayment(referenceId: "PED-1", outcome: "paid")
        XCTAssertEqual(p.checkoutStatus, .paid)
        do {
            _ = try await client.simulatePayment(referenceId: "PED-1", outcome: "banana")
            XCTFail("deveria lançar")
        } catch let e as MultiPayError { XCTAssertEqual(e.code, "invalid_request") }
    }

    func testBaseURLPrefixIsKeptInRequestURL() async throws {
        MockURLProtocol.handler = { _ in (201, self.payment("PED-1"), [:]) }
        for base in ["https://api.multifidelidade.app/integracoes", "https://api.multifidelidade.app/integracoes/"] {
            let client = try MultiPayClient.forApp(testApiKey: testKey, baseURL: URL(string: base)!, session: session())
            _ = try await client.createPayment(request())
            XCTAssertEqual(MockURLProtocol.requests.last?.url?.absoluteString,
                           "https://api.multifidelidade.app/integracoes/v2/payments", "base: \(base)")
        }
        XCTAssertEqual(MultiPayClient.defaultBaseURL.absoluteString, "https://api.multifidelidade.app/integracoes")
    }
}
