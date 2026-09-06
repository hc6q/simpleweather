import Foundation

enum SharedConfiguration {
    static var appGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "WeatherAppGroup") as? String ?? "group.com.hc6q.weatherapp"
    }
    static let smallWidgetKind = "WeatherSmall"
    static let mediumWidgetKind = "WeatherMedium"
}

// Actor isolation serializes file IO; atomic replacement also protects cross-process readers.
actor WeatherCache {
    private struct Envelope: Codable {
        let version: Int
        let snapshot: WeatherSnapshot
    }

    static let shared = WeatherCache()
    static let widget = WeatherCache(fileName: "widget-weather-v1.json")
    private let directory: URL?
    private let fileName: String

    init(directory: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: SharedConfiguration.appGroup),
        fileName: String = "weather-v1.json") {
        self.directory = directory
        self.fileName = fileName
    }

    func load() -> WeatherSnapshot? {
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1, envelope.snapshot.isValid,
              envelope.snapshot.updatedAt <= Date.now.addingTimeInterval(5 * 60) else { return nil }
        return envelope.snapshot
    }

    @discardableResult
    func save(_ snapshot: WeatherSnapshot) -> Bool {
        guard snapshot.isValid, let directory else { return false }
        if let existing = load(), existing.updatedAt > snapshot.updatedAt { return true }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(fileName)
            // App and extension use different files, each with atomic replacement.
            let data = try JSONEncoder().encode(Envelope(version: 1, snapshot: snapshot))
            try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { return false }
    }
}

struct SharedPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: SharedConfiguration.appGroup)) {
        self.defaults = defaults ?? .standard
    }

    var unit: TemperatureUnit {
        get { TemperatureUnit(rawValue: defaults.string(forKey: "temperatureUnit") ?? "") ?? .celsius }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "temperatureUnit") }
    }

    var lastLocation: WeatherPlace? {
        get {
            guard let data = defaults.data(forKey: "lastLocation"),
                  let place = try? JSONDecoder().decode(WeatherPlace.self, from: data),
                  place.coordinates.isValid else { return nil }
            return place
        }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "lastLocation") }
    }

    var widgetRefreshAllowed: Bool {
        get { defaults.bool(forKey: "widgetRefreshAllowed") }
        nonmutating set { defaults.set(newValue, forKey: "widgetRefreshAllowed") }
    }

    var attribution: WeatherAttributionRecord? {
        get {
            guard let data = defaults.data(forKey: "weatherAttribution") else { return nil }
            return try? JSONDecoder().decode(WeatherAttributionRecord.self, from: data)
        }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "weatherAttribution") }
    }
}
