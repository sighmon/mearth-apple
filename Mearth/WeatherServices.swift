import Foundation

struct DashboardComposer {
    private let marsService = MarsWeatherService()
    private let earthService = EarthTemperatureService()
    private let moonService = MoonTemperatureEstimator()
    private let localService = LocalWeatherService()

    func makeSnapshot(now: Date) async -> DashboardSnapshot {
        var cards: [TemperatureCard] = []
        var warnings: [String] = []

        let marsResult: Result<MarsConditions, Error>
        do {
            marsResult = .success(try await marsService.fetchCurrentConditions(at: now))
        } catch {
            marsResult = .failure(error)
            warnings.append("Curiosity weather could not be refreshed.")
        }

        switch marsResult {
        case .success(let mars):
            cards.append(
                TemperatureCard(
                    kind: .mars,
                    title: "Mars",
                    subtitle: "Curiosity at Gale Crater",
                    value: Self.temperatureString(mars.estimatedCurrentTemperature),
                    detail: "LMST \(Self.hourMinuteString(mars.localMeanSolarTime)) · latest REMS sol \(mars.sol)",
                    footnote: "Estimated from the latest official REMS range (\(Self.dateString(mars.terrestrialDate)) UTC, \(mars.season))."
                )
            )

            do {
                let earthMatch = try await earthService.closestCityMatch(for: mars.estimatedCurrentTemperature)
                let delta = abs(earthMatch.temperature - mars.estimatedCurrentTemperature)
                cards.append(
                    TemperatureCard(
                        kind: .earth,
                        title: "Earth Match",
                        subtitle: "\(earthMatch.city), \(earthMatch.country)",
                        value: Self.temperatureString(earthMatch.temperature),
                        detail: "\(Self.temperatureDeltaString(delta)) from Mars right now",
                        footnote: "Closest current city match from a broad global Open-Meteo sample."
                    )
                )
            } catch {
                warnings.append("Earth comparison cities are unavailable.")
                cards.append(
                    TemperatureCard(
                        kind: .earth,
                        title: "Earth Match",
                        subtitle: "Global city sample unavailable",
                        value: "--",
                        detail: "Open-Meteo did not return a usable comparison set.",
                        footnote: "Mars is still shown from Curiosity's official feed."
                    )
                )
            }

        case .failure:
            cards.append(
                TemperatureCard(
                    kind: .mars,
                    title: "Mars",
                    subtitle: "Curiosity feed unavailable",
                    value: "--",
                    detail: "The official REMS endpoint did not return a usable payload.",
                    footnote: "This card uses CAB's Curiosity weather widget feed when it is reachable."
                )
            )
            cards.append(
                TemperatureCard(
                    kind: .earth,
                    title: "Earth Match",
                    subtitle: "Waiting on the Mars reference temperature",
                    value: "--",
                    detail: "A comparison city needs the Curiosity reading first.",
                    footnote: "Refresh again when the Mars feed is back."
                )
            )
        }

        let moonEstimate = moonService.estimate(at: now)
        cards.append(
            TemperatureCard(
                kind: .moon,
                title: "Moon Estimate",
                subtitle: "Apollo 11 · Tranquility Base",
                value: Self.temperatureString(moonEstimate.temperature),
                detail: "Lunar local time \(Self.hourMinuteString(moonEstimate.localHour))",
                footnote: "Modeled from lunar phase and solar angle at the landing site, not a live sensor feed."
            )
        )

        do {
            let local = try await localService.fetchCurrentConditions()
            cards.append(
                TemperatureCard(
                    kind: .local,
                    title: "Local",
                    subtitle: local.label,
                    value: Self.temperatureString(local.temperature),
                    detail: "Current temperature near you",
                    footnote: local.sourceNote
                )
            )
        } catch {
            warnings.append("Local weather could not be resolved.")
            cards.append(
                TemperatureCard(
                    kind: .local,
                    title: "Local",
                    subtitle: "Current location unavailable",
                    value: "--",
                    detail: "IP geolocation or local forecast lookup failed.",
                    footnote: "This card falls back to network location so it also works on Apple TV."
                )
            )
        }

        return DashboardSnapshot(
            generatedAt: now,
            cards: cards,
            warning: warnings.isEmpty ? nil : warnings.joined(separator: " ")
        )
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
    private let client = RemoteJSONClient()

    func fetchCurrentConditions(at now: Date) async throws -> MarsConditions {
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
            estimatedCurrentTemperature: estimate
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
    private let client = RemoteJSONClient()

    func closestCityMatch(for referenceTemperature: Double) async throws -> EarthCityTemperature {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: Self.cities.map { Self.coordinateString($0.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: Self.cities.map { Self.coordinateString($0.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "current", value: "temperature_2m"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
        ]

        guard let url = components.url else {
            throw WeatherServiceError.invalidURL
        }

        let data = try await client.data(from: url)
        let responses = try OpenMeteoForecastResponse.decodeMany(from: data)
        let paired = zip(Self.cities, responses).map { city, response in
            EarthCityTemperature(city: city.name, country: city.country, temperature: response.current.temperature2M)
        }

        guard let closest = paired.min(by: {
            abs($0.temperature - referenceTemperature) < abs($1.temperature - referenceTemperature)
        }) else {
            throw WeatherServiceError.invalidPayload
        }

        return closest
    }

    private static func coordinateString(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private static let cities: [EarthCity] = [
        .init(name: "Longyearbyen", country: "Svalbard", latitude: 78.2232, longitude: 15.6469),
        .init(name: "Nuuk", country: "Greenland", latitude: 64.1814, longitude: -51.6941),
        .init(name: "Yellowknife", country: "Canada", latitude: 62.4540, longitude: -114.3718),
        .init(name: "Reykjavik", country: "Iceland", latitude: 64.1466, longitude: -21.9426),
        .init(name: "Yakutsk", country: "Russia", latitude: 62.0355, longitude: 129.6755),
        .init(name: "Ulaanbaatar", country: "Mongolia", latitude: 47.8864, longitude: 106.9057),
        .init(name: "Anchorage", country: "United States", latitude: 61.2181, longitude: -149.9003),
        .init(name: "Oslo", country: "Norway", latitude: 59.9139, longitude: 10.7522),
        .init(name: "Edmonton", country: "Canada", latitude: 53.5461, longitude: -113.4938),
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

    func estimate(at date: Date) -> MoonEstimate {
        let ageDays = positiveModulo(date.timeIntervalSince(referenceNewMoon) / 86_400, synodicMonth)
        let phaseDegrees = (ageDays / synodicMonth) * 360
        let hourAngle = signedModulo(phaseDegrees + apollo11.longitude - 180, 360)
        let solarCosine = cos(hourAngle * .pi / 180)
        let warmedCosine = max(0, solarCosine)
        let temperature = -173 + pow(warmedCosine, 0.35) * 300
        let localHour = positiveModulo(12 + hourAngle / 15, 24)

        return MoonEstimate(temperature: temperature, localHour: localHour)
    }
}

struct LocalWeatherService {
    private let client = RemoteJSONClient()

    func fetchCurrentConditions() async throws -> LocalConditions {
        let resolved = try await resolveLocation()
        let forecast = try await fetchTemperature(latitude: resolved.latitude, longitude: resolved.longitude)
        return LocalConditions(
            label: resolved.label,
            temperature: forecast.current.temperature2M,
            sourceNote: resolved.sourceNote
        )
    }

    private func resolveLocation() async throws -> ResolvedLocation {
        if let ipapi = try? await client.decode(IPAPILocationResponse.self, from: URL(string: "https://ipapi.co/json/")!),
           let latitude = ipapi.latitude,
           let longitude = ipapi.longitude {
            return ResolvedLocation(
                label: locationLabel(city: ipapi.city, region: ipapi.region, country: ipapi.countryName),
                latitude: latitude,
                longitude: longitude,
                sourceNote: "Approximate network location from ipapi.co, then current Open-Meteo conditions."
            )
        }

        let ipwho = try await client.decode(IPWhoLocationResponse.self, from: URL(string: "https://ipwho.is/")!)
        guard ipwho.success, let latitude = ipwho.latitude, let longitude = ipwho.longitude else {
            throw WeatherServiceError.invalidPayload
        }

        return ResolvedLocation(
            label: locationLabel(city: ipwho.city, region: ipwho.region, country: ipwho.country),
            latitude: latitude,
            longitude: longitude,
            sourceNote: "Approximate network location from ipwho.is, then current Open-Meteo conditions."
        )
    }

    private func fetchTemperature(latitude: Double, longitude: Double) async throws -> OpenMeteoForecastResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m"),
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
}

struct RemoteJSONClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
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

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "A source URL could not be built."
        case .invalidPayload:
            return "The source returned data in an unexpected format."
        case .httpFailure:
            return "The source returned a failed HTTP response."
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
    let sunrise: String
    let sunset: String

    enum CodingKeys: String, CodingKey {
        case terrestrialDate = "terrestrial_date"
        case sol
        case season
        case minTemp = "min_temp"
        case maxTemp = "max_temp"
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

        enum CodingKeys: String, CodingKey {
            case temperature2M = "temperature_2m"
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
