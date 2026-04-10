import Foundation
import OSLog
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(WeatherKit)
import WeatherKit
#endif

private let weatherLogger = Logger(subsystem: "com.sighmon.mearth", category: "Weather")

struct DashboardComposer {
    private let marsService = MarsWeatherService()
    private let earthService = EarthTemperatureService()
    private let moonService = MoonTemperatureEstimator()
    private let localService = LocalWeatherService()

    func makePrimarySnapshot(now: Date) async -> DashboardSnapshot {
        weatherLogger.info("Primary snapshot refresh started at \(now.formatted(date: .abbreviated, time: .standard))")
        var cards: [TemperatureCard] = []
        var warnings: [String] = []

        let marsResult = await loadMarsResult(at: now)
        let moonEstimate = moonService.estimate(at: now)

        switch marsResult {
        case .success(let mars):
            weatherLogger.info("Mars refresh succeeded for sol \(mars.sol)")
            cards.append(
                    TemperatureCard(
                        kind: .mars,
                        title: "Mars",
                        subtitle: "Curiosity at Gale Crater",
                        value: Self.temperatureString(mars.estimatedCurrentTemperature),
                        supportingMetrics: [
                            Self.uvMetric(Self.marsUVIndexEquivalent(mars)),
                            Self.radiationMetric(Self.marsRadiationDoseRate),
                        ],
                        sourceNote: "Official CAB Curiosity REMS weather feed, with modeled UV-equivalent and NASA/JPL RAD baseline context.",
                        detail: "LMST \(Self.hourMinuteString(mars.localMeanSolarTime)) · latest REMS sol \(mars.sol)",
                        footnote: "REMS weather, modeled UV, RAD baseline.",
                        lastUpdated: now,
                        isAvailable: true,
                        isCached: false,
                    location: CardLocation(
                        title: "Curiosity Rover",
                        subtitle: "Gale Crater, Mars",
                        body: .mars,
                        latitude: -4.5895,
                        longitude: 137.4417,
                        note: "Planetary locator centered on Curiosity's landing region."
                    )
                )
            )

            do {
                let earthMatch = try await earthService.closestCityMatch(for: mars.estimatedCurrentTemperature)
                let delta = abs(earthMatch.temperature - mars.estimatedCurrentTemperature)
                weatherLogger.info("Earth match succeeded: \(earthMatch.city), \(earthMatch.country) at \(earthMatch.temperature, format: .fixed(precision: 1))C")
                cards.append(
                    TemperatureCard(
                        kind: .earth,
                        title: "Earth Match",
                        subtitle: "\(earthMatch.city), \(earthMatch.country)",
                        value: Self.temperatureString(earthMatch.temperature),
                        supportingMetrics: [
                            Self.uvMetric(earthMatch.uvIndex),
                            Self.radiationMetric(Self.earthRadiationDoseRate),
                        ],
                        sourceNote: earthMatch.sourceNote,
                        earthComparisonCandidates: earthMatch.comparisonCandidates,
                        detail: "\(Self.temperatureDeltaString(delta)) from Mars right now",
                        footnote: "Live weather and UV, Earth background radiation.",
                        lastUpdated: now,
                        isAvailable: true,
                        isCached: false,
                        location: CardLocation(
                            title: earthMatch.city,
                            subtitle: earthMatch.country,
                            body: .earth,
                            latitude: earthMatch.latitude,
                            longitude: earthMatch.longitude,
                            note: "Shown with native Apple Maps."
                        )
                    )
                )
            } catch {
                weatherLogger.error("Earth match failed: \(error.localizedDescription)")
                warnings.append("Earth comparison cities are unavailable: \(error.localizedDescription)")
                cards.append(
                    TemperatureCard(
                        kind: .earth,
                        title: "Earth Match",
                        subtitle: "Global city sample unavailable",
                        value: "--",
                        supportingMetrics: [],
                        sourceNote: "Open-Meteo did not return the sampled comparison set.",
                        detail: "Open-Meteo did not return a usable comparison set.",
                        footnote: "Mars is still shown from Curiosity's official feed.",
                        lastUpdated: now,
                        isAvailable: false,
                        isCached: false,
                        location: nil
                    )
                )
            }

        case .failure(let error):
            weatherLogger.error("Mars refresh failed: \(error.localizedDescription)")
            cards.append(
                TemperatureCard(
                    kind: .mars,
                    title: "Mars",
                    subtitle: "Curiosity feed unavailable",
                    value: "--",
                    supportingMetrics: [],
                    sourceNote: "CAB's Curiosity weather widget feed is unavailable right now.",
                    detail: "The official REMS endpoint did not return a usable payload.",
                    footnote: "This card uses CAB's Curiosity weather widget feed when it is reachable.",
                    lastUpdated: now,
                    isAvailable: false,
                    isCached: false,
                    location: nil
                )
            )
            cards.append(
                TemperatureCard(
                    kind: .earth,
                    title: "Earth Match",
                    subtitle: "Waiting on the Mars reference temperature",
                    value: "--",
                    supportingMetrics: [],
                    sourceNote: "The Earth comparison needs a current Mars reference temperature first.",
                    detail: "A comparison city needs the Curiosity reading first.",
                    footnote: "Refresh again when the Mars feed is back.",
                    lastUpdated: now,
                    isAvailable: false,
                    isCached: false,
                    location: nil
                )
            )
            warnings.append("Curiosity weather could not be refreshed: \(error.localizedDescription)")
        }

        cards.append(
            TemperatureCard(
                kind: .moon,
                title: "Moon Estimate",
                subtitle: "Apollo 11 · Tranquility Base",
                value: Self.temperatureString(moonEstimate.temperature),
                supportingMetrics: [
                    Self.uvMetric(Self.moonUVIndexEquivalent(moonEstimate)),
                    Self.radiationMetric(Self.moonRadiationDoseRate),
                ],
                sourceNote: "Modeled lunar surface conditions at Tranquility Base using local solar angle, UV-equivalent scaling, and Apollo-era radiation context.",
                detail: "Lunar local time \(Self.hourMinuteString(moonEstimate.localHour))",
                footnote: "Modeled temperature and UV, Apollo-era radiation baseline.",
                lastUpdated: now,
                isAvailable: true,
                isCached: false,
                location: CardLocation(
                    title: "Apollo 11",
                    subtitle: "Tranquility Base, Moon",
                    body: .moon,
                    latitude: 0.6741,
                    longitude: 23.4729,
                    note: "Lunar locator with the landing coordinates."
                )
            )
        )

        weatherLogger.info("Primary snapshot refresh finished with \(cards.count) cards")
        return DashboardSnapshot(
            generatedAt: now,
            cards: cards,
            warning: warnings.isEmpty ? nil : warnings.joined(separator: " ")
        )
    }

