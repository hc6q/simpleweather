import XCTest
import WeatherKit
@testable import WeatherApp

final class WeatherModelTests: XCTestCase {
    private let portuguese = Locale(identifier: "pt_BR")
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testTemperatureConversionAndRounding() {
        XCTAssertEqual(TemperatureUnit.fahrenheit.value(fromCelsius: 0), 32)
        XCTAssertEqual(TemperatureUnit.fahrenheit.value(fromCelsius: 100), 212)
        XCTAssertEqual(TemperatureUnit.fahrenheit.value(fromCelsius: -40), -40)
        XCTAssertEqual(WeatherFormatting.temperature(17, unit: .celsius, includeUnit: true, locale: portuguese), "17°C")
        XCTAssertEqual(WeatherFormatting.temperature(17, unit: .fahrenheit, includeUnit: true, locale: portuguese), "63°F")
        XCTAssertEqual(WeatherFormatting.temperature(-0.1, unit: .celsius, locale: portuguese), "0°")
        XCTAssertEqual(WeatherFormatting.temperature(.nan, unit: .celsius, locale: portuguese), "—°")
    }

    func testHoursRespectForecastTimeZone() {
        let date = ISO8601DateFormatter().date(from: "2026-09-06T18:00:00Z")!
        XCTAssertEqual(WeatherFormatting.hour(date, timeZone: TimeZone(secondsFromGMT: -10_800)!, locale: portuguese), "15h")
        XCTAssertEqual(WeatherFormatting.hour(date, timeZone: utc, locale: portuguese), "18h")
        XCTAssertEqual(WeatherFormatting.weekday(date, timeZone: utc, locale: portuguese), "DOM")
    }

    func testNextHoursAreFutureSortedAndBounded() {
        let snapshot = PreviewWeather.snapshot()
        let now = PreviewWeather.date.addingTimeInterval(3600)
        let hours = snapshot.nextHours(after: now, limit: 4)
        XCTAssertEqual(hours.count, 4)
        XCTAssertEqual(hours.first?.date, PreviewWeather.date.addingTimeInterval(7200))
        XCTAssertTrue(hours.allSatisfy { $0.date > now })
        XCTAssertTrue(snapshot.nextHours(after: now, limit: 0).isEmpty)
        XCTAssertTrue(snapshot.nextHours(after: now.addingTimeInterval(200_000), limit: 4).isEmpty)
    }

    func testDuplicateHoursAreNotDisplayed() {
        let source = PreviewWeather.snapshot()
        let snapshot = WeatherSnapshot(place: source.place, current: source.current,
            hourly: Array(source.hourly.reversed()) + source.hourly, daily: source.daily, updatedAt: source.updatedAt)
        let hours = snapshot.nextHours(after: PreviewWeather.date, limit: 48)
        XCTAssertEqual(hours.count, 24)
        XCTAssertEqual(hours, source.hourly)
    }

    func testDaysUseLocalCalendarAcrossMidnight() {
        let source = PreviewWeather.snapshot()
        let now = ISO8601DateFormatter().date(from: "2026-09-07T01:00:00Z")!
        let day = ISO8601DateFormatter().date(from: "2026-09-06T03:00:00Z")!
        let place = WeatherPlace(coordinates: source.place.coordinates, name: "Teste",
                                 timeZoneIdentifier: "America/Sao_Paulo", locatedAt: now)
        let today = DailyWeatherModel(date: day, minimumCelsius: 1, maximumCelsius: 3,
                                     condition: .cloudy, symbolName: "cloud.fill", precipitationChance: nil)
        let snapshot = WeatherSnapshot(place: place, current: source.current,
            hourly: source.hourly, daily: [today], updatedAt: now)
        XCTAssertEqual(snapshot.nextDays(from: now, limit: 4).count, 1)
        XCTAssertTrue(snapshot.nextDays(from: now.addingTimeInterval(3 * 3600), limit: 4).isEmpty)
    }

    func testStalenessBoundary() {
        let snapshot = PreviewWeather.snapshot()
        XCTAssertFalse(snapshot.isStale(at: snapshot.updatedAt.addingTimeInterval(1799)))
        XCTAssertTrue(snapshot.isStale(at: snapshot.updatedAt.addingTimeInterval(1800)))
    }

    func testWeatherKitConditionsPreserveMeaning() {
        XCTAssertEqual(WeatherConditionModel(WeatherKit.WeatherCondition.rain), .rain)
        XCTAssertEqual(WeatherConditionModel(WeatherKit.WeatherCondition.partlyCloudy), .partlyCloudy)
        XCTAssertEqual(WeatherConditionModel(WeatherKit.WeatherCondition.strongStorms), .strongStorms)
        XCTAssertEqual(WeatherConditionModel(WeatherKit.WeatherCondition.freezingRain), .freezingRain)
    }

    func testCodableRoundTrip() throws {
        let snapshot = PreviewWeather.snapshot()
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(WeatherSnapshot.self, from: data), snapshot)
    }

    func testInvalidCoordinatesAndNonFiniteTemperatureAreRejected() {
        XCTAssertFalse(Coordinates(latitude: 91, longitude: 0).isValid)
        XCTAssertFalse(Coordinates(latitude: 0, longitude: .infinity).isValid)
        let source = PreviewWeather.snapshot()
        let invalid = CurrentWeatherModel(date: source.current.date, temperatureCelsius: .nan,
            condition: .cloudy, symbolName: "cloud.fill", isDaylight: true)
        XCTAssertFalse(WeatherSnapshot(place: source.place, current: invalid,
            hourly: source.hourly, daily: source.daily, updatedAt: source.updatedAt).isValid)
    }

    func testUnitPersistsBetweenConsumers() throws {
        let suite = "WeatherAppTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = SharedPreferences(defaults: defaults)
        XCTAssertEqual(first.unit, .celsius)
        first.unit = .fahrenheit
        XCTAssertEqual(SharedPreferences(defaults: defaults).unit, .fahrenheit)
        first.widgetRefreshAllowed = false
        XCTAssertFalse(SharedPreferences(defaults: defaults).widgetRefreshAllowed)
    }
}
