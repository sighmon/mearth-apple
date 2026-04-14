import SwiftUI
import WidgetKit
#if os(iOS)
import ActivityKit
#endif

private struct MearthWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedDashboardSnapshot
}

private struct MearthWidgetProvider: TimelineProvider {
    private let store = SharedDashboardSnapshotStore()

    func placeholder(in context: Context) -> MearthWidgetEntry {
        MearthWidgetEntry(date: .now, snapshot: SharedDashboardSnapshotStore.preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (MearthWidgetEntry) -> Void) {
        let snapshot = store.load() ?? SharedDashboardSnapshotStore.preview
        completion(MearthWidgetEntry(date: snapshot.generatedAt, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MearthWidgetEntry>) -> Void) {
        let snapshot = store.load() ?? SharedDashboardSnapshotStore.preview
        let entry = MearthWidgetEntry(date: snapshot.generatedAt, snapshot: snapshot)
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: snapshot.generatedAt) ?? snapshot.generatedAt.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct MearthDashboardWidget: Widget {
    private let kind = "MearthDashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MearthWidgetProvider()) { entry in
            MearthWidgetView(entry: entry)
        }
        .configurationDisplayName("Mearth Conditions")
        .description("Shows the latest Mars, Earth, Moon, and local temperatures.")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        [
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
        ]
        #else
        [
            .systemSmall,
            .systemMedium,
            .systemLarge,
        ]
        #endif
    }
}

private struct MearthWidgetView: View {
    let entry: MearthWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                compactGrid(limit: 3)
            case .systemMedium:
                fullGrid(columns: 2, limit: 2)
            case .systemLarge:
                fullGrid(columns: 2)
            case .accessoryInline:
                inlineAccessory
            case .accessoryCircular:
                circularAccessory
            case .accessoryRectangular:
                rectangularAccessory
            default:
                fullGrid(columns: 2)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(.sRGB, white: 0.17, opacity: 1), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func compactGrid(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mearth")
                .font(.headline)
                .foregroundStyle(.white)
            ForEach(entry.snapshot.cards.prefix(limit)) { card in
                WidgetRow(card: card, compact: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(4)
    }

    private func fullGrid(columns: Int, limit: Int? = nil) -> some View {
        let cards = Array(limit.map { entry.snapshot.cards.prefix($0) } ?? entry.snapshot.cards[...])

        return VStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mearth")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(entry.snapshot.generatedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                ForEach(cards) { card in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(card.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(card.value)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(card.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(10)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(8)
    }

    private var inlineAccessory: some View {
        Text(entry.snapshot.summaryLine)
            .lineLimit(1)
    }

    private var circularAccessory: some View {
        let mars = entry.snapshot.card(for: .mars)?.value ?? "--"
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Text("Mars")
                    .font(.system(size: 10, weight: .semibold))
                Text(mars)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }

    private var rectangularAccessory: some View {
        HStack(spacing: 10) {
            accessoryMetric(kind: .mars)
            accessoryMetric(kind: .earth)
            accessoryMetric(kind: .moon)
            accessoryMetric(kind: .local)
        }
    }

    private func accessoryMetric(kind: SharedCardKind) -> some View {
        let card = entry.snapshot.card(for: kind)
        return VStack(alignment: .center, spacing: 2) {
            Text(kind.shortLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Text(rectangularAccessoryValue(for: card))
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    private func rectangularAccessoryValue(for card: SharedWeatherCard?) -> String {
        guard let value = card?.value else {
            return "--"
        }

        return value
            .replacingOccurrences(of: "°C", with: "°")
            .replacingOccurrences(of: "°F", with: "°")
    }
}

private struct WidgetRow: View {
    let card: SharedWeatherCard
    let compact: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(displayTitle)
                .font(compact ? .caption.weight(.semibold) : .caption)
                .foregroundStyle(.white.opacity(0.76))
            Spacer(minLength: 6)
            Text(displayValue)
                .font(compact ? .body.weight(.bold) : .headline)
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    private var displayValue: String {
        guard compact else {
            return card.value
        }

        return card.value
            .replacingOccurrences(of: "°C", with: "°")
            .replacingOccurrences(of: "°F", with: "°")
    }

    private var displayTitle: String {
        guard compact else {
            return card.title
        }

        return card.title.split(separator: " ").first.map(String.init) ?? card.title
    }
}

#if os(iOS)
@available(iOSApplicationExtension 16.2, *)
struct MearthLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MearthLiveActivityAttributes.self) { context in
            MearthLiveActivityContentView(state: context.state)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DynamicIslandMetricView(label: "Mars", value: context.state.marsValue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DynamicIslandMetricView(label: "Earth", value: context.state.earthValue)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DynamicIslandExpandedBottomView(state: context.state)
                }
            } compactLeading: {
                DynamicIslandCompactValueView(value: context.state.marsValue)
            } compactTrailing: {
                DynamicIslandCompactValueView(value: context.state.localValue)
            } minimal: {
                DynamicIslandMinimalView()
            }
            .widgetURL(URL(string: "mearth://dashboard"))
            .keylineTint(.white)
        }
    }
}
#endif

#if os(iOS)
@available(iOSApplicationExtension 16.2, *)
private struct MearthLiveActivityContentView: View {
    let state: MearthLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mearth")
                .font(.headline)
            HStack(spacing: 20) {
                DynamicIslandMetricView(label: "Mars", value: state.marsValue)
                DynamicIslandMetricView(label: "Earth", value: state.earthValue)
                DynamicIslandMetricView(label: "Moon", value: state.moonValue)
                DynamicIslandMetricView(label: "Local", value: state.localValue)
            }
        }
        .padding(16)
    }
}

