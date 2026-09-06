import SwiftUI

struct SmallWeatherWidgetView: View {
    let snapshot: WeatherSnapshot?
    let unit: TemperatureUnit
    let date: Date

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 4) {
                if let current = snapshot?.current {
                    WeatherIcon(symbol: current.symbolName, size: min(geometry.size.height * 0.40, 66))
                    Text(WeatherFormatting.temperature(current.temperatureCelsius, unit: unit, includeUnit: true))
                        .font(.system(size: 44, weight: .light)).tracking(-1.6)
                        .lineLimit(1).minimumScaleFactor(0.55)
                    Text(conditionLabel)
                        .font(.system(size: 14)).foregroundStyle(WeatherTheme.secondary)
                        .lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.center)
                } else {
                    widgetEmptyState
                }
            }
            .padding(12)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .foregroundStyle(.white).background(.black)
        .accessibilityElement(children: .combine)
    }

    private var conditionLabel: String {
        guard let snapshot else { return L10n.text("widget.openApp") }
        return snapshot.isStale(at: date) ? WeatherFormatting.updated(snapshot.updatedAt, relativeTo: date) :
                                          snapshot.current.condition.title
    }
}

struct MediumWeatherWidgetView: View {
    let snapshot: WeatherSnapshot?
    let unit: TemperatureUnit
    let date: Date

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width - 24)
            HStack(spacing: 0) {
                if let snapshot {
                    current(snapshot)
                        .frame(width: availableWidth * 0.38)
                    Rectangle().fill(WeatherTheme.divider).frame(width: 0.75).padding(.vertical, 17)
                    let hours = snapshot.nextHours(after: date, limit: 4)
                    HStack(spacing: 0) {
                        ForEach(0..<4) { index in
                            if index > 0 {
                                Rectangle().fill(WeatherTheme.divider).frame(width: 0.75).padding(.vertical, 22)
                            }
                            if index < hours.count {
                                hour(hours[index], timeZone: snapshot.place.timeZone)
                            } else {
                                VStack(spacing: 15) {
                                    Text("—").foregroundStyle(WeatherTheme.secondary)
                                    Image(systemName: "cloud").foregroundStyle(WeatherTheme.secondary)
                                    Text("—°")
                                }.font(.caption).frame(maxWidth: .infinity)
                                    .accessibilityLabel(L10n.text("forecast.expired"))
                            }
                        }
                    }
                    .padding(.leading, 8)
                    .frame(maxWidth: .infinity)
                } else {
                    widgetEmptyState.frame(maxWidth: .infinity)
                }
            }
            .padding(12)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .foregroundStyle(.white).background(.black)
    }

    private func current(_ snapshot: WeatherSnapshot) -> some View {
        VStack(spacing: 3) {
            WeatherIcon(symbol: snapshot.current.symbolName, size: 52)
            Text(WeatherFormatting.temperature(snapshot.current.temperatureCelsius, unit: unit, includeUnit: true))
                .font(.system(size: 38, weight: .light)).tracking(-1.5)
                .lineLimit(1).minimumScaleFactor(0.55)
            Text(snapshot.isStale(at: date) ? WeatherFormatting.updated(snapshot.updatedAt, relativeTo: date) :
                                           snapshot.current.condition.title)
                .font(.system(size: 12)).foregroundStyle(WeatherTheme.secondary)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
        }
        .padding(.trailing, 8)
        .accessibilityElement(children: .combine)
    }

    private func hour(_ hour: HourlyWeatherModel, timeZone: TimeZone) -> some View {
        VStack(spacing: 16) {
            Text(WeatherFormatting.hour(hour.date, timeZone: timeZone))
                .font(.system(size: 12)).foregroundStyle(WeatherTheme.secondary)
                .lineLimit(1).minimumScaleFactor(0.65)
            WeatherIcon(symbol: hour.symbolName, size: 27)
            Text(WeatherFormatting.temperature(hour.temperatureCelsius, unit: unit))
                .font(.system(size: 17)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([WeatherFormatting.hour(hour.date, timeZone: timeZone), hour.condition.title,
            WeatherFormatting.temperature(hour.temperatureCelsius, unit: unit, includeUnit: true),
            WeatherFormatting.precipitation(hour.precipitationChance)].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

private var widgetEmptyState: some View {
    VStack(spacing: 8) {
        Image(systemName: "cloud").font(.system(size: 32)).foregroundStyle(WeatherTheme.secondary)
        Text("—°").font(.system(size: 40, weight: .light))
        Text(L10n.text("widget.openApp")).font(.caption)
            .foregroundStyle(WeatherTheme.secondary).multilineTextAlignment(.center)
    }
}
