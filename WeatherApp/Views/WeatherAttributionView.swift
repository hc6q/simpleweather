import SwiftUI
import UIKit

struct WeatherAttributionView: View {
    let attribution: WeatherAttributionRecord?
    private let fallbackURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    var body: some View {
        VStack(spacing: 9) {
            if let data = attribution?.markData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(width: 96, height: 22)
                    .accessibilityLabel("Apple Weather")
            } else if let url = attribution?.markURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: { fallbackMark }
                    .frame(width: 96, height: 22).accessibilityLabel("Apple Weather")
            } else {
                fallbackMark
            }
            Link(L10n.text("weather.dataSources"), destination: attribution?.legalURL ?? fallbackURL)
                .font(.caption).foregroundStyle(WeatherTheme.secondary)
                .frame(minHeight: 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var fallbackMark: some View {
        Label("Weather", systemImage: "apple.logo")
            .font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
            .accessibilityLabel("Apple Weather")
    }
}
