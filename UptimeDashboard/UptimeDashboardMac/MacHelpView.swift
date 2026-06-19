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
    <style>body{font-family:-apple-system,sans-serif;max-width:650px;margin:40px auto;padding:0 20px;color:#333;line-height:1.6}h1{font-size:24px}h2{font-size:18px;margin-top:24px}h3{font-size:15px;margin-top:16px}ul{padding-left:20px}li{margin-bottom:4px}.key{background:#eee;padding:2px 6px;border-radius:3px;font-family:monospace;font-size:13px}</style>
    </head><body>
    <h1>Dashboard INVA MAC</h1>
    <p>Applicazione di monitoraggio uptime multi-sonda e sensori datacenter per i servizi IN.VA.</p>

    <h2>Schermata principale</h2>
    <p>La dashboard mostra 5 sezioni (affiancate se la finestra è larga, impilate se stretta):</p>
    <ul>
    <li><strong>Portali</strong> — Stato dei servizi web monitorati da 5 sonde indipendenti</li>
    <li><strong>Temperatura (°C)</strong> — Sensori di temperatura del datacenter</li>
    <li><strong>Potenza (kW)</strong> — Sensori di potenza elettrica</li>
    <li><strong>UPS</strong> — Stato UPS: batteria, sorgente, capacità, durata, fasi</li>
    <li><strong>Generatori</strong> — Stato gruppi elettrogeni: controller, tensione, carico, carburante</li>
    </ul>

    <h2>Sonde</h2>
    <ul>
    <li><strong>Aruba</strong> — Bergamo</li>
    <li><strong>TIM</strong> — Sestu (CA)</li>
    <li><strong>ILIAD</strong> — Sinnai (CA)</li>
    <li><strong>NodePing</strong> — Europa</li>
    <li><strong>Uptime</strong> — Globale</li>
    </ul>

    <h2>Stato globale</h2>
    <ul>
    <li>🟢 <strong>GREEN</strong> — Tutto UP</li>
    <li>🟡 <strong>YELLOW</strong> — Mismatch tra sonde</li>
    <li>🔴 <strong>RED</strong> — DOWN su tutte le sonde</li>
    </ul>

    <h2>Sensori datacenter</h2>
    <p>I sensori monitorano temperatura, potenza, stato UPS e gruppi elettrogeni. Ogni sensore ha una soglia individuale dal sistema di monitoraggio:</p>
    <ul>
    <li>🟠 <strong>Normale (temperatura)</strong> / 🔵 <strong>Normale (potenza)</strong> / 🟣 <strong>Normale (UPS)</strong> / 🟠 <strong>Normale (generatori)</strong></li>
    <li>🔴 <strong>Critical</strong> — Soglia superata, richiede attenzione immediata</li>
    </ul>
    <p>I sensori possono mostrare valori numerici (es. 23.5 °C, 100 %) o di stato (es. "Normale", "AUTOMATICO").</p>
    <p>Passa il mouse sul grafico per vedere valore e orario del punto.</p>

    <h2>Notifiche</h2>
    <p>Ricevi notifiche push quando lo stato cambia:</p>
    <ul>
    <li>🔴 Servizi DOWN</li>
    <li>🟡 Incongruenza tra sonde</li>
    <li>🟢 Tutto OK (ripristino)</li>
    <li>🔴🟡🟢 Alert sensori (temperature/potenza fuori soglia o rientrate)</li>
    </ul>
    <p>Clicca l'icona 🔔 nella toolbar per vedere lo storico notifiche (ultimo mese).</p>

    <h2>Soglia notifica</h2>
    <p>Configura quante sonde devono essere DOWN prima di ricevere la notifica (1–5). Impostazioni → Soglia notifica.</p>

    <h2>Scorciatoie</h2>
    <ul>
    <li><span class="key">⌘R</span> — Aggiorna Dashboard</li>
    <li><span class="key">⌘,</span> — Impostazioni</li>
    <li><span class="key">⌘Q</span> — Nascondi nella menu bar</li>
    <li><span class="key">⌥⌘Q</span> — Esci definitivamente</li>
    </ul>

    <h2>Supporto</h2>
    <p>Per assistenza contattare ABISSI S.r.l.</p>
    </body></html>
    """
}
