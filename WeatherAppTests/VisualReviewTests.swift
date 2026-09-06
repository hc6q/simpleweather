import SwiftUI
import UIKit
import XCTest
@testable import WeatherApp

@MainActor
final class VisualReviewTests: XCTestCase {
    func testRenderPhoneSizesAndWidgets() throws {
        let snapshot = PreviewWeather.snapshot()
        for width in [375.0, 390, 430] {
            let view = WeatherDashboard(snapshot: snapshot, unit: .celsius, now: PreviewWeather.date)
                .padding(.top, 44).padding(.bottom, 34).background(.black)
                .environment(\.colorScheme, .dark)
                .environment(\.locale, Locale(identifier: "pt_BR"))
                .frame(width: width, height: width == 375 ? 667 : 844)
            try attach(view, name: "app-\(Int(width))")
        }
        try attach(SmallWeatherWidgetView(snapshot: snapshot, unit: .celsius, date: PreviewWeather.date)
            .frame(width: 170, height: 170), name: "widget-small")
        try attach(MediumWeatherWidgetView(snapshot: snapshot, unit: .celsius, date: PreviewWeather.date)
            .frame(width: 364, height: 170), name: "widget-medium")
        try attach(WeatherDashboard(snapshot: snapshot, unit: .fahrenheit, now: PreviewWeather.date)
            .environment(\.dynamicTypeSize, .accessibility3)
            .frame(width: 375, height: 812), name: "app-accessibility")
    }

    private func attach<V: View>(_ view: V, name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, "SwiftUI should render \(name)")
        XCTAssertGreaterThan(image.size.width, 0)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