    func makeLocalSnapshot(now: Date) async -> DashboardCardSnapshot {
        weatherLogger.info("Local card refresh started")
        switch await loadLocalResult() {
        case .success(let local):
            weatherLogger.info("Local weather succeeded for \(local.label) at \(local.temperature, format: .fixed(precision: 1))C")
            return DashboardCardSnapshot(
                generatedAt: now,
                card: TemperatureCard(
                    kind: .local,
                    title: "Local",
                    subtitle: local.label,
                    value: Self.temperatureString(local.temperature),
                    supportingMetrics: [
                        Self.uvMetric(local.uvIndex),
                        Self.radiationMetric(Self.earthRadiationDoseRate),
                    ],
                    sourceNote: local.sourceNote,
                    detail: "Current temperature near you",
                    footnote: " Weather and UV, Earth background radiation.",
                    lastUpdated: now,
                    isAvailable: true,
                    isCached: false,
                    location: CardLocation(
                        title: "Your Approximate Location",
                        subtitle: local.label,
                        body: .earth,
                        latitude: local.latitude,
                        longitude: local.longitude,
                        note: "Shown with native Apple Maps. Network geolocation may be approximate."
                    )
                ),
                warning: nil
            )
        case .failure(let error):
            weatherLogger.error("Local weather failed: \(error.localizedDescription)")
            return DashboardCardSnapshot(
                generatedAt: now,
                card: TemperatureCard(
                    kind: .local,
                    title: "Local",
                    subtitle: "Current location unavailable",
                    value: "--",
                    supportingMetrics: [],
                    sourceNote: "Apple location services and network fallback both failed to resolve a current local weather reading.",
                    detail: "IP geolocation or local forecast lookup failed.",
                    footnote: "This card falls back to network location so it also works on Apple TV.",
                    lastUpdated: now,
                    isAvailable: false,
                    isCached: false,
                    location: nil
                ),
                warning: "Local weather could not be resolved: \(error.localizedDescription)"
            )
        }
    }

    private func loadMarsResult(at now: Date) async -> Result<MarsConditions, Error> {
        do {
            return .success(try await withTimeout(seconds: 15) {
                try await marsService.fetchCurrentConditions(at: now)
            })
        } catch {
            return .failure(error)
        }
    }

