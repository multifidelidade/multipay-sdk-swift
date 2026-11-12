# MultiPay Demo (app de teste do SDK)

App SwiftUI mínimo para exercitar o SDK de ponta a ponta com uma chave `mp_test_`. Não é parte do pacote (o SwiftPM ignora esta pasta).

## Criar o projeto no Xcode (uma vez)
1. Xcode → *File > New > Project… > iOS > App*. Nome `MultiPayDemo`, Interface **SwiftUI**, Language **Swift**. Salve em qualquer pasta fora deste repositório.
2. Apague o `ContentView.swift` e o `<Nome>App.swift` gerados e arraste para o projeto os dois arquivos desta pasta (`MultiPayDemoApp.swift`, `ContentView.swift`), marcando *Copy items if needed*.
3. *File > Add Package Dependencies…* → URL `https://github.com/multifidelidade/multipay-sdk-swift` (versão `0.1.0`), produto `MultiPaySDK`.
   Para testar alterações locais do SDK, use *Add Local…* apontando para a pasta do repositório.
4. Deployment target: iOS 15 ou superior.

## Usar
1. Preencha **URL da API** (https), **chave `mp_test_...`** (gerada em `POST /v2/admin/api-keys`) e, se o checkout de teste estiver num host fora de `multifidelidade.app`, o host em **Hosts extras**.
2. `1. Verificar chave`: deve mostrar o lojista e `livemode=false`.
3. `2. Criar e abrir checkout`: abre a página de checkout do sandbox no `ASWebAuthenticationSession`. Toque no botão de aprovar; a janela fecha e o log mostra o retorno e o status lido na API.
4. `4. Simular 'paid'` conclui o pagamento sem usar o navegador (dispara o webhook).

## O que conferir
- A janela do checkout abre e **fecha sozinha** ao voltar (`multipaydemo://pagamento/retorno`).
- O status da URL de retorno é só dica: o app sempre confirma com `getPayment`.
- Chave `mp_live_` no campo: o SDK deve recusar (`live_key_not_allowed_in_app`).
- URL `http://` (fora de localhost): recusada (`insecure_base_url`).
- Fechar a janela no X: o log mostra "Usuário fechou a janela".
