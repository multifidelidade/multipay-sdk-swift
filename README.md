# MultiPay SDK — iOS / Swift

Swift Package (iOS 15+, macOS 12+). Sem dependências externas.

> ⚠️ **Verificado só parcialmente.** Em 11/11/2026 o núcleo (cliente HTTP, parsing do retorno, validação de URL) compilou e passou 9 testes no Linux (Swift 5.9, Docker).
> **Ainda não rodou em Apple:** `WebhookVerifier` (CryptoKit) e `MultiPayCheckout` (ASWebAuthenticationSession/UIKit) só compilam no Xcode. Abra `Package.swift` no Xcode, rode `⌘U` e teste no simulador antes de publicar.
> Para repetir no Linux: `docker run --rm -v "$PWD:/src:ro" swift:5.9 bash -c "cp -r /src /w && cd /w && swift test"`.
> A lógica espelha o SDK Kotlin (20 testes verdes) e usa o mesmo vetor de assinatura de webhook do servidor .NET e do MCP.

## Princípio de segurança

**A chave `mp_live_` nunca vai para o app.** O app mostra o checkout; quem cria o pagamento é o **seu backend**.

```
App ──"quero pagar o pedido 123"──► Seu backend ──POST /v2/payments (mp_live_)──► MultiPay
App ◄────────── paymentUrl ──────── Seu backend
App ── ASWebAuthenticationSession(paymentUrl) ──► checkout (PIX/cartão) ──► meuapp://pagamento/retorno?referenceId=123&status=paid
App ──"e o pedido 123, pagou?"──► Seu backend (confirma por webhook/GET) ──► App
```

`MultiPayClient.forApp(...)` **recusa** `mp_live_`. `forBackend(...)` (para Vapor etc.) está marcado como indisponível em iOS.

## Instalação

Xcode → *Add Package Dependencies…* → URL do repositório do SDK → `MultiPaySDK`.
Ou `Package.swift`: `.package(url: "<repo>", from: "0.1.0")`.

## Uso no app (SwiftUI)

```swift
import MultiPaySDK

@MainActor
func pagar(pedido: Pedido) async {
    do {
        // 1) seu backend cria o pagamento (mp_live_ fica lá) e devolve o paymentUrl
        let paymentURL = try await meuBackend.criarPagamento(pedido.id)   // URL

        // 2) abre o checkout e espera o retorno (returnUrl = "meuapp://pagamento/retorno")
        guard let result = try await MultiPayCheckout.present(paymentURL: paymentURL, returnURLScheme: "meuapp") else {
            return   // usuário fechou a janela
        }

        // 3) o status da URL é só dica: confirme no backend
        switch result.status {
        case .paid:     try await meuBackend.confirmar(referenceId: result.referenceId)
        case .canceled, .expired: mostrarErro()
        default: break
        }
    } catch {
        mostrarErro(error.localizedDescription)
    }
}
```

`present` valida que a URL é `https` e de um host MultiPay antes de abrir (`extraHosts:` para seu ambiente de testes).

## Testando sem pagar (sandbox)

Com uma chave `mp_test_` o checkout é uma página fake com botões. Para concluir sem tocar no navegador:

```swift
let client = try MultiPayClient.forApp(testApiKey: "mp_test_...")
let created = try await client.createPayment(.init(referenceId: "PED-1", amountCents: 1500, cpf: "…",
                                                   callbackUrl: "https://…/hook", returnUrl: "meuapp://pagamento/retorno"))
_ = try await client.simulatePayment(referenceId: "PED-1", outcome: "paid")   // dispara o webhook
```

## Backend Swift (Vapor): verificar webhook

```swift
let ok = WebhookVerifier.verify(secret: secret, header: req.headers.first(name: WebhookVerifier.headerName), rawBody: rawBodyString)
guard ok == .valid else { throw Abort(.badRequest) }
```