    private func loadLocalResult() async -> Result<LocalConditions, Error> {
        weatherLogger.info("Starting local weather task with a 20 second dashboard budget")
        do {
            return .success(try await withTimeout(seconds: 20) {
                try await localService.fetchCurrentConditions()
            })
        } catch {
            weatherLogger.error("Local weather task failed before snapshot completion: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    private static func temperatureString(_ value: Double) -> String {
        "\(Int(value.rounded()))°C"
    }

    private static func temperatureDeltaString(_ value: Double) -> String {
        "\(Int(value.rounded()))°C difference"
    }

    private static func dateString(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day())
    }

    private static let earthRadiationDoseRate = 0.06
    private static let marsRadiationDoseRate = 27.8
    private static let moonRadiationDoseRate = 32.0

    private static func uvMetric(_ value: Double?) -> CardSupportingMetric {
        CardSupportingMetric(label: "UV INDEX", value: uvIndexString(value))
    }

    private static func radiationMetric(_ value: Double) -> CardSupportingMetric {
        CardSupportingMetric(label: "RADIATION", value: radiationString(value))
    }

    private static func uvIndexString(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return "\(String(format: "%.1f", value))"
    }

    private static func radiationString(_ value: Double) -> String {
        "\(String(format: "%.2f", value)) µSv/h"
    }

    private static func marsUVIndexEquivalent(_ mars: MarsConditions) -> Double? {
        let peakIndex = marsPeakUVIndex(for: mars.uvIndexCategory)
        return daylightUVIndex(
            peakIndex: peakIndex,
            localHour: mars.localMeanSolarTime,
            sunrise: mars.sunriseHour,
            sunset: mars.sunsetHour,
            exponent: 0.92
        )
    }

    private static func moonUVIndexEquivalent(_ moon: MoonEstimate) -> Double? {
        daylightUVIndex(
            peakIndex: 12.0,
            localHour: moon.localHour,
            sunrise: 6,
            sunset: 18,
            exponent: 0.9
        )
    }

    private static func marsPeakUVIndex(for category: String) -> Double? {
        switch category.lowercased().replacingOccurrences(of: "_", with: " ") {
        case "low":
            return 1.5
        case "moderate":
            return 4.0
        case "high":
            return 6.5
        case "very high":
            return 9.0
        case "extreme":
            return 11.0
        default:
            return nil
        }
    }

    private static func daylightUVIndex(
        peakIndex: Double?,
        localHour: Double,
        sunrise: Double,
        sunset: Double,
        exponent: Double
    ) -> Double? {
        guard let peakIndex else {
            return nil
        }

        let normalizedTime = positiveModulo(localHour, 24)
        guard normalizedTime >= sunrise && normalizedTime <= sunset else {
            return 0
        }

        let daylightLength = max(0.1, sunset - sunrise)
        let progress = (normalizedTime - sunrise) / daylightLength
        let sunFactor = pow(max(0, sin(.pi * progress)), exponent)
        return peakIndex * sunFactor
    }

    private static func hourMinuteString(_ hourValue: Double) -> String {
        let normalized = positiveModulo(hourValue, 24)
        let totalMinutes = Int((normalized * 60).rounded())
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}

struct MarsWeatherService {
    private static let galeLongitudeEast = 137.4417
    private let client = RemoteJSONClient(timeoutIntervalForRequest: 40, timeoutIntervalForResource: 60)

    func fetchCurrentConditions(at now: Date) async throws -> MarsConditions {
        weatherLogger.info("Fetching Mars weather from CAB REMS feed")
        let url = URL(string: "http://cab.inta-csic.es/rems/wp-content/plugins/marsweather-widget/api.php")!
        let payload = try await client.decode(MarsWidgetPayload.self, from: url)

        guard let latest = payload.soles.sorted(by: { ($0.solValue ?? 0) > ($1.solValue ?? 0) }).first,
              let sol = latest.solValue,
              let terrestrialDate = latest.terrestrialDateValue,
              let minTemp = latest.minTempValue,
              let maxTemp = latest.maxTempValue,
              let sunrise = latest.sunriseValue,
              let sunset = latest.sunsetValue else {
            throw WeatherServiceError.invalidPayload
        }

        let lmst = marsLocalMeanSolarTime(at: now, eastLongitudeDegrees: Self.galeLongitudeEast)
        let estimate = estimateTemperature(
            localTime: lmst,
            sunrise: sunrise,
            sunset: sunset,
            minTemp: minTemp,
            maxTemp: maxTemp
        )

        return MarsConditions(
            sol: sol,
            terrestrialDate: terrestrialDate,
            season: latest.season,
            sunriseHour: sunrise,
            sunsetHour: sunset,
            minTemperature: minTemp,
            maxTemperature: maxTemp,
            localMeanSolarTime: lmst,
            estimatedCurrentTemperature: estimate,
            uvIndexCategory: latest.localUVIrradianceIndex
        )
    }

    private func marsLocalMeanSolarTime(at date: Date, eastLongitudeDegrees: Double) -> Double {
        let utcJulianDate = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let terrestrialTimeJulianDate = utcJulianDate + 69.184 / 86_400
        let marsSolDate = (terrestrialTimeJulianDate - 2_405_522.002_877_9) / 1.027_491_251_7
        let coordinatedMarsTime = positiveModulo(marsSolDate * 24, 24)
        return positiveModulo(coordinatedMarsTime + eastLongitudeDegrees / 15, 24)
    }

    private func estimateTemperature(localTime: Double, sunrise: Double, sunset: Double, minTemp: Double, maxTemp: Double) -> Double {
        let daylightLength = max(0.1, sunset - sunrise)
        let normalizedTime = positiveModulo(localTime, 24)

        if normalizedTime >= sunrise && normalizedTime <= sunset {
            let progress = (normalizedTime - sunrise) / daylightLength
            let heatingCurve = pow(max(0, sin(.pi * progress)), 0.82)
            return minTemp + (maxTemp - minTemp) * heatingCurve
        }

        let nightLength = max(0.1, 24 - daylightLength)
        let nightProgress: Double

        if normalizedTime > sunset {
            nightProgress = (normalizedTime - sunset) / nightLength
        } else {
            nightProgress = (normalizedTime + 24 - sunset) / nightLength
        }

        let duskTemperature = minTemp + (maxTemp - minTemp) * 0.22
        let coolingCurve = pow(max(0, cos((.pi / 2) * min(max(nightProgress, 0), 1))), 1.4)
        return minTemp + (duskTemperature - minTemp) * coolingCurve
    }
}

struct EarthTemperatureService {
    private let openMeteoService = OpenMeteoEarthTemperatureService()

    func closestCityMatch(for referenceTemperature: Double) async throws -> EarthCityTemperature {
        weatherLogger.info("Finding Earth match using Open-Meteo sample for reference \(referenceTemperature, format: .fixed(precision: 1))C")
        return try await openMeteoService.closestCityMatch(for: referenceTemperature)
    }
}

private struct OpenMeteoEarthTemperatureService {
    private let client = RemoteJSONClient()

    func closestCityMatch(for referenceTemperature: Double) async throws -> EarthCityTemperature {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: Self.cities.map { Self.coordinateString($0.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: Self.cities.map { Self.coordinateString($0.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "current", value: "temperature_2m,uv_index"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
        ]

        guard let url = components.url else {
            throw WeatherServiceError.invalidURL
        }

        let data = try await client.data(from: url)
        let responses = try OpenMeteoForecastResponse.decodeMany(from: data)
        let paired = zip(Self.cities, responses).map { city, response in
            EarthCityTemperature(
                city: city.name,
                country: city.country,
                temperature: response.current.temperature2M,
                uvIndex: response.current.uvIndex,
                latitude: city.latitude,
                longitude: city.longitude,
                sourceNote: "Closest current city match from the app's sampled global city set via Open-Meteo.",
                comparisonCandidates: []
            )
        }

        let sorted = paired
            .map { candidate in
                EarthComparisonCandidate(
                    city: candidate.city,
                    country: candidate.country,
                    temperature: candidate.temperature,
                    uvIndex: candidate.uvIndex,
                    temperatureDeltaFromReference: abs(candidate.temperature - referenceTemperature),
                    isSelectedMatch: false
                )
            }
            .sorted {
                if $0.temperatureDeltaFromReference == $1.temperatureDeltaFromReference {
                    return $0.temperature < $1.temperature
                }
                return $0.temperatureDeltaFromReference < $1.temperatureDeltaFromReference
            }

        guard let selected = sorted.first else {
            throw WeatherServiceError.invalidPayload
        }

        let comparisonCandidates = sorted.map { candidate in
            EarthComparisonCandidate(
                city: candidate.city,
                country: candidate.country,
                temperature: candidate.temperature,
                uvIndex: candidate.uvIndex,
                temperatureDeltaFromReference: candidate.temperatureDeltaFromReference,
                isSelectedMatch: candidate.city == selected.city && candidate.country == selected.country
            )
        }

        let closest = EarthCityTemperature(
            city: selected.city,
            country: selected.country,
            temperature: selected.temperature,
            uvIndex: selected.uvIndex,
            latitude: paired.first(where: { $0.city == selected.city && $0.country == selected.country })?.latitude ?? 0,
            longitude: paired.first(where: { $0.city == selected.city && $0.country == selected.country })?.longitude ?? 0,
            sourceNote: "Closest current city match from the app's sampled global city set via Open-Meteo. The modal shows the full sampled comparison list.",
            comparisonCandidates: comparisonCandidates
        )

        weatherLogger.info("Open-Meteo Earth match selected \(closest.city), \(closest.country)")
        return closest
    }

    private static func coordinateString(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    static let cities: [EarthCity] = [
        .init(name: "Longyearbyen", country: "Svalbard", latitude: 78.2232, longitude: 15.6469),
        .init(name: "Tromso", country: "Norway", latitude: 69.6496, longitude: 18.9560),
        .init(name: "Nuuk", country: "Greenland", latitude: 64.1814, longitude: -51.6941),
        .init(name: "Murmansk", country: "Russia", latitude: 68.9585, longitude: 33.0827),
        .init(name: "Reykjavik", country: "Iceland", latitude: 64.1466, longitude: -21.9426),
        .init(name: "Iqaluit", country: "Canada", latitude: 63.7467, longitude: -68.5170),
        .init(name: "Yellowknife", country: "Canada", latitude: 62.4540, longitude: -114.3718),
        .init(name: "Yakutsk", country: "Russia", latitude: 62.0355, longitude: 129.6755),
        .init(name: "Whitehorse", country: "Canada", latitude: 60.7212, longitude: -135.0568),
        .init(name: "Fairbanks", country: "United States", latitude: 64.8378, longitude: -147.7164),
        .init(name: "Norilsk", country: "Russia", latitude: 69.3558, longitude: 88.1893),
        .init(name: "Kiruna", country: "Sweden", latitude: 67.8558, longitude: 20.2253),
        .init(name: "Rovaniemi", country: "Finland", latitude: 66.5039, longitude: 25.7294),
        .init(name: "Oulu", country: "Finland", latitude: 65.0121, longitude: 25.4651),
        .init(name: "Anchorage", country: "United States", latitude: 61.2181, longitude: -149.9003),
        .init(name: "Magadan", country: "Russia", latitude: 59.5682, longitude: 150.8085),
        .init(name: "Astana", country: "Kazakhstan", latitude: 51.1694, longitude: 71.4491),
        .init(name: "Ulaanbaatar", country: "Mongolia", latitude: 47.8864, longitude: 106.9057),
        .init(name: "Harbin", country: "China", latitude: 45.8038, longitude: 126.5350),
        .init(name: "Changchun", country: "China", latitude: 43.8171, longitude: 125.3235),
        .init(name: "Sapporo", country: "Japan", latitude: 43.0618, longitude: 141.3545),
        .init(name: "Winnipeg", country: "Canada", latitude: 49.8951, longitude: -97.1384),
        .init(name: "Saskatoon", country: "Canada", latitude: 52.1332, longitude: -106.6700),
        .init(name: "Regina", country: "Canada", latitude: 50.4452, longitude: -104.6189),
        .init(name: "Edmonton", country: "Canada", latitude: 53.5461, longitude: -113.4938),
        .init(name: "Calgary", country: "Canada", latitude: 51.0447, longitude: -114.0719),
        .init(name: "Novosibirsk", country: "Russia", latitude: 55.0084, longitude: 82.9357),
        .init(name: "Krasnoyarsk", country: "Russia", latitude: 56.0153, longitude: 92.8932),
        .init(name: "Omsk", country: "Russia", latitude: 54.9885, longitude: 73.3242),
        .init(name: "Oslo", country: "Norway", latitude: 59.9139, longitude: 10.7522),
        .init(name: "Berlin", country: "Germany", latitude: 52.5200, longitude: 13.4050),
        .init(name: "London", country: "United Kingdom", latitude: 51.5072, longitude: -0.1276),
        .init(name: "Warsaw", country: "Poland", latitude: 52.2297, longitude: 21.0122),
        .init(name: "Almaty", country: "Kazakhstan", latitude: 43.2389, longitude: 76.8897),
        .init(name: "Beijing", country: "China", latitude: 39.9042, longitude: 116.4074),
        .init(name: "Seoul", country: "South Korea", latitude: 37.5665, longitude: 126.9780),
        .init(name: "Tokyo", country: "Japan", latitude: 35.6762, longitude: 139.6503),
        .init(name: "San Francisco", country: "United States", latitude: 37.7749, longitude: -122.4194),
        .init(name: "New York", country: "United States", latitude: 40.7128, longitude: -74.0060),
        .init(name: "Athens", country: "Greece", latitude: 37.9838, longitude: 23.7275),
        .init(name: "Cairo", country: "Egypt", latitude: 30.0444, longitude: 31.2357),
        .init(name: "Dubai", country: "United Arab Emirates", latitude: 25.2048, longitude: 55.2708),
        .init(name: "Delhi", country: "India", latitude: 28.6139, longitude: 77.2090),
        .init(name: "Mexico City", country: "Mexico", latitude: 19.4326, longitude: -99.1332),
        .init(name: "Bangkok", country: "Thailand", latitude: 13.7563, longitude: 100.5018),
        .init(name: "Singapore", country: "Singapore", latitude: 1.3521, longitude: 103.8198),
        .init(name: "Jakarta", country: "Indonesia", latitude: -6.2088, longitude: 106.8456),
        .init(name: "Lima", country: "Peru", latitude: -12.0464, longitude: -77.0428),
        .init(name: "Sao Paulo", country: "Brazil", latitude: -23.5505, longitude: -46.6333),
        .init(name: "Buenos Aires", country: "Argentina", latitude: -34.6037, longitude: -58.3816),
        .init(name: "Santiago", country: "Chile", latitude: -33.4489, longitude: -70.6693),
        .init(name: "Cape Town", country: "South Africa", latitude: -33.9249, longitude: 18.4241),
        .init(name: "Johannesburg", country: "South Africa", latitude: -26.2041, longitude: 28.0473),
        .init(name: "Perth", country: "Australia", latitude: -31.9523, longitude: 115.8613),
        .init(name: "Adelaide", country: "Australia", latitude: -34.9285, longitude: 138.6007),
        .init(name: "Melbourne", country: "Australia", latitude: -37.8136, longitude: 144.9631),
        .init(name: "Sydney", country: "Australia", latitude: -33.8688, longitude: 151.2093),
        .init(name: "Hobart", country: "Australia", latitude: -42.8821, longitude: 147.3272),
        .init(name: "Christchurch", country: "New Zealand", latitude: -43.5321, longitude: 172.6362),
        .init(name: "McMurdo Station", country: "Antarctica", latitude: -77.8419, longitude: 166.6863),
    ]
}

struct MoonTemperatureEstimator {
    private let apollo11 = ApolloSite(name: "Tranquility Base", latitude: 0.6741, longitude: 23.4729)
    private let synodicMonth = 29.530588853
    private let referenceNewMoon = ISO8601DateFormatter().date(from: "2000-01-06T18:14:00Z")!
    private let minimumTemperature = -173.0
    private let maximumTemperature = 127.0
    private let peakTemperatureHour = 14.0

    func estimate(at date: Date) -> MoonEstimate {
        let ageDays = positiveModulo(date.timeIntervalSince(referenceNewMoon) / 86_400, synodicMonth)
        let phaseDegrees = (ageDays / synodicMonth) * 360
        let hourAngle = signedModulo(phaseDegrees + apollo11.longitude - 180, 360)
        let localHour = positiveModulo(12 + hourAngle / 15, 24)
        let temperature = estimatedSurfaceTemperature(localHour: localHour)

        return MoonEstimate(temperature: temperature, localHour: localHour)
    }

    private func estimatedSurfaceTemperature(localHour: Double) -> Double {
        let midpoint = (maximumTemperature + minimumTemperature) / 2
        let amplitude = (maximumTemperature - minimumTemperature) / 2
        let shiftedHour = positiveModulo(localHour - peakTemperatureHour, 24)
        let cyclePosition = shiftedHour / 24
        let thermalWave = cos(cyclePosition * 2 * .pi)

        // Ease the thermal curve slightly so the surface lingers near the extremes
        // without snapping to a perfectly flat lunar-night floor.
        let smoothedWave = thermalWave >= 0
            ? pow(thermalWave, 0.82)
            : -pow(abs(thermalWave), 0.92)

        return midpoint + amplitude * smoothedWave
    }
}

struct LocalWeatherService {
    #if canImport(CoreLocation)
    private let deviceLocationService = DeviceLocationLocalWeatherService()
    #endif
    private let networkFallbackService = NetworkFallbackLocalWeatherService()

    func fetchCurrentConditions() async throws -> LocalConditions {
        #if canImport(CoreLocation)
        do {
            weatherLogger.info("Attempting local weather from device location")
            return try await deviceLocationService.fetchCurrentConditions()
        } catch {
            weatherLogger.error("Device-location local weather failed, falling back to network: \(error.localizedDescription)")
            return try await networkFallbackService.fetchCurrentConditions(preferredLocation: nil, reason: error)
        }
        #else
        weatherLogger.info("Device location unavailable on this platform, using network fallback")
        return try await networkFallbackService.fetchCurrentConditions(preferredLocation: nil, reason: nil)
        #endif
    }
}

private struct NetworkFallbackLocalWeatherService {
    private let client = RemoteJSONClient()

    func fetchCurrentConditions(preferredLocation: CLLocation?, reason: Error?) async throws -> LocalConditions {
        if let preferredLocation {
            weatherLogger.info("Fetching local fallback weather for device coordinates \(preferredLocation.coordinate.latitude, format: .fixed(precision: 4)), \(preferredLocation.coordinate.longitude, format: .fixed(precision: 4))")
            let forecast = try await fetchTemperature(
                latitude: preferredLocation.coordinate.latitude,
                longitude: preferredLocation.coordinate.longitude
            )
            let label = await resolveLabel(for: preferredLocation)
            return LocalConditions(
                label: label,
                temperature: forecast.current.temperature2M,
                uvIndex: forecast.current.uvIndex,
                sourceNote: "Current device location via Apple Location Services, temperature via Open-Meteo fallback.",
                latitude: preferredLocation.coordinate.latitude,
                longitude: preferredLocation.coordinate.longitude
            )
        }

        weatherLogger.info("Resolving network-based fallback location")
        let resolved = try await resolveLocation()
        let forecast = try await fetchTemperature(latitude: resolved.latitude, longitude: resolved.longitude)
        return LocalConditions(
            label: resolved.label,
            temperature: forecast.current.temperature2M,
            uvIndex: forecast.current.uvIndex,
            sourceNote: sourceNote(reason: reason),
            latitude: resolved.latitude,
            longitude: resolved.longitude
        )
    }

    private func resolveLocation() async throws -> ResolvedLocation {
        if let ipapi = try? await client.decode(IPAPILocationResponse.self, from: URL(string: "https://ipapi.co/json/")!),
           let latitude = ipapi.latitude,
           let longitude = ipapi.longitude {
            weatherLogger.info("Resolved fallback location via ipapi: \(latitude, format: .fixed(precision: 4)), \(longitude, format: .fixed(precision: 4))")
            return ResolvedLocation(
                label: locationLabel(city: ipapi.city, region: ipapi.region, country: ipapi.countryName),
                latitude: latitude,
                longitude: longitude,
                sourceNote: "Approximate network location."
            )
        }

        let ipwho = try await client.decode(IPWhoLocationResponse.self, from: URL(string: "https://ipwho.is/")!)
        guard ipwho.success, let latitude = ipwho.latitude, let longitude = ipwho.longitude else {
            throw WeatherServiceError.invalidPayload
        }

        weatherLogger.info("Resolved fallback location via ipwho: \(latitude, format: .fixed(precision: 4)), \(longitude, format: .fixed(precision: 4))")
        return ResolvedLocation(
            label: locationLabel(city: ipwho.city, region: ipwho.region, country: ipwho.country),
            latitude: latitude,
            longitude: longitude,
            sourceNote: "Approximate network location."
        )
    }

    private func fetchTemperature(latitude: Double, longitude: Double) async throws -> OpenMeteoForecastResponse {
        weatherLogger.info("Fetching Open-Meteo current temperature for \(latitude, format: .fixed(precision: 4)), \(longitude, format: .fixed(precision: 4))")
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,uv_index"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
        ]

        guard let url = components.url else {
            throw WeatherServiceError.invalidURL
        }

        return try await client.decode(OpenMeteoForecastResponse.self, from: url)
    }

    private func locationLabel(city: String?, region: String?, country: String?) -> String {
        let parts: [String] = [city, region, country]
            .compactMap { (value: String?) -> String? in
                guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                    return nil
                }
                return trimmed
            }

        return parts.isEmpty ? "Current network location" : parts.joined(separator: ", ")
    }

    private func resolveLabel(for location: CLLocation) async -> String {
        let geocoder = CLGeocoder()
        if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
            let parts = [placemark.locality, placemark.administrativeArea, placemark.country]
                .compactMap { value -> String? in
                    guard let value, !value.isEmpty else {
                        return nil
                    }
                    return value
                }

            if !parts.isEmpty {
                return parts.joined(separator: ", ")
            }
        }

        return String(
            format: "Lat %.2f, Lon %.2f",
            location.coordinate.latitude,
            location.coordinate.longitude
        )
    }

    private func sourceNote(reason: Error?) -> String {
        if reason == nil {
            return "Approximate network location and weather fallback."
        }
        return "Approximate network location and weather fallback because Apple location or WeatherKit was unavailable."
    }
}

#if canImport(CoreLocation)
private struct DeviceLocationLocalWeatherService {
    private let fallbackService = NetworkFallbackLocalWeatherService()
    #if canImport(WeatherKit)
    private let weatherService = WeatherService.shared
    #endif

    func fetchCurrentConditions() async throws -> LocalConditions {
        let location: CLLocation
        do {
            location = try await withTimeout(seconds: 12) {
                try await requestCurrentDeviceLocation()
            }
        } catch {
            weatherLogger.error("Device location lookup failed before weather lookup: \(error.localizedDescription)")
            throw error
        }
        weatherLogger.info("Resolved device location \(location.coordinate.latitude, format: .fixed(precision: 4)), \(location.coordinate.longitude, format: .fixed(precision: 4))")
        #if canImport(WeatherKit)
        do {
            let current = try await withTimeout(seconds: 4) {
                try await weatherService.weather(for: location, including: .current)
            }
            let label = await resolveLabel(for: location)
            weatherLogger.info("WeatherKit local weather succeeded for \(label)")

            return LocalConditions(
                label: label,
                temperature: current.temperature.converted(to: .celsius).value,
                uvIndex: Double(current.uvIndex.value),
                sourceNote: "Current device location via Apple Location Services, with current weather and UV from Apple Weather.",
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        } catch {
            weatherLogger.error("WeatherKit local weather failed, falling back to Open-Meteo: \(error.localizedDescription)")
            return try await fallbackService.fetchCurrentConditions(preferredLocation: location, reason: error)
        }
        #else
        return try await fallbackService.fetchCurrentConditions(preferredLocation: location, reason: nil)
        #endif
    }

    private func resolveLabel(for location: CLLocation) async -> String {
        let geocoder = CLGeocoder()
        if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
            let parts = [placemark.locality, placemark.administrativeArea, placemark.country]
                .compactMap { value -> String? in
                    guard let value, !value.isEmpty else {
                        return nil
                    }
                    return value
                }

            if !parts.isEmpty {
                return parts.joined(separator: ", ")
            }
        }

        return String(
            format: "Lat %.2f, Lon %.2f",
            location.coordinate.latitude,
            location.coordinate.longitude
        )
    }
}

@MainActor
private func requestCurrentDeviceLocation() async throws -> CLLocation {
    let provider = DeviceLocationProvider()
    return try await provider.requestCurrentLocation()
}

private final class DeviceLocationProvider: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestCurrentLocation() async throws -> CLLocation {
        try await ensureAuthorization()

        if let location = locationManager.location {
            weatherLogger.info("Using cached device location after authorization")
            return location
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            weatherLogger.info("Requesting one-shot device location update")
            locationManager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        weatherLogger.info("Location authorization changed to \(Self.authorizationStatusDescription(manager.authorizationStatus))")
        guard let continuation = authorizationContinuation else {
            return
        }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            authorizationContinuation = nil
            weatherLogger.info("Location authorization granted")
            continuation.resume()
        case .denied, .restricted:
            authorizationContinuation = nil
            weatherLogger.error("Location authorization denied or restricted")
            continuation.resume(throwing: WeatherServiceError.locationUnavailable)
        case .notDetermined:
            break
        @unknown default:
            authorizationContinuation = nil
            continuation.resume(throwing: WeatherServiceError.locationUnavailable)
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        locationManagerDidChangeAuthorization(manager)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation = locationContinuation else {
            return
        }

        locationContinuation = nil

        if let location = locations.last {
            weatherLogger.info("Received device location update")
            continuation.resume(returning: location)
        } else {
            weatherLogger.error("Location update returned no coordinates")
            continuation.resume(throwing: WeatherServiceError.locationUnavailable)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation = locationContinuation else {
            return
        }

        locationContinuation = nil
        weatherLogger.error("Location manager failed: \(error.localizedDescription)")
        continuation.resume(throwing: error)
    }

    private func ensureAuthorization() async throws {
        weatherLogger.info("Current location authorization status is \(Self.authorizationStatusDescription(self.locationManager.authorizationStatus))")
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return
        case .denied, .restricted:
            weatherLogger.error("Location unavailable because authorization is denied or restricted")
            throw WeatherServiceError.locationUnavailable
        case .notDetermined:
            try await withCheckedThrowingContinuation { continuation in
                authorizationContinuation = continuation
                weatherLogger.info("Requesting when-in-use location authorization")
                locationManager.requestWhenInUseAuthorization()
            }
        @unknown default:
            throw WeatherServiceError.locationUnavailable
        }
    }

    private static func authorizationStatusDescription(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorizedAlways:
            return "authorizedAlways"
        case .authorizedWhenInUse:
            return "authorizedWhenInUse"
        @unknown default:
            return "unknown"
        }
    }
}
#endif

struct RemoteJSONClient {
    private let session: URLSession

    init(timeoutIntervalForRequest: TimeInterval = 20, timeoutIntervalForResource: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutIntervalForRequest
        configuration.timeoutIntervalForResource = timeoutIntervalForResource
        session = URLSession(configuration: configuration)
    }

    func decode<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let data = try await data(from: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return try decoder.decode(T.self, from: data)
    }

    func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw WeatherServiceError.httpFailure
        }

        return data
    }
}

