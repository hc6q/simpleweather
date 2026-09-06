#if DEBUG
import Foundation
import SwiftUI

// Fixtures are only referenced by #Preview declarations and XCTest, never by runtime services.
enum PreviewWeather {
    static let date = Date(timeIntervalSince1970: 1_788_703_200)

    static func snapshot(condition: WeatherConditionModel = .cloudy,
                         symbol: String = "cloud.fill", daylight: Bool = true) -> WeatherSnapshot {
        let place = WeatherPlace(coordinates: Coordinates(latitude: 0, longitude: 0),
                                 name: "Localidade", timeZoneIdentifier: "GMT", locatedAt: date)
        let symbols = ["cloud.fill", "cloud.rain.fill", "cloud.fill", "cloud.rain.fill"]
        let conditions: [WeatherConditionModel] = [.cloudy, .rain, .cloudy, .rain]
        let temperatures = [19.0, 18, 16, 15]
        return WeatherSnapshot(place: place,
            current: CurrentWeatherModel(date: date, temperatureCelsius: 17,
                condition: condition, symbolName: symbol, isDaylight: daylight),
            hourly: (0..<24).map { index in
                HourlyWeatherModel(date: date.addingTimeInterval(Double(index + 1) * 3600),
                    temperatureCelsius: temperatures[index % 4], condition: conditions[index % 4],
                    symbolName: symbols[index % 4], precipitationChance: index % 2 == 0 ? 0.1 : 0.8,
                    isDaylight: index < 5)
            }, daily: (0..<4).map { index in
                DailyWeatherModel(date: date.addingTimeInterval(Double(index) * 86400),
                    minimumCelsius: [12.0, 10, 8, 11][index], maximumCelsius: [21.0, 19, 17, 20][index],
                    condition: [.cloudy, .rain, .clear, .partlyCloudy][index],
                    symbolName: ["cloud.fill", "cloud.rain.fill", "sun.max.fill", "cloud.sun.fill"][index],
                    precipitationChance: index == 1 ? 0.8 : 0.1)
            }, updatedAt: date)
    }
}

#Preview("Widget pequeno • Nublado", traits: .fixedLayout(width: 170, height: 170)) {
    SmallWeatherWidgetView(snapshot: PreviewWeather.snapshot(), unit: .celsius, date: PreviewWeather.date)
        .environment(\.locale, Locale(identifier: "pt_BR"))
}

#Preview("Widget médio", traits: .fixedLayout(width: 364, height: 170)) {
    MediumWeatherWidgetView(snapshot: PreviewWeather.snapshot(), unit: .celsius, date: PreviewWeather.date)
        .environment(\.locale, Locale(identifier: "pt_BR"))
}
#endif
