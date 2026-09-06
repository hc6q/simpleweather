import SwiftUI
import WidgetKit

struct SmallWeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedConfiguration.smallWidgetKind, provider: WeatherTimelineProvider()) { entry in
            SmallWeatherWidgetView(snapshot: entry.snapshot, unit: entry.unit, date: entry.date)
                .containerBackground(.black, for: .widget)
                .overlay { ContainerRelativeShape().strokeBorder(WeatherTheme.border, lineWidth: 1) }
                .widgetURL(URL(string: "weatherapp://forecast"))
                .environment(\.colorScheme, .dark)
        }
        .configurationDisplayName(Text(L10n.text("widget.small.name")))
        .description(Text(L10n.text("widget.small.description")))
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}
