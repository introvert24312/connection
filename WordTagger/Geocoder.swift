import Foundation
import CoreLocation
import Combine

public final class GeocoderService: NSObject, ObservableObject {
    @Published public private(set) var isGeocoding = false
    @Published public private(set) var recentLocations: [GeocodedLocation] = []
    
    private let geocoder = CLGeocoder()
    private let cache = NSCache<NSString, GeocodedLocation>()
    private let maxCacheSize = 100
    private let maxRecentLocations = 50
    
    public static let shared = GeocoderService()
    
    override init() {
        super.init()
        setupCache()
    }
    
    private func setupCache() {
        cache.countLimit = maxCacheSize
        cache.name = "GeocoderCache"
    }
    
    // MARK: - Forward Geocoding (Address -> Coordinates)
    
    public func geocode(address: String) async throws -> GeocodedLocation {
        let cacheKey = NSString(string: address.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
        
        // Check cache first
        if let cachedLocation = cache.object(forKey: cacheKey) {
            return cachedLocation
        }
        
        // Perform geocoding
        await MainActor.run {
            isGeocoding = true
        }
        
        defer {
            Task { @MainActor in
                isGeocoding = false
            }
        }
        
        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            
            guard let placemark = placemarks.first,
                  let coordinate = placemark.location?.coordinate else {
                throw GeocodingError.noResultsFound
            }
            
            let location = GeocodedLocation(
                address: address,
                coordinate: coordinate,
                placemark: placemark,
                timestamp: Date()
            )
            
            // Cache the result
            cache.setObject(location, forKey: cacheKey)
            
            // Add to recent locations
            await MainActor.run {
                addToRecentLocations(location)
            }
            
            return location
            
        } catch {
            if let geocodingError = error as? CLError {
                throw GeocodingError.from(clError: geocodingError)
            } else {
                throw GeocodingError.unknown(error)
            }
        }
    }
    
    // MARK: - Reverse Geocoding (Coordinates -> Address)
    
    public func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> GeocodedLocation {
        let cacheKey = NSString(string: "\(coordinate.latitude),\(coordinate.longitude)")
        
        // Check cache first
        if let cachedLocation = cache.object(forKey: cacheKey) {
            return cachedLocation
        }
        
        await MainActor.run {
            isGeocoding = true
        }
        
        defer {
            Task { @MainActor in
                isGeocoding = false
            }
        }
        
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            guard let placemark = placemarks.first else {
                throw GeocodingError.noResultsFound
            }
            
            let address = formatAddress(from: placemark)
            let geocodedLocation = GeocodedLocation(
                address: address,
                coordinate: coordinate,
                placemark: placemark,
                timestamp: Date()
            )
            
            // Cache the result
            cache.setObject(geocodedLocation, forKey: cacheKey)
            
            // Add to recent locations
            await MainActor.run {
                addToRecentLocations(geocodedLocation)
            }
            
            return geocodedLocation
            
        } catch {
            if let geocodingError = error as? CLError {
                throw GeocodingError.from(clError: geocodingError)
            } else {
                throw GeocodingError.unknown(error)
            }
        }
    }
    
    // MARK: - Batch Geocoding
    
    public func batchGeocode(addresses: [String]) async -> [String: Result<GeocodedLocation, GeocodingError>] {
        var results: [String: Result<GeocodedLocation, GeocodingError>] = [:]
        
        await MainActor.run {
            isGeocoding = true
        }
        
        defer {
            Task { @MainActor in
                isGeocoding = false
            }
        }
        
        // Process addresses with a small delay to avoid rate limiting
        for address in addresses {
            do {
                let location = try await geocode(address: address)
                results[address] = .success(location)
                
                // Small delay to be respectful to the geocoding service
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                
            } catch let error as GeocodingError {
                results[address] = .failure(error)
            } catch {
                results[address] = .failure(.unknown(error))
            }
        }
        
        return results
    }
    
    // MARK: - Location Suggestions
    
    public func searchLocations(query: String) async throws -> [LocationSuggestion] {
        guard !query.isEmpty else { return [] }
        
        // For now, we'll use simple geocoding
        // In a production app, you might use MKLocalSearch for better results
        do {
            let location = try await geocode(address: query)
            return [LocationSuggestion(
                title: location.address,
                subtitle: location.formattedAddress,
                coordinate: location.coordinate
            )]
        } catch {
            // If geocoding fails, return empty array
            return []
        }
    }
    
    // MARK: - Cache Management
    
    public func clearCache() {
        cache.removeAllObjects()
    }
    
    public func cacheSize() -> Int {
        return cache.countLimit
    }
    
    // MARK: - Recent Locations Management
    
    @MainActor
    private func addToRecentLocations(_ location: GeocodedLocation) {
        // Remove if already exists
        recentLocations.removeAll { $0.address == location.address }
        
        // Add to beginning
        recentLocations.insert(location, at: 0)
        
        // Limit size
        if recentLocations.count > maxRecentLocations {
            recentLocations = Array(recentLocations.prefix(maxRecentLocations))
        }
    }
    
    public func clearRecentLocations() {
        recentLocations.removeAll()
    }
    
    // MARK: - Helper Methods
    
    private func formatAddress(from placemark: CLPlacemark) -> String {
        var components: [String] = []
        
        if let name = placemark.name {
            components.append(name)
        }
        
        if let locality = placemark.locality {
            components.append(locality)
        }
        
        if let country = placemark.country {
            components.append(country)
        }
        
        return components.joined(separator: ", ")
    }
}

