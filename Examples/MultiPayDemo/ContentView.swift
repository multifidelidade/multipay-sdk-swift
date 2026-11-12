import SwiftUI
import MultiPaySDK

/// App de teste do SDK. Fluxo: whoami -> criar pagamento -> abrir checkout (ASWebAuthenticationSession)
/// -> ler o retorno -> consultar o status na API. Use SOMENTE chave mp_test_.
struct ContentView: View {
    @AppStorage("baseURL") private var baseURL = "https://api.multifidelidade.app"
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("extraHosts") private var extraHosts = ""      // ex.: homolog.exemplo.com, separados por vírgula
    @AppStorage("cpf") private var cpf = "52998224725"         // CPF de teste válido
    @AppStorage("amount") private var amountCents = "1500"
    @State private var lastRef = ""
    @State private var log: [String] = []
    @State private var busy = false

    private let returnScheme = "multipaydemo"

    var body: some View {
        NavigationStack {
            Form {
                Section("Ambiente") {
                    TextField("URL da API (https)", text: $baseURL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Chave mp_test_...", text: $apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Hosts extras do checkout (opcional)", text: $extraHosts).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Pagamento") {
                    TextField("CPF", text: $cpf).keyboardType(.numberPad)
                    TextField("Valor em centavos", text: $amountCents).keyboardType(.numberPad)
                }
                Section("Ações") {
                    Button("1. Verificar chave (whoami)") { run(whoami) }
                    Button("2. Criar e abrir checkout") { run(payFlow) }
                    Button("3. Consultar último pagamento") { run(fetchLast) }
                    Button("4. Simular 'paid' (sandbox)") { run { try await simulate("paid") } }
                    Button("5. Cancelar último pagamento") { run(cancelLast) }
                }
                .disabled(busy)
                if busy { ProgressView() }
                Section("Log") {
                    if !lastRef.isEmpty { Text("referenceId: \(lastRef)").font(.caption.monospaced()) }
                    ForEach(Array(log.enumerated().reversed()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("MultiPay Demo")
        }
    }

    // MARK: ações

    private func makeClient() throws -> MultiPayClient {
        guard let url = URL(string: baseURL) else { throw URLError(.badURL) }
        return try MultiPayClient.forApp(testApiKey: apiKey.trimmingCharacters(in: .whitespaces), baseURL: url)
    }

    private func whoami() async throws {
        let me = try await makeClient().whoami()
        add("OK: lojista \(me.merchantName) (#\(me.merchantId)), livemode=\(me.livemode)")
    }

    private func payFlow() async throws {
        let client = try makeClient()
        let ref = "DEMO-\(Int(Date().timeIntervalSince1970))"
        let request = CreatePaymentRequest(
            referenceId: ref,
            amountCents: Int64(amountCents) ?? 1500,
            cpf: cpf,
            callbackUrl: "https://example.com/webhook",
            returnUrl: "\(returnScheme)://pagamento/retorno",
            message: "Teste do SDK iOS"
        )
        let created = try await client.createPayment(request)
        lastRef = ref
        add("Criado \(ref): status=\(created.payment.status), replayed=\(created.replayed)")
        add("paymentUrl: \(created.payment.paymentUrl)")

        guard let url = created.payment.checkoutURL else { add("paymentUrl inválida"); return }
        let hosts = Set(extraHosts.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let result = try await MultiPayCheckout.present(paymentURL: url, returnURLScheme: returnScheme, extraHosts: hosts)
        if let result {
            add("Retorno do checkout: ref=\(result.referenceId ?? "-"), status=\(result.status) (dica; confirme na API)")
        } else {
            add("Usuário fechou a janela sem concluir.")
        }
        let p = try await client.getPayment(referenceId: ref)
        add("Status na API: \(p.status)")
    }

    private func fetchLast() async throws {
        guard !lastRef.isEmpty else { add("Crie um pagamento primeiro."); return }
        let p = try await makeClient().getPayment(referenceId: lastRef)
        add("Status na API: \(p.status), pago em: \(p.paidAt ?? "-")")
    }

    private func simulate(_ outcome: String) async throws {
        guard !lastRef.isEmpty else { add("Crie um pagamento primeiro."); return }
        let p = try await makeClient().simulatePayment(referenceId: lastRef, outcome: outcome)
        add("Simulado \(outcome): status=\(p.status)")
    }

    private func cancelLast() async throws {
        guard !lastRef.isEmpty else { add("Crie um pagamento primeiro."); return }
        let p = try await makeClient().cancelPayment(referenceId: lastRef)
        add("Cancelado: status=\(p.status)")
    }

    // MARK: util

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }       // reabilita os botões em qualquer caminho
            do { try await work() }
            catch let e as MultiPayError { add("ERRO \(e.code) (HTTP \(e.status)): \(e.message)") }
            catch { add("ERRO: \(error.localizedDescription)") }
        }
    }

    private func add(_ s: String) { log.append(s) }
}
