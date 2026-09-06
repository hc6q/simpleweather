import SwiftUI

struct WeatherIcon: View {
    let symbol: String
    var size: CGFloat = 44

    private var cloudGradient: LinearGradient {
        LinearGradient(colors: [Color(white: 0.98), Color(red: 0.75, green: 0.79, blue: 0.85),
                                Color(red: 0.36, green: 0.40, blue: 0.48)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        Group {
            if symbol == "cloud.fill" || symbol == "cloud" {
                cloud
            } else if symbol == "cloud.rain.fill" || symbol == "cloud.drizzle.fill" || symbol == "cloud.heavyrain.fill" {
                VStack(spacing: size * -0.03) {
                    cloud.frame(height: size * 0.68)
                    HStack(spacing: size * 0.16) {
                        ForEach(0..<3) { _ in
                            Capsule().fill(WeatherTheme.rain)
                                .frame(width: max(1.5, size * 0.045), height: size * 0.20)
                                .rotationEffect(.degrees(18))
                        }
                    }
                }
            } else {
                Image(systemName: symbol)
                    .resizable().scaledToFit()
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(symbol.contains("sun") || symbol.contains("bolt") ? WeatherTheme.sun : WeatherTheme.secondary,
                                     Color(white: 0.91), WeatherTheme.rain)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var cloud: some View {
        Image(systemName: "cloud.fill")
            .resizable().scaledToFit()
            .foregroundStyle(cloudGradient)
    }
}
