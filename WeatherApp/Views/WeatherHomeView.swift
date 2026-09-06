import SwiftUI
import UIKit

struct WeatherHomeView: View {
    @Bindable var model: WeatherViewModel
    @State private var showingSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WeatherTheme.background.ignoresSafeArea()
            if let snapshot = model.snapshot {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    WeatherDashboard(snapshot: snapshot, unit: model.unit, now: context.date,
                        attribution: model.attribution, notice: model.message,
                        permissionDenied: model.state == .permissionDenied,
                        settings: { showingSettings = true },
                        retry: { Task { await model.refresh() } })
                }
                .refreshable { await model.refresh() }
                .transition(.opacity)
            } else {
                emptyState
                    .overlay(alignment: .topTrailing) {
                        Button { showingSettings = true } label: {
                            Image(systemName: "ellipsis").font(.system(size: 19, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(WeatherTheme.card, in: Circle())
                                .overlay { Circle().strokeBorder(WeatherTheme.border, lineWidth: 0.75) }
                        }
                        .buttonStyle(.plain).accessibilityLabel(L10n.text("settings.title"))
                        .padding(.top, 8).padding(.trailing, 14)
                    }
            }
        }
        .foregroundStyle(.white)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.snapshot == nil)
        .sheet(isPresented: $showingSettings) { SettingsView(model: model) }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            if model.state == .permissionDenied {
                Image(systemName: "location.slash").font(.largeTitle).foregroundStyle(WeatherTheme.secondary)
                Text(L10n.text("location.permission.title")).font(.title2)
                Text(L10n.text("location.permission.message"))
                    .foregroundStyle(WeatherTheme.secondary).multilineTextAlignment(.center)
                Button(L10n.text("action.openSettings"), action: Self.openSystemSettings)
                    .buttonStyle(.borderedProminent).tint(Color(white: 0.18))
            } else {
                Text("—°").font(.system(size: 86, weight: .light))
                Text(L10n.text(model.state == .error ? "weather.error.message" : "weather.loading"))
                    .foregroundStyle(WeatherTheme.secondary).multilineTextAlignment(.center)
                if model.state == .error {
                    Button(L10n.text("action.retry")) { Task { await model.refresh() } }
                        .buttonStyle(.borderedProminent).tint(Color(white: 0.18))
                }
            }
            Spacer()
        }
        .padding(32)
    }

    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// Pure presentation view: previews and render tests inject fixtures without production mock paths.
struct WeatherDashboard: View {
    let snapshot: WeatherSnapshot
    let unit: TemperatureUnit
    let now: Date
    var attribution: WeatherAttributionRecord?
    var notice: String?
    var permissionDenied = false
    var settings: () -> Void = {}
    var retry: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header.padding(.top, 8).padding(.bottom, 3)
                CurrentWeatherView(current: snapshot.current, unit: unit)
                    .padding(.bottom, 6)
                HourlyForecastView(snapshot: snapshot, unit: unit, now: now)
                DailyForecastView(snapshot: snapshot, unit: unit, now: now)
                if snapshot.isStale(at: now) || notice != nil || permissionDenied {
                    cacheNotice
                }
                WeatherAttributionView(attribution: attribution)
            }
            .padding(.horizontal, 14).padding(.bottom, 8)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(WeatherTheme.background)
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            Text(snapshot.place.name).font(.title2).fontWeight(.regular)
                .lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Button(action: settings) {
                Image(systemName: "ellipsis").font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(WeatherTheme.card, in: Circle())
                    .overlay { Circle().strokeBorder(WeatherTheme.border, lineWidth: 0.75) }
            }
            .buttonStyle(.plain).accessibilityLabel(L10n.text("settings.title"))
        }
    }

    private var cacheNotice: some View {
        VStack(spacing: 6) {
            Text(WeatherFormatting.updated(snapshot.updatedAt, relativeTo: now))
            if let notice { Text(notice).multilineTextAlignment(.center) }
            if permissionDenied {
                Button(L10n.text("action.openSettings"), action: WeatherHomeView.openSystemSettings)
                    .frame(minHeight: 44)
            } else if notice != nil {
                Button(L10n.text("action.retry"), action: retry).frame(minHeight: 44)
            }
        }
        .font(.caption).foregroundStyle(WeatherTheme.secondary).padding(.top, 5)
    }
}
