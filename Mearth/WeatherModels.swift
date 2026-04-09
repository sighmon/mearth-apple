import Foundation

enum TemperatureCardKind: String, CaseIterable, Codable, Identifiable {
    case mars
    case earth
    case moon
    case local

    var id: String { rawValue }
}

enum CelestialBody: String, Codable {
    case earth
    case mars
    case moon
}

struct CardLocation: Codable, Identifiable {
    let title: String
    let subtitle: String
    let body: CelestialBody
    let latitude: Double
    let longitude: Double
    let note: String

    var id: String {
        "\(body.rawValue)-\(title)-\(latitude)-\(longitude)"
    }
}

struct TemperatureCard: Codable, Identifiable {
    let kind: TemperatureCardKind
    let title: String
    let subtitle: String
    let value: String
    let supportingMetrics: [CardSupportingMetric]
    let detail: String
    let footnote: String
    let lastUpdated: Date
    let isAvailable: Bool
    let isCached: Bool
    let location: CardLocation?

    var id: String { kind.id }

    enum CodingKeys: String, CodingKey {
        case kind
        case title
        case subtitle
        case value
        case supportingMetrics
        case detail
        case footnote
        case lastUpdated
        case isAvailable
        case isCached
        case location
    }

    init(
        kind: TemperatureCardKind,
        title: String,
        subtitle: String,
        value: String,
        supportingMetrics: [CardSupportingMetric] = [],
        detail: String,
        footnote: String,
        lastUpdated: Date,
        isAvailable: Bool,
        isCached: Bool,
        location: CardLocation?
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.supportingMetrics = supportingMetrics
        self.detail = detail
        self.footnote = footnote
        self.lastUpdated = lastUpdated
        self.isAvailable = isAvailable
        self.isCached = isCached
        self.location = location
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(TemperatureCardKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        value = try container.decode(String.self, forKey: .value)
        supportingMetrics = try container.decodeIfPresent([CardSupportingMetric].self, forKey: .supportingMetrics) ?? []
        detail = try container.decode(String.self, forKey: .detail)
        footnote = try container.decode(String.self, forKey: .footnote)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        isAvailable = try container.decode(Bool.self, forKey: .isAvailable)
        isCached = try container.decode(Bool.self, forKey: .isCached)
        location = try container.decodeIfPresent(CardLocation.self, forKey: .location)
    }
}

struct CardSupportingMetric: Codable, Identifiable, Hashable {
    let label: String
    let value: String

    var id: String { label }
}

struct DashboardSnapshot {
    let generatedAt: Date
    let cards: [TemperatureCard]
    let warning: String?
}

struct DashboardCardSnapshot {
    let generatedAt: Date
    let card: TemperatureCard
    let warning: String?
}

struct MarsConditions {
    let sol: Int
    let terrestrialDate: Date
    let season: String
    let sunriseHour: Double
    let sunsetHour: Double
    let minTemperature: Double
    let maxTemperature: Double
    let localMeanSolarTime: Double
    let estimatedCurrentTemperature: Double
    let uvIndexCategory: String
}

struct EarthCityTemperature {
    let city: String
    let country: String
    let temperature: Double
    let uvIndex: Double?
    let latitude: Double
    let longitude: Double
    let sourceNote: String
}

struct LocalConditions {
    let label: String
    let temperature: Double
    let uvIndex: Double?
    let sourceNote: String
    let latitude: Double
    let longitude: Double
}
