import Foundation
import SwiftUI

enum TemperatureUnitPreference: String, CaseIterable, Identifiable {
    case automatic
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "Auto"
        case .celsius:
            return "°C"
        case .fahrenheit:
            return "°F"
        }
    }
}

enum TemperatureDisplayUnit {
    case celsius
    case fahrenheit

    var symbol: String {
        switch self {
        case .celsius:
            return "°C"
        case .fahrenheit:
            return "°F"
        }
    }
}

@MainActor
final class TemperatureUnitStore: ObservableObject {
    @Published private(set) var preference: TemperatureUnitPreference
    @Published private(set) var detectedCountryCode: String?

    private let defaults: UserDefaults
    private let preferenceKey = "TemperatureUnitStore.preference"
    private let countryCodeKey = "TemperatureUnitStore.detectedCountryCode"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preference = TemperatureUnitPreference(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .automatic
        self.detectedCountryCode = defaults.string(forKey: countryCodeKey)
    }

    var resolvedUnit: TemperatureDisplayUnit {
        switch preference {
        case .automatic:
            return Self.usesFahrenheit(for: detectedCountryCode ?? Self.currentRegionCode)
                ? .fahrenheit
                : .celsius
        case .celsius:
            return .celsius
        case .fahrenheit:
            return .fahrenheit
        }
    }

    func setPreference(_ newValue: TemperatureUnitPreference) {
        preference = newValue
        defaults.set(newValue.rawValue, forKey: preferenceKey)
    }

    func applyDetectedCountryCode(_ countryCode: String?) {
        let normalized = countryCode?.uppercased()
        guard detectedCountryCode != normalized else {
            return
        }

        detectedCountryCode = normalized
        if let normalized {
            defaults.set(normalized, forKey: countryCodeKey)
        } else {
            defaults.removeObject(forKey: countryCodeKey)
        }
    }

    func formattedTemperature(celsius: Double, fractionDigits: Int = 0) -> String {
        let value = convertedValue(fromCelsius: celsius)
        return "\(Self.numberString(value, fractionDigits: fractionDigits))\(resolvedUnit.symbol)"
    }

    func formattedTemperatureDelta(celsius: Double, fractionDigits: Int = 0) -> String {
        let value = abs(convertedDelta(fromCelsius: celsius))
        return "\(Self.numberString(value, fractionDigits: fractionDigits))\(resolvedUnit.symbol)"
    }

    private func convertedValue(fromCelsius celsius: Double) -> Double {
        switch resolvedUnit {
        case .celsius:
            return celsius
        case .fahrenheit:
            return (celsius * 9 / 5) + 32
        }
    }

    private func convertedDelta(fromCelsius celsius: Double) -> Double {
        switch resolvedUnit {
        case .celsius:
            return celsius
        case .fahrenheit:
            return celsius * 9 / 5
        }
    }

    private static func numberString(_ value: Double, fractionDigits: Int) -> String {
        if fractionDigits == 0 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.\(fractionDigits)f", value)
    }

    private static func usesFahrenheit(for countryCode: String?) -> Bool {
        guard let countryCode else {
            return false
        }

        switch countryCode.uppercased() {
        case "US", "BS", "BZ", "KY", "PW", "LR", "FM", "MH":
            return true
        default:
            return false
        }
    }

    private static var currentRegionCode: String? {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            return Locale.autoupdatingCurrent.region?.identifier
        } else {
            return Locale.autoupdatingCurrent.regionCode
        }
    }
}
