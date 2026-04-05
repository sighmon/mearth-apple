import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var cards: [TemperatureCard] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var warning: String?

    private let composer: DashboardComposer

    init(composer: DashboardComposer = DashboardComposer()) {
        self.composer = composer
    }

    init(
        previewCards: [TemperatureCard],
        isLoading: Bool = false,
        lastUpdated: Date? = nil,
        warning: String? = nil,
        composer: DashboardComposer = DashboardComposer()
    ) {
        self.composer = composer
        self.cards = previewCards
        self.isLoading = isLoading
        self.lastUpdated = lastUpdated
        self.warning = warning
    }

    func refreshIfNeeded() async {
        guard cards.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        let snapshot = await composer.makeSnapshot(now: .now)
        cards = snapshot.cards
        warning = snapshot.warning
        lastUpdated = snapshot.generatedAt
    }
}

extension DashboardStore {
    static var preview: DashboardStore {
        DashboardStore(
            previewCards: [
                TemperatureCard(
                    kind: .mars,
                    title: "Mars",
                    subtitle: "Curiosity at Gale Crater",
                    value: "-18°C",
                    detail: "LMST 14:42 · latest REMS sol 4849",
                    footnote: "Estimated from the latest official REMS range.",
                    location: CardLocation(
                        title: "Curiosity Rover",
                        subtitle: "Gale Crater, Mars",
                        body: .mars,
                        latitude: -4.5895,
                        longitude: 137.4417,
                        note: "Preview planetary locator."
                    )
                ),
                TemperatureCard(
                    kind: .earth,
                    title: "Earth Match",
                    subtitle: "Reykjavik, Iceland",
                    value: "-16°C",
                    detail: "2°C difference from Mars right now",
                    footnote: "Closest current city match from a broad global Open-Meteo sample.",
                    location: CardLocation(
                        title: "Reykjavik",
                        subtitle: "Iceland",
                        body: .earth,
                        latitude: 64.1466,
                        longitude: -21.9426,
                        note: "Preview Apple Maps location."
                    )
                ),
                TemperatureCard(
                    kind: .moon,
                    title: "Moon Estimate",
                    subtitle: "Apollo 11 · Tranquility Base",
                    value: "96°C",
                    detail: "Lunar local time 11:08",
                    footnote: "Modeled from lunar phase and solar angle at the landing site, not a live sensor feed.",
                    location: CardLocation(
                        title: "Apollo 11",
                        subtitle: "Tranquility Base, Moon",
                        body: .moon,
                        latitude: 0.6741,
                        longitude: 23.4729,
                        note: "Preview lunar locator."
                    )
                ),
                TemperatureCard(
                    kind: .local,
                    title: "Local",
                    subtitle: "Adelaide, South Australia, Australia",
                    value: "22°C",
                    detail: "Current temperature near you",
                    footnote: "Approximate network location from ipapi.co, then current Open-Meteo conditions.",
                    location: CardLocation(
                        title: "Your Approximate Location",
                        subtitle: "Adelaide, South Australia, Australia",
                        body: .earth,
                        latitude: -34.9285,
                        longitude: 138.6007,
                        note: "Preview Apple Maps location."
                    )
                ),
            ],
            lastUpdated: Date(),
            warning: "Preview data only."
        )
    }
}
