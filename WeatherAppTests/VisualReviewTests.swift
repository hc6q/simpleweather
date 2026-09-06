import SwiftUI
import UIKit
import XCTest
@testable import WeatherApp

@MainActor
final class VisualReviewTests: XCTestCase {
    func testRenderPhoneSizesAndWidgets() async throws {
        let snapshot = PreviewWeather.snapshot()
        for width in [375.0, 390, 430] {
            let view = WeatherDashboard(snapshot: snapshot, unit: .celsius, now: PreviewWeather.date)
                .padding(.top, 44).padding(.bottom, 34).background(.black)
                .environment(\.colorScheme, .dark)
                .environment(\.locale, Locale(identifier: "pt_BR"))
                .frame(width: width, height: width == 375 ? 667 : 844)
            try await attach(view, size: CGSize(width: width, height: width == 375 ? 667 : 844),
                             name: "app-\(Int(width))")
        }
        try await attach(SmallWeatherWidgetView(snapshot: snapshot, unit: .celsius, date: PreviewWeather.date)
            .frame(width: 170, height: 170), size: CGSize(width: 170, height: 170), name: "widget-small")
        try await attach(MediumWeatherWidgetView(snapshot: snapshot, unit: .celsius, date: PreviewWeather.date)
            .frame(width: 364, height: 170), size: CGSize(width: 364, height: 170), name: "widget-medium")
        try await attach(WeatherDashboard(snapshot: snapshot, unit: .fahrenheit, now: PreviewWeather.date)
            .environment(\.dynamicTypeSize, .accessibility3)
            .frame(width: 375, height: 812), size: CGSize(width: 375, height: 812), name: "app-accessibility")
    }

    private func attach<V: View>(_ view: V, size: CGSize, name: String) async throws {
        // ImageRenderer omits UIKit-backed scroll views. Host the actual view hierarchy instead.
        let controller = UIHostingController(rootView: view.ignoresSafeArea())
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.frame = window.bounds
        controller.view.backgroundColor = .black
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        await Task.yield()
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let cgImage = try XCTUnwrap(image.cgImage)
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
            bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let visible = (0..<(64 * 64)).filter {
            max(pixels[$0 * 4], pixels[$0 * 4 + 1], pixels[$0 * 4 + 2]) > 80
        }.count
        XCTAssertGreaterThan(visible, 20, "\(name) must contain visible content, not a blank screenshot")
    }
}
