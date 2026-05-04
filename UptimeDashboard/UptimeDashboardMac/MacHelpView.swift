import SwiftUI
import WebKit

/// Finestra Help con documentazione HTML renderizzata tramite WKWebView.
struct MacHelpView: View {
    var body: some View {
        HelpWebView()
            .frame(minWidth: 500, minHeight: 400)
    }
}

/// Wrapper NSViewRepresentable per WKWebView che carica l'HTML dell'help.
struct HelpWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")

        if let url = Bundle.main.url(forResource: "index",
                                      withExtension: "html",
                                      subdirectory: "UptimeDashboardMac.help/Contents/Resources") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            // Fallback: HTML inline
            let html = Self.fallbackHTML
            webView.loadHTMLString(html, baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static let fallbackHTML = """
    <!DOCTYPE html>
    <html lang="it">
    <head><meta charset="utf-8"><title>Aiuto</title>
    <style>body{font-family:-apple-system,sans-serif;max-width:600px;margin:40px auto;padding:0 20px;color:#333;line-height:1.6}h1{font-size:24px}h2{font-size:18px;margin-top:24px}</style>
    </head><body>
    <h1>Dashboard INVA MAC</h1>
    <p>Applicazione di monitoraggio uptime multi-sonda per i servizi IN.VA.</p>
    <h2>Sonde</h2>
    <ul>
    <li><strong>k1</strong> — Aruba Bergamo</li>
    <li><strong>k2</strong> — TIM Sestu</li>
    <li><strong>k3</strong> — ILIAD Sinnai</li>
    <li><strong>n1</strong> — NodePing Europe</li>
    <li><strong>u1</strong> — Uptime</li>
    </ul>
    <h2>Stato globale</h2>
    <ul>
    <li>🟢 <strong>GREEN</strong> — Tutto UP</li>
    <li>🟡 <strong>YELLOW</strong> — Mismatch tra sonde</li>
    <li>🔴 <strong>RED</strong> — DOWN su tutte le sonde</li>
    </ul>
    <h2>Soglia notifica</h2>
    <p>Configura quante sonde devono essere DOWN prima di ricevere la notifica (1–5). Impostazioni → Soglia notifica.</p>
    <h2>Scorciatoie</h2>
    <ul>
    <li><strong>⌘R</strong> — Aggiorna Dashboard</li>
    <li><strong>⌘,</strong> — Impostazioni</li>
    <li><strong>⌘Q</strong> — Nascondi nella menu bar</li>
    <li><strong>⌥⌘Q</strong> — Esci definitivamente</li>
    </ul>
    <h2>Supporto</h2>
    <p>Per assistenza contattare ABISSI S.r.l.</p>
    </body></html>
    """
}
