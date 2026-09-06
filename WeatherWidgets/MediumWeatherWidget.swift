import SwiftUI
import WidgetKit

struct MediumWeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedConfiguration.mediumWidgetKind, provider: WeatherTimelineProvider()) { entry in
            MediumWeatherWidgetView(snapshot: entry.snapshot, unit: entry.unit, date: entry.date)
                .containerBackground(.black, for: .widget)
                .overlay { ContainerRelativeShape().strokeBorder(WeatherTheme.border, lineWidth: 1) }
                .widgetURL(URL(string: "weatherapp://forecast"))
                .environment(\.colorScheme, .dark)
        }
        .configurationDisplayName(Text(L10n.text("widget.medium.name")))
        .description(Text(L10n.text("widget.medium.description")))
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}
