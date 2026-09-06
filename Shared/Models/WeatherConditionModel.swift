import Foundation

enum WeatherConditionModel: String, Codable, CaseIterable, Sendable {
    case clear, mostlyClear, partlyCloudy, mostlyCloudy, cloudy
    case drizzle, rain, heavyRain, isolatedThunderstorms, scatteredThunderstorms, thunderstorms, strongStorms
    case snow, flurries, heavySnow, blowingSnow, blizzard, sleet, hail, wintryMix
    case freezingDrizzle, freezingRain, foggy, haze, smoky, blowingDust
    case breezy, windy, hot, frigid, hurricane, tropicalStorm, sunShowers, sunFlurries
    case unknown

    var title: String { L10n.text("condition." + rawValue) }
}

enum TemperatureUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case celsius, fahrenheit
    var id: Self { self }
    var symbol: String { self == .celsius ? "°C" : "°F" }
    var title: String { L10n.text("unit." + rawValue) }

    func value(fromCelsius value: Double) -> Double {
        self == .celsius ? value : value * 9 / 5 + 32
    }
}