private struct DynamicIslandMetricView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.bold))
                .monospacedDigit()
        }
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct DynamicIslandExpandedBottomView: View {
    let state: MearthLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            DynamicIslandMetricView(label: "Moon", value: state.moonValue)
            DynamicIslandMetricView(label: "Local", value: state.localValue)
        }
    }
}

private struct DynamicIslandCompactValueView: View {
    let value: String

    var body: some View {
        Text(value)
            .monospacedDigit()
    }
}

private struct DynamicIslandMinimalView: View {
    var body: some View {
        Text("M")
    }
}
#endif

@main
struct MearthWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MearthDashboardWidget()
        #if os(iOS)
        if #available(iOSApplicationExtension 16.2, *) {
            MearthLiveActivityWidget()
        }
        #endif
    }
}

#if DEBUG
private enum MearthWidgetPreviewData {
    static let liveSnapshot = SharedDashboardSnapshotStore.preview

    static let cachedSnapshot = SharedDashboardSnapshot(
        generatedAt: .now.addingTimeInterval(-60 * 42),
        cards: [
            SharedWeatherCard(
                kind: .mars,
                title: "Mars",
                subtitle: "Curiosity at Gale Crater",
                value: "-24°C",
                detail: "LMST 05:14 · latest REMS sol 4856",
                footnote: "Cached official REMS weather.",
                isAvailable: true,
                isCached: true,
                lastUpdated: .now.addingTimeInterval(-60 * 42)
            ),
            SharedWeatherCard(
                kind: .earth,
                title: "Earth Match",
                subtitle: "Norilsk, Russia",
                value: "-21°C",
                detail: "3°C warmer than Mars",
                footnote: "Cached Earth match.",
                isAvailable: true,
                isCached: true,
                lastUpdated: .now.addingTimeInterval(-60 * 42)
            ),
            SharedWeatherCard(
                kind: .moon,
                title: "Moon Estimate",
                subtitle: "Apollo 11 · Tranquility Base",
                value: "-147°C",
                detail: "Lunar local time 22:31",
                footnote: "Modeled lunar night estimate.",
                isAvailable: true,
                isCached: true,
                lastUpdated: .now.addingTimeInterval(-60 * 42)
            ),
            SharedWeatherCard(
                kind: .local,
                title: "Local",
                subtitle: "New York, New York, USA",
                value: "61°F",
                detail: "Current conditions near you",
                footnote: "Cached local weather.",
                isAvailable: true,
                isCached: true,
                lastUpdated: .now.addingTimeInterval(-60 * 42)
            ),
        ],
        warning: "Showing cached results."
    )

    static let liveEntry = MearthWidgetEntry(date: liveSnapshot.generatedAt, snapshot: liveSnapshot)
    static let cachedEntry = MearthWidgetEntry(date: cachedSnapshot.generatedAt, snapshot: cachedSnapshot)

    #if os(iOS)
    @available(iOSApplicationExtension 16.2, *)
    static let liveActivityAttributes = MearthLiveActivityAttributes(name: "Mearth")

    @available(iOSApplicationExtension 16.2, *)
    static let liveActivityState = MearthLiveActivityAttributes.ContentState(snapshot: liveSnapshot)

    @available(iOSApplicationExtension 16.2, *)
    static let cachedActivityState = MearthLiveActivityAttributes.ContentState(snapshot: cachedSnapshot)
    #endif
}

struct MearthWidgetPreviewProvider: PreviewProvider {
    static var previews: some View {
        Group {
            MearthWidgetView(entry: MearthWidgetPreviewData.liveEntry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("Small")

            MearthWidgetView(entry: MearthWidgetPreviewData.liveEntry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("Medium")

            MearthWidgetView(entry: MearthWidgetPreviewData.cachedEntry)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
                .previewDisplayName("Large Cached")

            #if os(iOS)
            MearthWidgetView(entry: MearthWidgetPreviewData.liveEntry)
                .previewContext(WidgetPreviewContext(family: .accessoryInline))
                .previewDisplayName("Inline")

            MearthWidgetView(entry: MearthWidgetPreviewData.liveEntry)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
                .previewDisplayName("Circular")

            MearthWidgetView(entry: MearthWidgetPreviewData.cachedEntry)
                .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
                .previewDisplayName("Rectangular")
            #endif
        }
    }
}

#if os(iOS)
@available(iOSApplicationExtension 16.2, *)
struct MearthLiveActivityPreviewProvider: PreviewProvider {
    static var previews: some View {
        Group {
            MearthLiveActivityContentView(state: MearthWidgetPreviewData.liveActivityState)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black)
                .previewDisplayName("Live Activity")

            HStack {
                DynamicIslandMetricView(label: "Mars", value: MearthWidgetPreviewData.liveActivityState.marsValue)
                Spacer()
                DynamicIslandMetricView(label: "Earth", value: MearthWidgetPreviewData.liveActivityState.earthValue)
            }
            .padding()
            .background(Color.black)
            .previewDisplayName("Dynamic Island Expanded")

            HStack(spacing: 12) {
                DynamicIslandCompactValueView(value: MearthWidgetPreviewData.cachedActivityState.marsValue)
                DynamicIslandCompactValueView(value: MearthWidgetPreviewData.cachedActivityState.localValue)
                DynamicIslandMinimalView()
            }
            .padding()
            .background(Color.black)
            .previewDisplayName("Dynamic Island Compact + Minimal")
        }
        .preferredColorScheme(.dark)
    }
}
#endif
#endif
