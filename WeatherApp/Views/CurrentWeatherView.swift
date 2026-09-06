import SwiftUI

struct CurrentWeatherView: View {
    let current: CurrentWeatherModel
    let unit: TemperatureUnit
    @ScaledMetric(relativeTo: .largeTitle) private var temperatureSize = 86.0

    var body: some View {
        VStack(spacing: 4) {
            WeatherIcon(symbol: current.symbolName, size: 100)
                .padding(.bottom, 2)
            Text(WeatherFormatting.temperature(current.temperatureCelsius, unit: unit, includeUnit: true))
                .font(.system(size: min(temperatureSize, 116), weight: .light))
                .tracking(-3).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.55)
                .padding(.vertical, -10)
            Text(current.condition.title)
                .font(.title2).foregroundStyle(WeatherTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}
