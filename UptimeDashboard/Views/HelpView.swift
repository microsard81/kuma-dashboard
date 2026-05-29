import SwiftUI

/// Vista Help in-app con documentazione completa per l'utente.
struct HelpView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // Panoramica
                section("Panoramica") {
                    Text("Dashboard INVA monitora lo stato dei portali web e dei sensori del datacenter (temperatura e potenza). I dati si aggiornano automaticamente ogni 60 secondi.")
                }

                // Schermata principale
                section("Schermata principale") {
                    Text("La schermata principale mostra 3 aree:")
                        .font(.subheadline)
                    areaRow(icon: "globe", color: .green, title: "Portali", description: "Stato dei servizi web monitorati da 5 sonde indipendenti")
                    areaRow(icon: "thermometer.medium", color: .green, title: "Temperatura", description: "Sensori di temperatura del datacenter (°C)")
                    areaRow(icon: "bolt.fill", color: .blue, title: "Potenza", description: "Sensori di potenza degli inverter (kW)")
                    Text("Il pallino colorato indica lo stato globale dell'area. Tocca una card per vedere i dettagli.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Portali
                section("Portali — Le 5 sonde") {
                    probeRow("Aruba", location: "Bergamo")
                    probeRow("TIM", location: "Sestu (CA)")
                    probeRow("ILIAD", location: "Sinnai (CA)")
                    probeRow("NodePing", location: "Europa")
                    probeRow("Uptime", location: "Globale")
                    Divider()
                    statusRow(color: .green, label: "UP", description: "Tutte le sonde vedono la risorsa operativa")
                    statusRow(color: .yellow, label: "Mismatch", description: "Alcune sonde vedono DOWN, altre UP")
                    statusRow(color: .red, label: "DOWN", description: "Tutte le sonde vedono la risorsa non raggiungibile")
                }

                // Sensori
                section("Sensori datacenter") {
                    Text("I sensori misurano temperatura e potenza degli inverter. Ogni sensore ha soglie configurabili:")
                        .font(.subheadline)
                    statusRow(color: .green, label: "Normale", description: "Temperatura: valore entro i limiti. Potenza: valore sopra la soglia minima")
                    statusRow(color: .yellow, label: "Warning", description: "Temperatura troppo alta o potenza troppo bassa (soglia warning)")
                    statusRow(color: .red, label: "Critical", description: "Temperatura molto alta o potenza molto bassa (soglia critical)")
                    Divider()
                    infoRow(icon: "chart.xyaxis.line", text: "Ogni sensore mostra un grafico con gli ultimi 60 valori. Tocca il grafico per vedere valore e orario del punto.")
                }

                // Storico
                section("Storico (barre colorate)") {
                    Text("Nella sezione Portali, ogni risorsa mostra una barra con gli ultimi 60 campionamenti. I colori indicano lo stato in quel momento.")
                        .font(.subheadline)
                    Text("Tocca e scorri sulla barra per vedere l'orario e il dettaglio delle sonde in quel momento.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Notifiche
                section("Notifiche push") {
                    Text("Ricevi notifiche push quando lo stato cambia:")
                        .font(.subheadline)
                    notifRow("🔴", text: "Servizi DOWN — risorse completamente irraggiungibili")
                    notifRow("🟡", text: "Incongruenza — alcune sonde vedono DOWN")
                    notifRow("🟢", text: "Tutto OK — tutti i servizi ripristinati")
                    Divider()
                    notifRow("🔴", text: "Sensore critical — temperatura troppo alta o potenza troppo bassa")
                    notifRow("🟡", text: "Sensore warning — soglia di attenzione superata")
                    notifRow("🟢", text: "Sensore rientrato — valore tornato nella norma")
                }

                // Soglia
                section("Soglia notifica") {
                    Text("Puoi configurare quante sonde devono essere DOWN prima di ricevere la notifica (1–5).")
                        .font(.subheadline)
                    Text("Esempio: con soglia 3, ricevi la notifica solo quando almeno 3 sonde vedono DOWN. Le notifiche sensori arrivano sempre, indipendentemente dalla soglia.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Impostazioni
                section("Impostazioni") {
                    infoRow(icon: "paintbrush", text: "Tema: Auto, Chiaro o Scuro")
                    infoRow(icon: "arrow.up.arrow.down", text: "Ordinamento: per gravità, alfabetico o stato globale")
                    infoRow(icon: "arrow.clockwise", text: "Auto-refresh: intervallo di aggiornamento automatico")
                    infoRow(icon: "bell", text: "Notifiche: abilita/disabilita e configura la soglia")
                    infoRow(icon: "hand.tap", text: "Feedback aptico: vibrazione al tocco sullo storico")
                    infoRow(icon: "faceid", text: "Sicurezza: accesso rapido con Face ID / Touch ID")
                }

                // Riordino manuale
                section("Riordino manuale") {
                    infoRow(icon: "arrow.up.arrow.down", text: "Scorri verso destra su un elemento (portale, sensore o sezione nella home) per far apparire il pulsante di riordino.")
                    infoRow(icon: "hand.draw", text: "In modalità riordino, trascina gli elementi per disporli nell'ordine che preferisci.")
                    infoRow(icon: "checkmark.circle", text: "Tocca \"Termina\" in alto a destra per salvare. L'ordine viene mantenuto anche chiudendo l'app.")
                    infoRow(icon: "rectangle.3.group", text: "Puoi riordinare anche le 3 sezioni principali (Portali, Temperatura, Potenza) nella schermata home.")
                }

                // Aggiornamento
                section("Aggiornamento dati") {
                    infoRow(icon: "arrow.clockwise", text: "I dati si aggiornano automaticamente. Puoi anche trascinare verso il basso in qualsiasi scheda per forzare l'aggiornamento.")
                    infoRow(icon: "clock", text: "Se una sonda mostra DOWN, significa che rileva il problema da almeno 10 minuti consecutivi.")
                }

                // Supporto
                section("Supporto") {
                    Text("Per assistenza tecnica contattare ABISSI S.r.l.")
                        .font(.subheadline)
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Aiuto")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func areaRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(description).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func probeRow(_ name: String, location: String) -> some View {
        HStack {
            Text(name).font(.subheadline.bold())
            Spacer()
            Text(location).font(.subheadline).foregroundColor(.secondary)
        }
    }

    private func statusRow(color: Color, label: String, description: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.bold())
                Text(description).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text).font(.subheadline)
        }
    }

    private func notifRow(_ emoji: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(emoji).font(.subheadline)
            Text(text).font(.subheadline)
        }
    }
}
