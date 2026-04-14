import Foundation

enum SharedCardKind: String, CaseIterable, Codable, Identifiable {
    case mars
    case earth
    case moon
    case local

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .mars:
            "Mars"
        case .earth:
            "Earth"
        case .moon:
            "Moon"
        case .local:
            "Local"
        }
    }
}

struct SharedWeatherCard: Codable, Identifiable, Hashable {
    let kind: SharedCardKind
    let title: String
    let subtitle: String
    let value: String
    let detail: String
    let footnote: String
    let isAvailable: Bool
    let isCached: Bool
    let lastUpdated: Date

    var id: SharedCardKind { kind }
}

struct SharedDashboardSnapshot: Codable, Hashable {
    let generatedAt: Date
    let cards: [SharedWeatherCard]
    let warning: String?

    func card(for kind: SharedCardKind) -> SharedWeatherCard? {
        cards.first(where: { $0.kind == kind })
    }

    var summaryLine: String {
        cards.prefix(2).compactMap { card in
            let cardValue = card.value
                .replacingOccurrences(of: "°C", with: "°")
                .replacingOccurrences(of: "°F", with: "°")
            return "\(card.kind.shortLabel) \(cardValue)"
        }
        .joined(separator: " · ")
    }
}

enum MearthShared {
    static let appGroupIdentifier = "group.com.sighmon.mearth"
    static let sharedSnapshotDefaultsKey = "Mearth.sharedDashboardSnapshot"
}

struct SharedDashboardSnapshotStore {
    private let defaults: UserDefaults?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(suiteName: String = MearthShared.appGroupIdentifier) {
        defaults = UserDefaults(suiteName: suiteName)
    }

    func load() -> SharedDashboardSnapshot? {
        guard let data = defaults?.data(forKey: MearthShared.sharedSnapshotDefaultsKey) else {
            return nil
        }
        return try? decoder.decode(SharedDashboardSnapshot.self, from: data)
    }

    func save(snapshot: SharedDashboardSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        defaults?.set(data, forKey: MearthShared.sharedSnapshotDefaultsKey)
    }

    static var preview: SharedDashboardSnapshot {
        SharedDashboardSnapshot(
            generatedAt: .now,
            cards: [
                SharedWeatherCard(
                    kind: .mars,
                    title: "Mars",
                    subtitle: "Curiosity at Gale Crater",
                    value: "-18°C",
                    detail: "LMST 14:42 · latest REMS sol 4849",
                    footnote: "REMS weather, modeled UV, RAD baseline.",
                    isAvailable: true,
                    isCached: false,
                    lastUpdated: .now
                ),
                SharedWeatherCard(
                    kind: .earth,
                    title: "Earth Match",
                    subtitle: "Reykjavik, Iceland",
                    value: "-16°C",
                    detail: "2°C difference from Mars right now",
                    footnote: "Live weather and UV, Earth background radiation.",
                    isAvailable: true,
                    isCached: false,
                    lastUpdated: .now
                ),
                SharedWeatherCard(
                    kind: .moon,
                    title: "Moon Estimate",
                    subtitle: "Apollo 11 · Tranquility Base",
                    value: "96°C",
                    detail: "Lunar local time 11:08",
                    footnote: "Modeled temperature and UV, Apollo-era radiation baseline.",
                    isAvailable: true,
                    isCached: false,
                    lastUpdated: .now
                ),
                SharedWeatherCard(
                    kind: .local,
                    title: "Local",
                    subtitle: "Adelaide, South Australia, Australia",
                    value: "22°C",
                    detail: "Current temperature near you",
                    footnote: "Live local weather and UV, Earth background radiation.",
                    isAvailable: true,
                    isCached: false,
                    lastUpdated: .now
                ),
            ],
            warning: nil
        )
    }
}

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

struct MearthLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let summaryLine: String
        let marsValue: String
        let earthValue: String
        let moonValue: String
        let localValue: String
        let updatedAt: Date
    }

    let name: String
}

extension MearthLiveActivityAttributes.ContentState {
    init(snapshot: SharedDashboardSnapshot) {
        summaryLine = snapshot.summaryLine
        marsValue = snapshot.card(for: .mars)?.value ?? "--"
        earthValue = snapshot.card(for: .earth)?.value ?? "--"
        moonValue = snapshot.card(for: .moon)?.value ?? "--"
        localValue = snapshot.card(for: .local)?.value ?? "--"
        updatedAt = snapshot.generatedAt
    }
}
#endif