enum WeatherServiceError: LocalizedError {
    case invalidURL
    case invalidPayload
    case httpFailure
    case locationUnavailable
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "A source URL could not be built."
        case .invalidPayload:
            return "The source returned data in an unexpected format."
        case .httpFailure:
            return "The source returned a failed HTTP response."
        case .locationUnavailable:
            return "The current device location could not be resolved."
        case .timeout:
            return "The weather request timed out."
        }
    }
}

struct MoonEstimate {
    let temperature: Double
    let localHour: Double
}

private struct MarsWidgetPayload: Decodable {
    let soles: [MarsSolPayload]
}

private struct MarsSolPayload: Decodable {
    let terrestrialDate: String
    let sol: String
    let season: String
    let minTemp: String
    let maxTemp: String
    let localUVIrradianceIndex: String
    let sunrise: String
    let sunset: String

    enum CodingKeys: String, CodingKey {
        case terrestrialDate = "terrestrial_date"
        case sol
        case season
        case minTemp = "min_temp"
        case maxTemp = "max_temp"
        case localUVIrradianceIndex = "local_uv_irradiance_index"
        case sunrise
        case sunset
    }

    var terrestrialDateValue: Date? {
        Date.utcDayFormatter.date(from: terrestrialDate)
    }

    var solValue: Int? {
        Int(sol)
    }

