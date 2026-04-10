import SwiftUI

struct WatchDashboardView: View {
    @EnvironmentObject var viewModel: WatchDashboardViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.monitors.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("In attesa dei dati...")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(viewModel.monitors) { monitor in
                        WatchMonitorCard(monitor: monitor)
                    }
                }
            }
            .navigationTitle("INVA")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Circle()
                        .fill(ledColor)
                        .frame(width: 10, height: 10)
                }
            }
        }
    }

    private var ledColor: Color {
        switch viewModel.globalState {
        case "RED": return .red
        case "YELLOW": return .yellow
        default: return .green
        }
    }
}
