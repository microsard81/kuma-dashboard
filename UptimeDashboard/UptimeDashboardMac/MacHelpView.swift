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
    <style>
    body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;max-width:100%;margin:40px auto;padding:0 40px;color:#222;line-height:1.7;font-size:14px}
    h1{font-size:26px;margin-bottom:4px}
    h2{font-size:18px;margin-top:32px;border-bottom:1px solid #ddd;padding-bottom:6px}
    h3{font-size:15px;margin-top:20px}
    ul{padding-left:20px}li{margin-bottom:5px}
    table{border-collapse:collapse;width:100%;margin:12px 0}
    th,td{border:1px solid #ddd;padding:8px 12px;text-align:left}
    th{background:#f5f5f7;font-weight:600}
    .key{background:#f0f0f0;padding:2px 7px;border-radius:4px;font-family:SFMono-Regular,monospace;font-size:12px}
    .green{color:#34c759}.yellow{color:#f5a623}.red{color:#ff3b30}.blue{color:#007aff}.purple{color:#af52de}.orange{color:#ff9500}
    hr{border:none;border-top:1px solid #e0e0e0;margin:24px 0}
    </style>
    </head><body>
    <h1>Dashboard INVA MAC</h1>
    <hr>
    <p>Applicazione di monitoraggio uptime multi-sonda per i servizi IN.VA. Monitora lo stato dei servizi tramite cinque sonde indipendenti, i sensori del datacenter (temperatura, potenza, UPS, generatori) e invia notifiche push al cambio di stato.</p>

    <h2>Struttura dell'interfaccia</h2>
    <p>L'app usa un layout <strong>Sidebar + Detail</strong>:</p>
    <ul>
    <li><strong>Sidebar (sinistra)</strong> — Elenca le 5 sezioni con icona, nome e indicatore di stato. In cima c'è il pulsante "Panoramica" per tornare alla vista d'insieme.</li>
    <li><strong>Pannello Detail (destra)</strong> — Mostra il contenuto della sezione selezionata, oppure la Panoramica.</li>
    </ul>

    <h2>Panoramica</h2>
    <p>Quando nessuna sezione è selezionata (oppure cliccando "Panoramica" nella sidebar), il pannello destro mostra:</p>
    <ul>
    <li><strong>Card sezioni</strong> — Una card per ognuna delle 5 sezioni con icona, nome e stato riassuntivo (es. "OK (10)", "2/10 DOWN", "1/5 Critical"). Clicca una card per entrare nella sezione.</li>
    <li><strong>In evidenza</strong> — Sotto le card, mostra le risorse che hai pinnato (vedi sezione dedicata).</li>
    </ul>
    <p>Le card si aggiornano in tempo reale: se un sensore va in Critical o un portale va DOWN, il conteggio e il colore cambiano immediatamente.</p>

    <h2>Sezioni</h2>
    <table>
    <tr><th>Sezione</th><th>Contenuto</th></tr>
    <tr><td>Portali</td><td>Stato dei servizi web monitorati da 5 sonde indipendenti. Ogni monitor mostra lo stato per sonda e una sparkline storica.</td></tr>
    <tr><td>Temperatura</td><td>Sensori di temperatura del datacenter (°C) con grafico storico.</td></tr>
    <tr><td>Potenza</td><td>Sensori di potenza elettrica (kW) con grafico storico.</td></tr>
    <tr><td>UPS</td><td>Stato UPS: batteria, sorgente, capacità, durata, fasi.</td></tr>
    <tr><td>Generatori</td><td>Stato gruppi elettrogeni: controller, tensione, carico, carburante.</td></tr>
    </table>

    <h2>Sonde di monitoraggio</h2>
    <p>Ogni portale viene verificato da 5 sonde indipendenti distribuite geograficamente:</p>
    <table>
    <tr><th>Sonda</th><th>Posizione</th></tr>
    <tr><td>k1 — Aruba</td><td>Bergamo</td></tr>
    <tr><td>k2 — TIM</td><td>Sestu (CA)</td></tr>
    <tr><td>k3 — ILIAD</td><td>Sinnai (CA)</td></tr>
    <tr><td>n1 — NodePing</td><td>Europa</td></tr>
    <tr><td>u1 — Uptime</td><td>Globale</td></tr>
    </table>

    <h2>Stato globale</h2>
    <ul>
    <li><span class="green">●</span> <strong>GREEN</strong> — Tutte le risorse sono UP su tutte le sonde</li>
    <li><span class="yellow">●</span> <strong>YELLOW</strong> — Almeno una risorsa ha stato diverso tra le sonde</li>
    <li><span class="red">●</span> <strong>RED</strong> — Almeno una risorsa è DOWN su tutte le sonde</li>
    </ul>
    <p>Lo stato globale è indicato dal pallino colorato nella sidebar accanto a "Portali" e nell'icona della menu bar.</p>

    <h2>Sensori datacenter</h2>
    <p>I sensori monitorano temperatura, potenza, stato UPS e gruppi elettrogeni. Ogni sensore ha una soglia individuale definita dal sistema di monitoraggio:</p>
    <ul>
    <li><span class="orange">●</span> Normale (temperatura/generatori) / <span class="blue">●</span> Normale (potenza) / <span class="purple">●</span> Normale (UPS)</li>
    <li><span class="red">●</span> <strong>Critical</strong> — Soglia superata, richiede attenzione immediata</li>
    </ul>
    <p>I sensori possono mostrare valori numerici (es. 23.5 °C, 100 %) o di stato (es. "Normale", "AUTOMATICO"). Passa il mouse sul grafico sparkline per vedere valore e orario del punto.</p>

    <h2>In evidenza (Pin)</h2>
    <p>Puoi "pinnare" qualsiasi risorsa per tenerla sempre visibile nella Panoramica:</p>
    <ul>
    <li><strong>Aggiungere</strong> — Click destro (o Control+click) su un monitor o sensore in qualsiasi sezione → "Aggiungi a In evidenza"</li>
    <li><strong>Rimuovere</strong> — Click destro sulla card pinnata nella Panoramica → "Rimuovi da In evidenza"</li>
    <li><strong>Navigare</strong> — Doppio click su una card pinnata apre la sezione corrispondente</li>
    </ul>
    <p>Le card pinnate mostrano icona, nome e valore/stato live che si aggiorna in tempo reale.</p>

    <h2>Riordino manuale</h2>
    <p>In ogni sezione (Portali, Temperatura, Potenza, UPS, Generatori) puoi riordinare gli elementi:</p>
    <ul>
    <li>Clicca il pulsante <strong>↑↓</strong> nell'intestazione della sezione per entrare in modalità riordino</li>
    <li>Trascina le righe per cambiare l'ordine</li>
    <li>Clicca <strong>✓</strong> per confermare — l'ordine viene salvato e mantenuto tra i riavvii</li>
    </ul>

    <h2>Notifiche push</h2>
    <p>L'app riceve notifiche push native quando lo stato cambia:</p>
    <ul>
    <li><span class="red">●</span> Servizi DOWN (una o più risorse non raggiungibili)</li>
    <li><span class="yellow">●</span> Incongruenza tra sonde (mismatch)</li>
    <li><span class="green">●</span> Tutto OK (ripristino alla normalità)</li>
    <li><span class="red">●</span> Alert sensori (temperatura/potenza/UPS fuori soglia)</li>
    <li><span class="green">●</span> Sensore rientrato nella norma</li>
    </ul>
    <p>Clicca l'icona 🔔 nella toolbar per vedere lo storico notifiche.</p>

    <h3>Soglia notifica</h3>
    <p>Puoi configurare quante sonde devono essere DOWN prima di ricevere la notifica (da 1 a 5). Si applica solo alla categoria Portali. Impostazioni → Soglia notifica.</p>

    <h3>Categorie notifiche</h3>
    <p>Puoi scegliere quali categorie di notifiche ricevere (Impostazioni → toggle per categoria):</p>
    <ul>
    <li><strong>Portali</strong> — servizi DOWN o ripristinati (soggetta a soglia sonde)</li>
    <li><strong>Temperatura</strong> — alert sensori ambientali</li>
    <li><strong>Potenza</strong> — alert sensori potenza</li>
    <li><strong>UPS</strong> — alert UPS</li>
    <li><strong>Generatori</strong> — alert gruppi elettrogeni</li>
    </ul>
    <p>La configurazione è per-dispositivo.</p>

    <h2>Menu bar</h2>
    <p>L'app mostra un'icona nella barra dei menu con un pallino colorato che indica lo stato globale. Clicca per vedere un riepilogo rapido: risorse anomale, ultimo aggiornamento, e azioni (Aggiorna, Apri Dashboard, Impostazioni, Esci).</p>

    <h2>Autenticazione biometrica</h2>
    <p>Al primo login con username + password + 2FA, l'app salva un token nel Keychain protetto da Touch ID o Apple Watch. Ai successivi avvii puoi sbloccare con la biometria senza reinserire le credenziali. Il token scade dopo 90 giorni.</p>

    <h2>Limiti Grafici</h2>
    <p>Nelle Impostazioni puoi personalizzare i range dell'asse Y dei grafici sparkline per ogni tipo di sensore:</p>
    <table>
    <tr><th>Unità</th><th>Min default</th><th>Max default</th></tr>
    <tr><td>Temperatura (°C)</td><td>15</td><td>60</td></tr>
    <tr><td>Tensione (V)</td><td>0</td><td>250</td></tr>
    <tr><td>Capacità (%)</td><td>0</td><td>100</td></tr>
    <tr><td>Durata (min)</td><td>1</td><td>280</td></tr>
    <tr><td>Potenza (kW)</td><td>0</td><td>100</td></tr>
    </table>
    <p>Modifica i valori per adattare la scala dei grafici alle tue esigenze. I valori fuori range verranno comunque mostrati ma il grafico sarà troncato.</p>

    <h2>Scorciatoie</h2>
    <table>
    <tr><th>Tasto</th><th>Azione</th></tr>
    <tr><td><span class="key">⌘R</span></td><td>Aggiorna Dashboard</td></tr>
    <tr><td><span class="key">⌘,</span></td><td>Impostazioni</td></tr>
    <tr><td><span class="key">⌘Q</span></td><td>Esci</td></tr>
    </table>

    <h2>Supporto</h2>
    <p>Per assistenza tecnica contattare il team ABISSI S.r.l.</p>
    </body></html>
    """
}
