import SwiftUI

struct SettingsView: View {
    @Bindable var model: WeatherViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(L10n.text("settings.temperature"), selection: Binding(
                        get: { model.unit }, set: { model.setUnit($0) })) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.title + " (" + unit.symbol + ")").tag(unit)
                        }
                    }
                }.listRowBackground(WeatherTheme.card)

                Section {
                    Button(L10n.text("action.refreshLocation")) {
                        Task { await model.refresh(forceLocation: true) }
                    }.disabled(model.isRefreshing)
                    Button(L10n.text("action.refreshWeather")) {
                        Task { await model.refresh() }
                    }.disabled(model.isRefreshing)
                    if model.isRefreshing {
                        Text(L10n.text("weather.loading")).foregroundStyle(WeatherTheme.secondary)
                    }
                    if model.state == .permissionDenied {
                        Button(L10n.text("action.openSettings"), action: WeatherHomeView.openSystemSettings)
                    }
                    if let message = model.message {
                        Text(message).font(.footnote).foregroundStyle(WeatherTheme.secondary)
                    }
                }.listRowBackground(WeatherTheme.card)

                Section(L10n.text("settings.about")) {
                    LabeledContent(L10n.text("app.name"), value: version)
                    Text(L10n.text("app.about")).font(.footnote).foregroundStyle(WeatherTheme.secondary)
                    WeatherAttributionView(attribution: model.attribution)
                }.listRowBackground(WeatherTheme.card)
            }
            .scrollContentBackground(.hidden).background(.black)
            .navigationTitle(L10n.text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("action.done")) { dismiss() }
                }
            }
        }
        .tint(.white).preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
