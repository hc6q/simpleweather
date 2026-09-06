import Foundation

enum L10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: .main, comment: "")
    }

    static func format(_ key: String, _ values: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: values)
    }
}

enum WeatherFormatting {
    static func temperature(_ celsius: Double, unit: TemperatureUnit,
                            includeUnit: Bool = false, locale: Locale = .current) -> String {
        guard celsius.isFinite else { return "—°" }
        let rounded = unit.value(fromCelsius: celsius).rounded()
        let value = rounded == 0 ? 0.0 : rounded // Avoid −0°.
        let number = value.formatted(.number.locale(locale).precision(.fractionLength(0)))
        return number + (includeUnit ? unit.symbol : "°")
    }

    static func hour(_ date: Date, timeZone: TimeZone, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        if locale.language.languageCode?.identifier == "pt" {
            formatter.dateFormat = "H'h'"
        } else {
            formatter.setLocalizedDateFormatFromTemplate("j")
        }
        return formatter.string(from: date)
    }

    static func weekday(_ date: Date, timeZone: TimeZone, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "")
            .uppercased(with: locale)
    }

    static func updated(_ date: Date, relativeTo now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .current
        formatter.unitsStyle = .abbreviated
        return L10n.format("updated.relative", formatter.localizedString(for: date, relativeTo: now))
    }

    static func precipitation(_ value: Double?) -> String {
        guard let value else { return "" }
        return L10n.format("precipitation.chance", value.formatted(.percent.precision(.fractionLength(0))))
    }
}
