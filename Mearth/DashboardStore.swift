import Foundation
import OSLog

private let dashboardLogger = Logger(subsystem: "com.sighmon.mearth", category: "Dashboard")

enum DashboardDevelopmentOptions {
    // Flip this to true during development to bypass all live API calls.
    static let usePreviewData = false
}

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var cards: [TemperatureCard] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastSuccessfulRefresh: Date?
    @Published private(set) var warning: String?

    private let composer: DashboardComposer
    private let cacheStore: DashboardCacheStore
    private let sharedSnapshotStore: SharedDashboardSnapshotStore
    private var cachedCardsByKind: [TemperatureCardKind: TemperatureCard]
    private var primaryWarning: String?
    private var localWarning: String?

    init(
        composer: DashboardComposer = DashboardComposer(),
        cacheStore: DashboardCacheStore = DashboardCacheStore(),
        sharedSnapshotStore: SharedDashboardSnapshotStore = SharedDashboardSnapshotStore()
    ) {
        self.composer = composer
        self.cacheStore = cacheStore
        self.sharedSnapshotStore = sharedSnapshotStore

        if DashboardDevelopmentOptions.usePreviewData {
            let previewCards = Self.developmentPreviewCards(referenceDate: .now)
            self.cachedCardsByKind = Dictionary(uniqueKeysWithValues: previewCards.map { ($0.kind, $0) })
            self.cards = Self.cardsForDisplay(previewCards)
            self.lastUpdated = previewCards.map(\.lastUpdated).max()
            self.lastSuccessfulRefresh = self.lastUpdated
            self.warning = "Preview data only."
            self.primaryWarning = self.warning
            publishSharedSnapshot(cards: self.cards, generatedAt: self.lastUpdated ?? .now, warning: self.warning)
            dashboardLogger.info("DashboardStore initialized in preview development mode")
            return
        }

        let cachedCards = cacheStore.loadCards()
        self.cachedCardsByKind = Dictionary(uniqueKeysWithValues: cachedCards.map { ($0.kind, $0) })
        self.cards = Self.cardsForDisplay(
            cachedCards.map { card in
                TemperatureCard(
                    kind: card.kind,
                    title: card.title,
                    subtitle: card.subtitle,
                    value: card.value,
                    temperatureCelsius: card.temperatureCelsius,
                    temperatureDeltaCelsius: card.temperatureDeltaCelsius,
                    temperatureRegionCode: card.temperatureRegionCode,
                    supportingMetrics: card.supportingMetrics,
                    sourceNote: card.sourceNote,
                    earthComparisonCandidates: card.earthComparisonCandidates,
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
        publishSharedSnapshot(cards: self.cards, generatedAt: self.lastSuccessfulRefresh ?? .now, warning: self.warning)
        dashboardLogger.info("DashboardStore initialized with \(cachedCards.count) cached cards")
    }

    init(
        previewCards: [TemperatureCard],
        isLoading: Bool = false,
        lastUpdated: Date? = nil,
        lastSuccessfulRefresh: Date? = nil,
        warning: String? = nil,
        composer: DashboardComposer = DashboardComposer(),
        cacheStore: DashboardCacheStore = DashboardCacheStore(),
        sharedSnapshotStore: SharedDashboardSnapshotStore = SharedDashboardSnapshotStore()
    ) {
        self.composer = composer
        self.cacheStore = cacheStore
        self.sharedSnapshotStore = sharedSnapshotStore
        self.cards = Self.cardsForDisplay(previewCards)
        self.isLoading = isLoading
        self.lastUpdated = lastUpdated
        self.lastSuccessfulRefresh = lastSuccessfulRefresh
        self.warning = warning
        self.primaryWarning = warning
        self.cachedCardsByKind = Dictionary(uniqueKeysWithValues: previewCards.map { ($0.kind, $0) })
        publishSharedSnapshot(cards: self.cards, generatedAt: lastUpdated ?? .now, warning: warning)
    }

    func refreshIfNeeded() async {
        if DashboardDevelopmentOptions.usePreviewData {
            await refresh()
            return
        }
        guard lastUpdated == nil else { return }
        await refresh()
    }

    func refresh() async {
        if DashboardDevelopmentOptions.usePreviewData {
            let previewCards = Self.developmentPreviewCards(referenceDate: .now)
            cards = Self.cardsForDisplay(previewCards)
            warning = "Preview data only."
            lastUpdated = previewCards.map(\.lastUpdated).max()
            lastSuccessfulRefresh = lastUpdated
            primaryWarning = warning
            localWarning = nil
            cachedCardsByKind = Dictionary(uniqueKeysWithValues: previewCards.map { ($0.kind, $0) })
            publishSharedSnapshot(cards: cards, generatedAt: lastUpdated ?? .now, warning: warning)
            dashboardLogger.info("Dashboard refresh served preview development data")
            return
        }

        guard !isLoading else { return }

        isLoading = true
        cards = Self.cardsForDisplay(cards)
        dashboardLogger.info("Dashboard refresh started with \(self.cards.count) visible cards")
        defer { isLoading = false }

        let refreshDate = Date.now
        localWarning = nil
        async let localSnapshot = composer.makeLocalSnapshot(now: refreshDate)
        let primarySnapshot = await composer.makePrimarySnapshot(now: refreshDate)

        primaryWarning = primarySnapshot.warning
        var mergedCards = merge(primarySnapshot.cards)
        cards = mergedCards
        warning = mergedWarning(base: combinedBaseWarning, cards: mergedCards)
        lastUpdated = primarySnapshot.generatedAt
        lastSuccessfulRefresh = cachedCardsByKind.values.map(\.lastUpdated).max()
        publishSharedSnapshot(cards: mergedCards, generatedAt: primarySnapshot.generatedAt, warning: warning)
        dashboardLogger.info("Dashboard primary refresh published. warning=\(self.warning ?? "none"), cachedCards=\(mergedCards.filter { $0.isCached }.count)")

        let localCardSnapshot = await localSnapshot
        localWarning = localCardSnapshot.warning

        mergedCards = merge([localCardSnapshot.card])
        cards = mergedCards
        warning = mergedWarning(base: combinedBaseWarning, cards: mergedCards)
        lastUpdated = localCardSnapshot.generatedAt
        lastSuccessfulRefresh = cachedCardsByKind.values.map(\.lastUpdated).max()
        publishSharedSnapshot(cards: mergedCards, generatedAt: localCardSnapshot.generatedAt, warning: warning)
        dashboardLogger.info("Dashboard refresh finished. warning=\(self.warning ?? "none"), cachedCards=\(mergedCards.filter { $0.isCached }.count)")
    }

    func refreshLocalCardIfNeeded() async {
        if DashboardDevelopmentOptions.usePreviewData || isLoading {
            return
        }

        guard let localCard = cards.first(where: { $0.kind == .local }), !localCard.isAvailable else {
            return
        }

        dashboardLogger.info("Retrying local card refresh")
        let localSnapshot = await composer.makeLocalSnapshot(now: .now)
        localWarning = localSnapshot.warning

        let mergedCards = merge([localSnapshot.card])
        cards = mergedCards
        warning = mergedWarning(base: combinedBaseWarning, cards: mergedCards)
        lastUpdated = localSnapshot.generatedAt
        lastSuccessfulRefresh = cachedCardsByKind.values.map(\.lastUpdated).max()
        publishSharedSnapshot(cards: mergedCards, generatedAt: localSnapshot.generatedAt, warning: warning)
        dashboardLogger.info("Local card retry finished. warning=\(self.warning ?? "none"), cachedCards=\(mergedCards.filter { $0.isCached }.count)")
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
            temperatureCelsius: card.temperatureCelsius,
            temperatureDeltaCelsius: card.temperatureDeltaCelsius,
            temperatureRegionCode: card.temperatureRegionCode,
            supportingMetrics: card.supportingMetrics,
            sourceNote: card.sourceNote,
            earthComparisonCandidates: card.earthComparisonCandidates,
            detail: card.detail,
            footnote: card.footnote,
            lastUpdated: card.lastUpdated,
            isAvailable: card.isAvailable,
            isCached: isCached,
            location: card.location
        )
    }

    private func publishSharedSnapshot(cards: [TemperatureCard], generatedAt: Date, warning: String?) {
        let snapshot = SharedDashboardSnapshot(
            generatedAt: generatedAt,
            cards: cards.map(Self.sharedCard),
            warning: warning
        )
        sharedSnapshotStore.save(snapshot: snapshot)
        #if canImport(ActivityKit) && os(iOS)
        if #available(iOS 16.2, *) {
            Task { @MainActor in
                await MearthLiveActivityManager.update(snapshot: snapshot)
            }
        }
        #endif
    }

    private static func sharedCard(_ card: TemperatureCard) -> SharedWeatherCard {
        SharedWeatherCard(
            kind: SharedCardKind(rawValue: card.kind.rawValue) ?? .mars,
            title: card.title,
            subtitle: card.subtitle,
            value: card.value,
            detail: card.detail,
            footnote: card.footnote,
            isAvailable: card.isAvailable,
            isCached: card.isCached,
            lastUpdated: card.lastUpdated
        )
    }

    private static func cardsForDisplay(_ cards: [TemperatureCard]) -> [TemperatureCard] {
        let byKind = Dictionary(uniqueKeysWithValues: cards.map { ($0.kind, $0) })
        return TemperatureCardKind.allCases.compactMap { byKind[$0] ?? placeholderCard(for: $0) }
    }

    private var combinedBaseWarning: String? {
        let warnings = [primaryWarning, localWarning]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return warnings.isEmpty ? nil : warnings.joined(separator: " ")
    }

    private static func placeholderCard(for kind: TemperatureCardKind) -> TemperatureCard? {
        switch kind {
        case .mars:
            TemperatureCard(
                kind: .mars,
                title: "Mars",
                subtitle: "Curiosity at Gale Crater",
                value: "--",
                supportingMetrics: [],
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
                supportingMetrics: [],
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
                supportingMetrics: [],
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
                supportingMetrics: [],
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
    static func developmentPreviewCards(referenceDate: Date = Date()) -> [TemperatureCard] {
        [
            TemperatureCard(
                kind: .mars,
                title: "Mars",
                subtitle: "Curiosity at Gale Crater",
                value: "-18°C",
                temperatureCelsius: -18,
                supportingMetrics: [
                    CardSupportingMetric(label: "UV INDEX", value: "4.0"),
                    CardSupportingMetric(label: "RADIATION", value: "27.8 µSv/h"),
                ],
                sourceNote: "Official CAB Curiosity REMS weather feed, with modeled UV-equivalent and NASA/JPL RAD baseline context.",
                detail: "LMST 14:42 · latest REMS sol 4849",
                footnote: "REMS weather, modeled UV, RAD baseline.",
                lastUpdated: referenceDate,
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
                temperatureCelsius: -16,
                temperatureDeltaCelsius: 2,
                supportingMetrics: [
                    CardSupportingMetric(label: "UV INDEX", value: "0.3"),
                    CardSupportingMetric(label: "RADIATION", value: "0.06 µSv/h"),
                ],
                sourceNote: "Closest current city match from the app's sampled global city set via Open-Meteo. The modal shows the full sampled comparison list.",
                earthComparisonCandidates: [
                    EarthComparisonCandidate(city: "Reykjavik", country: "Iceland", temperature: -16.0, uvIndex: 0.3, latitude: 64.1466, longitude: -21.9426, temperatureDeltaFromReference: 2.0, isSelectedMatch: true),
                    EarthComparisonCandidate(city: "Tromso", country: "Norway", temperature: -12.0, uvIndex: 0.1, latitude: 69.6496, longitude: 18.9560, temperatureDeltaFromReference: 6.0, isSelectedMatch: false),
                    EarthComparisonCandidate(city: "Iqaluit", country: "Canada", temperature: -10.0, uvIndex: 0.0, latitude: 63.7467, longitude: -68.5170, temperatureDeltaFromReference: 8.0, isSelectedMatch: false),
                ],
                detail: "2°C difference from Mars right now",
                footnote: "Live weather and UV, Earth background radiation.",
                lastUpdated: referenceDate,
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
                temperatureCelsius: 96,
                supportingMetrics: [
                    CardSupportingMetric(label: "UV INDEX", value: "11.2"),
                    CardSupportingMetric(label: "RADIATION", value: "32.0 µSv/h"),
                ],
                sourceNote: "Modeled lunar surface conditions at Tranquility Base using local solar angle, UV-equivalent scaling, and Apollo-era radiation context.",
                detail: "Lunar local time 11:08",
                footnote: "Modeled temperature and UV, Apollo-era radiation baseline.",
                lastUpdated: referenceDate,
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
                temperatureCelsius: 22,
                temperatureRegionCode: "AU",
                supportingMetrics: [
                    CardSupportingMetric(label: "UV INDEX", value: "5.1"),
                    CardSupportingMetric(label: "RADIATION", value: "0.06 µSv/h"),
                ],
                sourceNote: "Current device location via Apple Location Services, with current weather and UV from Apple Weather.",
                detail: "Current temperature near you",
                footnote: "Live local weather and UV, Earth background radiation.",
                lastUpdated: referenceDate,
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
        ]
    }

    static var preview: DashboardStore {
        DashboardStore(
            previewCards: developmentPreviewCards(),
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
