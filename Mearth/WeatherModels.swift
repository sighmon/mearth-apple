import Foundation

enum TemperatureCardKind: String, Identifiable {
    case mars
    case earth
    case moon
    case local

    var id: String { rawValue }
}

struct TemperatureCard: Identifiable {
    let kind: TemperatureCardKind
    let title: String
    let subtitle: String
    let value: String
    let detail: String
    let footnote: String

    var id: String { kind.id }
}

struct DashboardSnapshot {
    let generatedAt: Date
    let cards: [TemperatureCard]
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
}

struct LocalConditions {
    let label: String
    let temperature: Double
    let sourceNote: String
}
