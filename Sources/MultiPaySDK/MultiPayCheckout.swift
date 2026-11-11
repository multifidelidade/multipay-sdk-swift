#if canImport(AuthenticationServices) && canImport(UIKit)
import AuthenticationServices
import UIKit

/// Abre o checkout MultiPay em `ASWebAuthenticationSession` e devolve o resultado do retorno.
///
/// Fluxo:
///  1. Seu backend cria o pagamento (chave `mp_live_` só lá) com `returnUrl = "meuapp://pagamento/retorno"` e devolve o `paymentUrl`.
///  2. `try await MultiPayCheckout.present(paymentURL:returnURLScheme:)`.
///  3. O checkout redireciona para o deep link; a sessão fecha e você recebe o `CheckoutResult`.
///  4. Confirme o status REAL no seu backend (webhook/GET). O status da URL é só dica de UI.
///
/// Não precisa registrar o esquema no Info.plist: `ASWebAuthenticationSession` intercepta o redirecionamento.
@MainActor
public enum MultiPayCheckout {

    public enum CheckoutError: Error, LocalizedError {
        case unsafeURL(URL)
        case couldNotStart

        public var errorDescription: String? {
            switch self {
            case .unsafeURL(let url): return "URL de checkout recusada (precisa ser https e de um host MultiPay): \(url)"
            case .couldNotStart: return "Não foi possível abrir o checkout."
            }
        }
    }

    /// - Parameters:
    ///   - paymentURL: `paymentUrl` devolvido pelo seu backend.
    ///   - returnURLScheme: esquema da sua `returnUrl` (ex.: `"meuapp"`).
    ///   - extraHosts: hosts adicionais autorizados (ex.: ambiente de testes próprio).
    ///   - prefersEphemeralSession: `true` não compartilha cookies com o Safari (sem tela "quer usar o site para entrar").
    /// - Returns: o resultado do retorno, ou `nil` se o usuário fechou a janela sem concluir.
    public static func present(
        paymentURL: URL,
        returnURLScheme: String,
        extraHosts: Set<String> = [],
        prefersEphemeralSession: Bool = true
    ) async throws -> CheckoutResult? {
        guard CheckoutURL.isSafe(paymentURL, extraHosts: extraHosts) else { throw CheckoutError.unsafeURL(paymentURL) }

        let provider = PresentationProvider()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CheckoutResult?, Error>) in
            let session = ASWebAuthenticationSession(url: paymentURL, callbackURLScheme: returnURLScheme) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(returning: nil)           // usuário fechou
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: CheckoutReturn.parse(callbackURL))
                }
            }
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = prefersEphemeralSession
            // a sessão precisa ficar viva até o callback
            ActiveSession.current = session
            if !session.start() {
                ActiveSession.current = nil
                continuation.resume(throwing: CheckoutError.couldNotStart)
            }
        }
    }

    private enum ActiveSession {
        static var current: ASWebAuthenticationSession?
    }

    private final class PresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
#endif
