import SwiftUI

struct DailyForecastView: View {
    let snapshot: WeatherSnapshot
    let unit: TemperatureUnit
    let now: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("forecast.nextDays"))
                    .font(.headline).fontWeight(.regular)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
                let days = snapshot.nextDays(from: now, limit: 4)
                if days.isEmpty {
                    Text(L10n.text("forecast.expired"))
                        .font(.subheadline).foregroundStyle(WeatherTheme.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(days) { day in
                        dayRow(day).padding(.vertical, 12)
                        if day.id != days.last?.id {
                            Rectangle().fill(WeatherTheme.divider).frame(height: 0.75)
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func dayRow(_ day: DailyWeatherModel) -> some View {
        let label = WeatherFormatting.weekday(day.date, timeZone: snapshot.place.timeZone)
        let range = WeatherFormatting.temperature(day.minimumCelsius, unit: unit) + " — " +
                    WeatherFormatting.temperature(day.maximumCelsius, unit: unit)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(label)
                        WeatherIcon(symbol: day.symbolName, size: 30)
                        Spacer(minLength: 4)
                    }
                    Text(range).monospacedDigit()
                    Text(day.condition.title).foregroundStyle(WeatherTheme.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    Text(label).font(.subheadline).frame(width: 36, alignment: .leading)
                    WeatherIcon(symbol: day.symbolName, size: 30).frame(width: 36)
                    Text(range).font(.subheadline).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: unit == .celsius ? 92 : 98)
                    Text(day.condition.title)
                        .font(.caption).foregroundStyle(WeatherTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([label, day.condition.title,
            L10n.format("temperature.range", WeatherFormatting.temperature(day.minimumCelsius, unit: unit, includeUnit: true),
                        WeatherFormatting.temperature(day.maximumCelsius, unit: unit, includeUnit: true)),
            WeatherFormatting.precipitation(day.precipitationChance)].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}
