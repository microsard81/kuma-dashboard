import SwiftUI

/// Vista Help in-app con documentazione per l'utente.
struct HelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // Panoramica
                    section("Panoramica") {
                        Text("Dashboard INVA monitora lo stato dei servizi tramite 5 sonde indipendenti distribuite geograficamente. Ogni servizio viene verificato ogni 60 secondi.")
                    }

                    // Sonde
                    section("Le 5 sonde") {
                        probeRow("Aruba", location: "Bergamo")
                        probeRow("TIM", location: "Sestu (CA)")
                        probeRow("ILIAD", location: "Sinnai (CA)")
                        probeRow("NodePing", location: "Europa")
                        probeRow("Uptime", location: "Globale")
                    }

                    // Stato
                    section("Stato delle risorse") {
                        statusRow(color: .green, label: "UP", description: "Tutte le sonde vedono la risorsa operativa")
                        statusRow(color: .yellow, label: "Mismatch", description: "Alcune sonde vedono DOWN, altre UP")
                        statusRow(color: .red, label: "DOWN", description: "Tutte le sonde vedono la risorsa non raggiungibile")
                    }

                    // Timing
                    section("Tempistiche") {
                        infoRow(icon: "clock", text: "Se una sonda mostra DOWN, significa che quella sonda rileva il problema da almeno 10 minuti consecutivi.")
                        infoRow(icon: "arrow.clockwise", text: "La dashboard si aggiorna automaticamente in base all'intervallo configurato nelle Impostazioni (default: 60 secondi).")
                    }

                    // Notifiche
                    section("Notifiche push") {
                        Text("Ricevi notifiche push quando lo stato dei servizi cambia:")
                            .font(.subheadline)
                        notifRow("🔴", text: "Servizi DOWN — una o più risorse completamente irraggiungibili")
                        notifRow("🟡", text: "Incongruenza — alcune sonde vedono DOWN")
                        notifRow("🟡🔴", text: "Peggioramento — più sonde DOWN rispetto a prima")
                        notifRow("🟢", text: "Tutto OK — tutti i servizi ripristinati")
                    }

                    // Soglia
                    section("Soglia notifica") {
                        Text("Puoi configurare quante sonde devono essere DOWN prima di ricevere la notifica (1–5).")
                            .font(.subheadline)
                        Text("Esempio: con soglia 3, ricevi la notifica solo quando almeno 3 sonde vedono DOWN su una risorsa. Le notifiche per 1 o 2 sonde DOWN vengono filtrate.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Impostazioni → Notifiche → Soglia notifica")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }

                    // Badge
                    section("Indicatore stato (in alto a sinistra)") {
                        HStack(spacing: 8) {
                            Circle().fill(.green).frame(width: 12, height: 12)
                            Text("Tutto OK — nessun problema")
                                .font(.subheadline)
                        }
                        HStack(spacing: 8) {
                            Circle().fill(.yellow).frame(width: 12, height: 12)
                            Text("+ numero giallo = risorse in mismatch")
                                .font(.subheadline)
                        }
                        HStack(spacing: 8) {
                            Circle().fill(.red).frame(width: 12, height: 12)
                            Text("+ numero rosso = risorse completamente DOWN")
                                .font(.subheadline)
                        }
                    }

                    // Sparkline
                    section("Storico (barre colorate)") {
                        Text("Ogni risorsa mostra una barra con gli ultimi 60 campionamenti. I colori indicano lo stato in quel momento.")
                            .font(.subheadline)
                        Text("Tocca una barra per vedere l'orario e il dettaglio delle sonde.")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
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
