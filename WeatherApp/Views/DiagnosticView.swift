import SwiftUI
import UIKit

@MainActor
struct DiagnosticView: View {
    @Bindable var model: WeatherViewModel
    @State private var runningTask: Task<Void, Never>?
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("diagnostics.explanation"))
                    .font(.footnote).foregroundStyle(WeatherTheme.secondary)
                Button(L10n.text("diagnostics.run")) {
                    copied = false
                    runningTask = Task { await model.runDiagnostics() }
                }
                .buttonStyle(.bordered).disabled(model.isRefreshing)
                if model.isDiagnosing {
                    HStack {
                        ProgressView()
                        Text(L10n.text("diagnostics.running"))
                        Button(L10n.text("diagnostics.cancel")) { runningTask?.cancel() }
                    }.font(.footnote)
                }
                Button(L10n.text(copied ? "diagnostics.copied" : "diagnostics.copy")) {
                    UIPasteboard.general.string = model.diagnosticReport.text
                    copied = true
                }.buttonStyle(.bordered)
                Text(L10n.text("diagnostics.privacy"))
                    .font(.caption).foregroundStyle(WeatherTheme.secondary)
                Text(verbatim: model.diagnosticReport.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(18)
        }
        .background(.black).foregroundStyle(.white)
        .navigationTitle(L10n.text("diagnostics.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { runningTask?.cancel() }
    }
}
