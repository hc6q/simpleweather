import CoreLocation
import Foundation
import WeatherKit

enum WeatherRequestError: Error { case invalidData, timedOut }

struct WeatherClient: Sendable {
    func fetch(for place: WeatherPlace) async throws -> WeatherSnapshot {
        guard place.coordinates.isValid else { throw WeatherRequestError.invalidData }
        return try await withTimeout(seconds: 22) {
            let location = CLLocation(latitude: place.coordinates.latitude, longitude: place.coordinates.longitude)
            let (current, hourly, daily) = try await WeatherService.shared.weather(
                for: location, including: .current, .hourly, .daily)
            let snapshot = WeatherSnapshot(
                place: place,
                current: CurrentWeatherModel(date: current.date,
                    temperatureCelsius: current.temperature.converted(to: .celsius).value,
                    condition: WeatherConditionModel(current.condition),
                    symbolName: current.symbolName, isDaylight: current.isDaylight),
                hourly: hourly.prefix(48).map {
                    HourlyWeatherModel(date: $0.date,
                        temperatureCelsius: $0.temperature.converted(to: .celsius).value,
                        condition: WeatherConditionModel($0.condition), symbolName: $0.symbolName,
                        precipitationChance: $0.precipitationChance, isDaylight: $0.isDaylight)
                },
                daily: daily.prefix(10).map {
                    DailyWeatherModel(date: $0.date,
                        minimumCelsius: $0.lowTemperature.converted(to: .celsius).value,
                        maximumCelsius: $0.highTemperature.converted(to: .celsius).value,
                        condition: WeatherConditionModel($0.condition), symbolName: $0.symbolName,
                        precipitationChance: $0.precipitationChance)
                }, updatedAt: .now)
            guard snapshot.isValid else { throw WeatherRequestError.invalidData }
            return snapshot
        }
    }

    func attribution() async -> WeatherAttributionRecord? {
        try? await withTimeout(seconds: 10) {
            let attribution = try await WeatherService.shared.attribution
            // Match Apple's Food Truck sample: the dark appearance uses combinedMarkDarkURL.
            let url = attribution.combinedMarkDarkURL
            var request = URLRequest(url: url)
            request.timeoutInterval = 6
            let data = try? await URLSession.shared.data(for: request).0
            return WeatherAttributionRecord(markURL: url, legalURL: attribution.legalPageURL,
                                            markData: data.flatMap { $0.count < 250_000 ? $0 : nil })
        }
    }
}

func withTimeout<T: Sendable>(seconds: UInt64,
                             operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw WeatherRequestError.timedOut
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw CancellationError() }
        return result
    }
}

extension WeatherConditionModel {
    init(_ condition: WeatherKit.WeatherCondition) {
        switch condition {
        case .clear: self = .clear
        case .mostlyClear: self = .mostlyClear
        case .partlyCloudy: self = .partlyCloudy
        case .mostlyCloudy: self = .mostlyCloudy
        case .cloudy: self = .cloudy
        case .drizzle: self = .drizzle
        case .rain: self = .rain
        case .heavyRain: self = .heavyRain
        case .isolatedThunderstorms: self = .isolatedThunderstorms
        case .scatteredThunderstorms: self = .scatteredThunderstorms
        case .thunderstorms: self = .thunderstorms
        case .strongStorms: self = .strongStorms
        case .snow: self = .snow
        case .flurries: self = .flurries
        case .heavySnow: self = .heavySnow
        case .blowingSnow: self = .blowingSnow
        case .blizzard: self = .blizzard
        case .sleet: self = .sleet
        case .hail: self = .hail
        case .wintryMix: self = .wintryMix
        case .freezingDrizzle: self = .freezingDrizzle
        case .freezingRain: self = .freezingRain
        case .foggy: self = .foggy
        case .haze: self = .haze
        case .smoky: self = .smoky
        case .blowingDust: self = .blowingDust
        case .breezy: self = .breezy
        case .windy: self = .windy
        case .hot: self = .hot
        case .frigid: self = .frigid
        case .hurricane: self = .hurricane
        case .tropicalStorm: self = .tropicalStorm
        case .sunShowers: self = .sunShowers
        case .sunFlurries: self = .sunFlurries
        @unknown default: self = .unknown
        }
    }
}
