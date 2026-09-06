#if DEBUG
import SwiftUI

#Preview("Nublado") {
    WeatherDashboard(snapshot: PreviewWeather.snapshot(), unit: .celsius, now: PreviewWeather.date)
        .preferredColorScheme(.dark)
}

#Preview("Chuva") {
    WeatherDashboard(snapshot: PreviewWeather.snapshot(condition: .rain, symbol: "cloud.rain.fill"),
                     unit: .celsius, now: PreviewWeather.date).preferredColorScheme(.dark)
}

#Preview("Sol") {
    WeatherDashboard(snapshot: PreviewWeather.snapshot(condition: .clear, symbol: "sun.max.fill"),
                     unit: .celsius, now: PreviewWeather.date).preferredColorScheme(.dark)
}

#Preview("Noite") {
    WeatherDashboard(snapshot: PreviewWeather.snapshot(condition: .clear, symbol: "moon.stars.fill", daylight: false),
                     unit: .celsius, now: PreviewWeather.date).preferredColorScheme(.dark)
}
#endif
