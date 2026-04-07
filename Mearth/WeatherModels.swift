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
    let detail: String
    let footnote: String
    let lastUpdated: Date
    let isAvailable: Bool
    let isCached: Bool
    let location: CardLocation?

    var id: String { kind.id }
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
}

struct EarthCityTemperature {
    let city: String
    let country: String
    let temperature: Double
    let latitude: Double
    let longitude: Double
    let sourceNote: String
}

struct LocalConditions {
    let label: String
    let temperature: Double
    let sourceNote: String
    let latitude: Double
    let longitude: Double
}