// MARK: - Data Models

public final class GeocodedLocation: NSObject, Codable {
    public let address: String
    public let coordinate: CLLocationCoordinate2D
    public let timestamp: Date
    
    // Additional placemark information
    public let country: String?
    public let locality: String?
    public let administrativeArea: String?
    public let postalCode: String?
    
    public init(address: String, coordinate: CLLocationCoordinate2D, placemark: CLPlacemark, timestamp: Date) {
        self.address = address
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.country = placemark.country
        self.locality = placemark.locality
        self.administrativeArea = placemark.administrativeArea
        self.postalCode = placemark.postalCode
        super.init()
    }
    
    public var formattedAddress: String {
        var components: [String] = []
        
        if let locality = locality {
            components.append(locality)
        }
        
        if let administrativeArea = administrativeArea {
            components.append(administrativeArea)
        }
        
        if let country = country {
            components.append(country)
        }
        
        return components.joined(separator: ", ")
    }
    
    // Custom Codable implementation for CLLocationCoordinate2D
    private enum CodingKeys: String, CodingKey {
        case address, timestamp, country, locality, administrativeArea, postalCode
        case latitude, longitude
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(address, forKey: .address)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(country, forKey: .country)
        try container.encodeIfPresent(locality, forKey: .locality)
        try container.encodeIfPresent(administrativeArea, forKey: .administrativeArea)
        try container.encodeIfPresent(postalCode, forKey: .postalCode)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(String.self, forKey: .address)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        locality = try container.decodeIfPresent(String.self, forKey: .locality)
        administrativeArea = try container.decodeIfPresent(String.self, forKey: .administrativeArea)
        postalCode = try container.decodeIfPresent(String.self, forKey: .postalCode)
        
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        super.init()
    }
}

public struct LocationSuggestion {
    public let title: String
    public let subtitle: String
    public let coordinate: CLLocationCoordinate2D
    
    public init(title: String, subtitle: String, coordinate: CLLocationCoordinate2D) {
        self.title = title
        self.subtitle = subtitle
        self.coordinate = coordinate
    }
}

// MARK: - Error Types

public enum GeocodingError: LocalizedError {
    case noResultsFound
    case networkError
    case rateLimitExceeded
    case invalidAddress
    case locationServicesDisabled
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .noResultsFound:
            return "No location found for the given address"
        case .networkError:
            return "Network error occurred during geocoding"
        case .rateLimitExceeded:
            return "Geocoding rate limit exceeded. Please try again later"
        case .invalidAddress:
            return "The provided address is invalid"
        case .locationServicesDisabled:
            return "Location services are disabled"
        case .unknown(let error):
            return "Unknown geocoding error: \(error.localizedDescription)"
        }
    }
    
    static func from(clError: CLError) -> GeocodingError {
        switch clError.code {
        case .network:
            return .networkError
        case .geocodeFoundNoResult, .geocodeFoundPartialResult:
            return .noResultsFound
        case .geocodeCanceled:
            return .rateLimitExceeded
        case .locationUnknown:
            return .invalidAddress
        case .denied:
            return .locationServicesDisabled
        default:
            return .unknown(clError)
        }
    }
}

// MARK: - NSObject Override for GeocodedLocation

extension GeocodedLocation {
    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? GeocodedLocation else { return false }
        return address == other.address &&
               coordinate.latitude == other.coordinate.latitude &&
               coordinate.longitude == other.coordinate.longitude
    }
    
    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(address)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        return hasher.finalize()
    }
}