    var minTempValue: Double? {
        Double(minTemp)
    }

    var maxTempValue: Double? {
        Double(maxTemp)
    }

    var sunriseValue: Double? {
        Self.parseTime(sunrise)
    }

    var sunsetValue: Double? {
        Self.parseTime(sunset)
    }

    private static func parseTime(_ value: String) -> Double? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]) else {
            return nil
        }
        return hours + minutes / 60
    }
}

private struct OpenMeteoForecastResponse: Decodable {
    let current: Current

    struct Current: Decodable {
        let temperature2M: Double
        let uvIndex: Double?

        enum CodingKeys: String, CodingKey {
            case temperature2M = "temperature_2m"
            case uvIndex = "uv_index"
        }
    }

    static func decodeMany(from data: Data) throws -> [OpenMeteoForecastResponse] {
        let decoder = JSONDecoder()
        if let array = try? decoder.decode([OpenMeteoForecastResponse].self, from: data) {
            return array
        }
        return [try decoder.decode(OpenMeteoForecastResponse.self, from: data)]
    }
}

private struct IPAPILocationResponse: Decodable {
    let city: String?
    let region: String?
    let countryName: String?
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case city
        case region
        case countryName = "country_name"
        case latitude
        case longitude
    }
}

private struct IPWhoLocationResponse: Decodable {
    let success: Bool
    let city: String?
    let region: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?
}

private struct EarthCity {
    let name: String
    let country: String
    let latitude: Double
    let longitude: Double
}

private struct ResolvedLocation {
    let label: String
    let latitude: Double
    let longitude: Double
    let sourceNote: String
}

private struct ApolloSite {
    let name: String
    let latitude: Double
    let longitude: Double
}

private func positiveModulo(_ value: Double, _ modulus: Double) -> Double {
    let remainder = value.truncatingRemainder(dividingBy: modulus)
    return remainder >= 0 ? remainder : remainder + modulus
}

private func signedModulo(_ value: Double, _ modulus: Double) -> Double {
    let centered = positiveModulo(value + modulus / 2, modulus) - modulus / 2
    return centered == -modulus / 2 ? modulus / 2 : centered
}

private func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            let duration = UInt64(seconds * 1_000_000_000)
            try await Task.sleep(nanoseconds: duration)
            throw WeatherServiceError.timeout
        }

        guard let first = try await group.next() else {
            throw WeatherServiceError.timeout
        }
        group.cancelAll()
        return first
    }
}

private extension Date {
    static let utcDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
