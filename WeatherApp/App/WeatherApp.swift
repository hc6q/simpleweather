import SwiftUI

@main
@MainActor
struct WeatherApp: App {
    @State private var model = WeatherViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WeatherHomeView(model: model)
                .preferredColorScheme(.dark)
                .task {
                    // A hosted XCTest process must never request GPS or the remote weather service.
                    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                    await model.activate()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active,
                          ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                    Task { await model.activate() }
                }
        }
    }
}
