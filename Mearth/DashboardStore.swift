import Foundation
import OSLog

private let dashboardLogger = Logger(subsystem: "com.sighmon.mearth", category: "Dashboard")

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var cards: [TemperatureCard] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastSuccessfulRefresh: Date?
    @Published private(set) var warning: String?

    private let composer: DashboardComposer
    private let cacheStore: DashboardCacheStore
    private var cachedCardsByKind: [TemperatureCardKind: TemperatureCard]

    init(composer: DashboardComposer = DashboardComposer(), cacheStore: DashboardCacheStore = DashboardCacheStore()) {
        self.composer = composer
        self.cacheStore = cacheStore
        let cachedCards = cacheStore.loadCards()
        self.cachedCardsByKind = Dictionary(uniqueKeysWithValues: cachedCards.map { ($0.kind, $0) })
        self.cards = Self.cardsForDisplay(
            cachedCards.map { card in
                TemperatureCard(
                    kind: card.kind,
                    title: card.title,
                    subtitle: card.subtitle,
                    value: card.value,
                    detail: card.detail,
                    footnote: card.footnote,
                    lastUpdated: card.lastUpdated,
                    isAvailable: card.isAvailable,
                    isCached: true,
                    location: card.location
                )
            }
        )
        self.lastSuccessfulRefresh = cachedCards.map(\.lastUpdated).max()
        dashboardLogger.info("DashboardStore initialized with \(cachedCards.count) cached cards")
    }

    init(
        previewCards: [TemperatureCard],
        isLoading: Bool = false,
        lastUpdated: Date? = nil,
        lastSuccessfulRefresh: Date? = nil,
        warning: String? = nil,
        composer: DashboardComposer = DashboardComposer(),
        cacheStore: DashboardCacheStore = DashboardCacheStore()
    ) {
        self.composer = composer
        self.cacheStore = cacheStore
        self.cards = Self.cardsForDisplay(previewCards)
        self.isLoading = isLoading
        self.lastUpdated = lastUpdated
        self.lastSuccessfulRefresh = lastSuccessfulRefresh
        self.warning = warning
        self.cachedCardsByKind = Dictionary(uniqueKeysWithValues: previewCards.map { ($0.kind, $0) })
    }

    func refreshIfNeeded() async {
        guard lastUpdated == nil else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        cards = Self.cardsForDisplay(cards)
        dashboardLogger.info("Dashboard refresh started with \(self.cards.count) visible cards")
        defer { isLoading = false }

        let refreshDate = Date.now
        async let localSnapshot = composer.makeLocalSnapshot(now: refreshDate)
        let primarySnapshot = await composer.makePrimarySnapshot(now: refreshDate)

        var warningMessages = [primarySnapshot.warning].compactMap { $0 }
        var mergedCards = merge(primarySnapshot.cards)
        cards = mergedCards
        warning = mergedWarning(base: warningMessages.joined(separator: " "), cards: mergedCards)
        lastUpdated = primarySnapshot.generatedAt
        lastSuccessfulRefresh = cachedCardsByKind.values.map(\.lastUpdated).max()
        dashboardLogger.info("Dashboard primary refresh published. warning=\(self.warning ?? "none"), cachedCards=\(mergedCards.filter { $0.isCached }.count)")

        let localCardSnapshot = await localSnapshot
        if let warning = localCardSnapshot.warning {
            warningMessages.append(warning)
        }

        mergedCards = merge([localCardSnapshot.card])
        cards = mergedCards
        warning = mergedWarning(base: warningMessages.joined(separator: " "), cards: mergedCards)
        lastUpdated = localCardSnapshot.generatedAt
        lastSuccessfulRefresh = cachedCardsByKind.values.map(\.lastUpdated).max()
        dashboardLogger.info("Dashboard refresh finished. warning=\(self.warning ?? "none"), cachedCards=\(mergedCards.filter { $0.isCached }.count)")
    }

    var hasCachedCards: Bool {
        cards.contains(where: \.isCached)
    }

    var lastCachedResultDate: Date? {
        cards
            .filter(\.isCached)
            .map(\.lastUpdated)
            .max()
    }

    private func merge(_ incomingCards: [TemperatureCard]) -> [TemperatureCard] {
        var mergedByKind = Dictionary(uniqueKeysWithValues: cards.map { ($0.kind, $0) })

        for card in incomingCards {
            if card.isAvailable {
                let liveCard = withCachedState(card, isCached: false)
                cachedCardsByKind[card.kind] = liveCard
                mergedByKind[card.kind] = liveCard
                dashboardLogger.info("Using live card for \(card.kind.rawValue)")
                continue
            }

            if let cached = cachedCardsByKind[card.kind] {
                mergedByKind[card.kind] = withCachedState(cached, isCached: true)
                dashboardLogger.info("Using cached card for \(card.kind.rawValue)")
            } else {
                mergedByKind[card.kind] = card
                dashboardLogger.error("No live or cached card available for \(card.kind.rawValue)")
            }
        }

        cacheStore.save(cards: Array(cachedCardsByKind.values))
        return Self.cardsForDisplay(TemperatureCardKind.allCases.compactMap { mergedByKind[$0] })
    }

    private func mergedWarning(base: String?, cards: [TemperatureCard]) -> String? {
        var messages: [String] = []

        if let base, !base.isEmpty {
            messages.append(base)
        }

        let cachedTitles = cards
            .filter(\.isCached)
            .map(\.title)

        if !cachedTitles.isEmpty {
            messages.append("Showing cached results for \(cachedTitles.joined(separator: ", ")).")
        }

        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    private func withCachedState(_ card: TemperatureCard, isCached: Bool) -> TemperatureCard {
        TemperatureCard(
            kind: card.kind,
            title: card.title,
            subtitle: card.subtitle,
            value: card.value,
            detail: card.detail,
            footnote: card.footnote,
            lastUpdated: card.lastUpdated,
            isAvailable: card.isAvailable,
            isCached: isCached,
            location: card.location
        )
    }

    private static func cardsForDisplay(_ cards: [TemperatureCard]) -> [TemperatureCard] {
        let byKind = Dictionary(uniqueKeysWithValues: cards.map { ($0.kind, $0) })
        return TemperatureCardKind.allCases.compactMap { byKind[$0] ?? placeholderCard(for: $0) }
    }

    private static func placeholderCard(for kind: TemperatureCardKind) -> TemperatureCard? {
        switch kind {
        case .mars:
            TemperatureCard(
                kind: .mars,
                title: "Mars",
                subtitle: "Curiosity at Gale Crater",
                value: "--",
                detail: "Refreshing Curiosity weather",
                footnote: "Waiting for the latest official REMS range.",
                lastUpdated: .now,
                isAvailable: false,
                isCached: false,
                location: nil
            )
        case .earth:
            TemperatureCard(
                kind: .earth,
                title: "Earth Match",
                subtitle: "Finding a current city match",
                value: "--",
                detail: "Comparing Earth temperatures with Mars",
                footnote: "Waiting for the latest current conditions.",
                lastUpdated: .now,
                isAvailable: false,
                isCached: false,
                location: nil
            )
        case .moon:
            TemperatureCard(
                kind: .moon,
                title: "Moon Estimate",
                subtitle: "Apollo 11 · Tranquility Base",
                value: "--",
                detail: "Calculating lunar local time",
                footnote: "Waiting for the latest modeled estimate.",
                lastUpdated: .now,
                isAvailable: false,
                isCached: false,
                location: nil
            )
        case .local:
            TemperatureCard(
                kind: .local,
                title: "Local",
                subtitle: "Resolving your current weather",
                value: "--",
                detail: "Checking Apple location services and weather",
                footnote: "Falling back to network location if needed.",
                lastUpdated: .now,
                isAvailable: false,
                isCached: false,
                location: nil
            )
        }
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
                    lastUpdated: Date(),
                    isAvailable: true,
                    isCached: false,
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
                    footnote: "Closest current city match from a global sample via Apple Weather.",
                    lastUpdated: Date(),
                    isAvailable: true,
                    isCached: false,
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
                    lastUpdated: Date(),
                    isAvailable: true,
                    isCached: false,
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
                    lastUpdated: Date(),
                    isAvailable: true,
                    isCached: false,
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
            lastSuccessfulRefresh: Date(),
            warning: "Preview data only."
        )
    }
}

struct DashboardCacheStore {
    private let defaults: UserDefaults
    private let cacheKey = "DashboardStore.cachedCards"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadCards() -> [TemperatureCard] {
        guard let data = defaults.data(forKey: cacheKey) else {
            return []
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode([TemperatureCard].self, from: data)) ?? []
    }

    func save(cards: [TemperatureCard]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(cards) else {
            return
        }

        defaults.set(data, forKey: cacheKey)
    }
}
