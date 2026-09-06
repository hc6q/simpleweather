import SwiftUI

struct HourlyForecastView: View {
    let snapshot: WeatherSnapshot
    let unit: TemperatureUnit
    let now: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var cardHeight = 132.0

    var body: some View {
        WeatherCard {
            GeometryReader { geometry in
                let columnWidth = max(dynamicTypeSize.isAccessibilitySize ? 100 : 58, geometry.size.width / 5)
                let hours = snapshot.nextHours(after: now, limit: 24)
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        column(label: snapshot.isStale(at: now) ? L10n.text("weather.latest") : L10n.text("weather.now"),
                               symbol: snapshot.current.symbolName,
                               temperature: snapshot.current.temperatureCelsius,
                               condition: snapshot.current.condition, precipitation: nil)
                            .frame(width: columnWidth)
                            .overlay(alignment: .trailing) { divider }
                        ForEach(hours) { hour in
                            column(label: WeatherFormatting.hour(hour.date, timeZone: snapshot.place.timeZone),
                                   symbol: hour.symbolName, temperature: hour.temperatureCelsius,
                                   condition: hour.condition, precipitation: hour.precipitationChance)
                                .frame(width: columnWidth)
                                .overlay(alignment: .trailing) {
                                    if hour.id != hours.last?.id { divider }
                                }
                        }
                    }
                    .padding(.vertical, 18)
                }
                .scrollIndicators(.hidden)
            }
            .frame(height: min(cardHeight, 220))
            .clipped()
        }
        .accessibilityLabel(L10n.text("forecast.hourly"))
    }

    private var divider: some View {
        Rectangle().fill(WeatherTheme.divider).frame(width: 0.75)
    }

    private func column(label: String, symbol: String, temperature: Double,
                        condition: WeatherConditionModel, precipitation: Double?) -> some View {
        VStack(spacing: 13) {
            Text(label).font(.subheadline).foregroundStyle(WeatherTheme.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            WeatherIcon(symbol: symbol, size: 30)
            Text(WeatherFormatting.temperature(temperature, unit: unit))
                .font(.title3).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([label, condition.title,
            WeatherFormatting.temperature(temperature, unit: unit, includeUnit: true),
            WeatherFormatting.precipitation(precipitation)].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}
