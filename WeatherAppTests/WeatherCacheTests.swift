import XCTest
@testable import WeatherApp

final class WeatherCacheTests: XCTestCase {
    func testAtomicCacheRoundTripAndCorruptDataFallback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = WeatherCache(directory: directory)
        let source = PreviewWeather.snapshot()
        // Cache validation uses the wall clock only to reject impossible future data.
        let snapshot = WeatherSnapshot(place: source.place, current: source.current,
            hourly: source.hourly, daily: source.daily, updatedAt: Date(timeIntervalSince1970: 1_600_000_000))
        let missing = await cache.load()
        XCTAssertNil(missing)
        let saved = await cache.save(snapshot)
        XCTAssertTrue(saved)
        let loaded = await WeatherCache(directory: directory).load()
        XCTAssertEqual(loaded, snapshot)
        try Data("invalid json".utf8).write(to: directory.appendingPathComponent("weather-v1.json"))
        let corrupt = await cache.load()
        XCTAssertNil(corrupt)
    }

    func testMissingAppGroupDoesNotClaimToSave() async {
        let cache = WeatherCache(directory: nil)
        let saved = await cache.save(PreviewWeather.snapshot())
        XCTAssertFalse(saved)
        let loaded = await cache.load()
        XCTAssertNil(loaded)
    }

    func testAnOlderWriteCannotReplaceNewerWeather() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = WeatherCache(directory: directory)
        let source = PreviewWeather.snapshot()
        let newer = WeatherSnapshot(place: source.place, current: source.current,
            hourly: source.hourly, daily: source.daily, updatedAt: Date(timeIntervalSince1970: 1_600_003_600))
        let older = WeatherSnapshot(place: source.place, current: source.current,
            hourly: source.hourly, daily: source.daily, updatedAt: Date(timeIntervalSince1970: 1_600_000_000))
        _ = await cache.save(newer)
        _ = await cache.save(older)
        let loaded = await cache.load()
        XCTAssertEqual(loaded, newer)
    }
}
