import SwiftUI

enum WeatherTheme {
    static let background = Color.black
    static let card = Color(white: 0.024)
    static let border = Color(white: 0.14)
    static let secondary = Color(white: 0.72)
    static let divider = Color(white: 0.12)
    static let rain = Color(red: 0.05, green: 0.78, blue: 1)
    static let sun = Color(red: 1, green: 0.80, blue: 0.10)
}

struct WeatherCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(WeatherTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(WeatherTheme.border, lineWidth: 0.75)
            }
    }
}
