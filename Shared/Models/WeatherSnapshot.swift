import Foundation

struct Coordinates: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite &&
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

struct WeatherPlace: Codable, Equatable, Sendable {
    let coordinates: Coordinates
    let name: String
    let timeZoneIdentifier: String
    let locatedAt: Date

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
}

struct CurrentWeatherModel: Codable, Equatable, Sendable {
    let date: Date
    let temperatureCelsius: Double
    let condition: WeatherConditionModel
    let symbolName: String
    let isDaylight: Bool
}

struct HourlyWeatherModel: Codable, Equatable, Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let temperatureCelsius: Double
    let condition: WeatherConditionModel
    let symbolName: String
    let precipitationChance: Double?
    let isDaylight: Bool
}

struct DailyWeatherModel: Codable, Equatable, Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let minimumCelsius: Double
    let maximumCelsius: Double
    let condition: WeatherConditionModel
    let symbolName: String
    let precipitationChance: Double?
}

struct WeatherSnapshot: Codable, Equatable, Sendable {
    let place: WeatherPlace
    let current: CurrentWeatherModel
    let hourly: [HourlyWeatherModel]
    let daily: [DailyWeatherModel]
    let updatedAt: Date

    func isStale(at date: Date = .now) -> Bool {
        date.timeIntervalSince(updatedAt) >= 30 * 60 ||
        date.timeIntervalSince(current.date) >= 60 * 60
    }

    // Never label the first hourly forecast "Agora": current observations are separate.
    func nextHours(after date: Date, limit: Int) -> [HourlyWeatherModel] {
        var seen = Set<Date>()
        return Array(hourly.sorted { $0.date < $1.date }
            .filter { $0.date > date && seen.insert($0.date).inserted }
            .prefix(max(0, limit)))
    }

    func nextDays(from date: Date, limit: Int) -> [DailyWeatherModel] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        let start = calendar.startOfDay(for: date)
        var seen = Set<Date>()
        return Array(daily.sorted { $0.date < $1.date }.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= start && seen.insert(day).inserted
        }.prefix(max(0, limit)))
    }

    var isValid: Bool {
        place.coordinates.isValid && !place.name.isEmpty &&
        updatedAt.timeIntervalSince1970.isFinite && current.date.timeIntervalSince1970.isFinite &&
        current.temperatureCelsius.isFinite && !current.symbolName.isEmpty &&
        !hourly.isEmpty && !daily.isEmpty &&
        hourly.allSatisfy {
            $0.date.timeIntervalSince1970.isFinite && $0.temperatureCelsius.isFinite &&
            !$0.symbolName.isEmpty && Self.validChance($0.precipitationChance)
        } && daily.allSatisfy {
            $0.date.timeIntervalSince1970.isFinite &&
            $0.minimumCelsius.isFinite && $0.maximumCelsius.isFinite &&
            $0.minimumCelsius <= $0.maximumCelsius && !$0.symbolName.isEmpty &&
            Self.validChance($0.precipitationChance)
        }
    }

    private static func validChance(_ value: Double?) -> Bool {
        value.map { $0.isFinite && (0...1).contains($0) } ?? true
    }
}

struct WeatherAttributionRecord: Codable, Equatable, Sendable {
    let markURL: URL
    let legalURL: URL
    let markData: Data?
}
