//
//  LocationTool.swift
//  FoundationLab
//
//  Created by Rudrank Riyam on 6/17/25.
//

@preconcurrency import CoreLocation
import Foundation
import FoundationModels
@preconcurrency import MapKit

/// `LocationTool` provides location services and geocoding functionality.
///
/// This tool can get current location, geocode addresses, and calculate distances.
/// Important: This requires location services entitlement and user permission.
public struct LocationTool: Tool {

  /// The name of the tool, used for identification.
  public let name = "accessLocation"
  /// A brief description of the tool's functionality.
  public let description =
    "Get current location, geocode addresses, search places, and calculate distances"

  /// Arguments for location operations.
  @Generable
  public struct Arguments {
    /// The action to perform: "current", "geocode", "reverse", "search", "distance"
    @Guide(
      description: "The action to perform: 'current', 'geocode', 'reverse', 'search', 'distance'")
    public var action: String

    /// Address to geocode (for geocode action)
    @Guide(description: "Address to geocode (for geocode action)")
    public var address: String?

    /// Latitude for reverse geocoding or distance calculation
    @Guide(description: "Latitude for reverse geocoding or distance calculation")
    public var latitude: Double?

    /// Longitude for reverse geocoding or distance calculation
    @Guide(description: "Longitude for reverse geocoding or distance calculation")
    public var longitude: Double?

    /// Second latitude for distance calculation
    @Guide(description: "Second latitude for distance calculation")
    public var latitude2: Double?

    /// Second longitude for distance calculation
    @Guide(description: "Second longitude for distance calculation")
    public var longitude2: Double?

    /// Search query for places (for search action)
    @Guide(description: "Search query for places (for search action)")
    public var searchQuery: String?

    /// Search radius in meters (defaults to 1000)
    @Guide(description: "Search radius in meters (defaults to 1000)")
    public var radius: Double?

    public init(
      action: String = "",
      address: String? = nil,
      latitude: Double? = nil,
      longitude: Double? = nil,
      latitude2: Double? = nil,
      longitude2: Double? = nil,
      searchQuery: String? = nil,
      radius: Double? = nil
    ) {
      self.action = action
      self.address = address
      self.latitude = latitude
      self.longitude = longitude
      self.latitude2 = latitude2
      self.longitude2 = longitude2
      self.searchQuery = searchQuery
      self.radius = radius
    }
  }

  private let locationManager = CLLocationManager()

  public init() {
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    locationManager.distanceFilter = kCLDistanceFilterNone
  }

  public func call(arguments: Arguments) async throws -> some PromptRepresentable {
    switch arguments.action.lowercased() {
    case "current":
      return await getCurrentLocation()
    case "geocode":
      return await geocodeAddress(address: arguments.address)
    case "reverse":
      return await reverseGeocode(latitude: arguments.latitude, longitude: arguments.longitude)
    case "search":
      return await searchPlaces(query: arguments.searchQuery, radius: arguments.radius)
    case "distance":
      return calculateDistance(arguments: arguments)
    default:
      return createErrorOutput(error: LocationError.invalidAction)
    }
  }

  private func getCurrentLocation() async -> GeneratedContent {
    let authorization = await checkLocationAuthorization()

    if !authorization.isAuthorized {
      if authorization.status == .notDetermined {
        return await requestLocationPermission()
      }

      if let message = authorization.result {
        return message
      }

      return createErrorOutput(error: LocationError.authorizationDenied)
    }

    do {
      let location = try await requestLiveLocation()
      return await buildCurrentLocationContent(from: location, source: .live)
    } catch {
      if let cached = await cachedLocation() {
        return await buildCurrentLocationContent(from: cached, source: .cached)
      }

      if let locationError = error as? LocationError {
        return createErrorOutput(error: locationError)
      }

      return createErrorOutput(error: error)
    }
  }

  @MainActor
  private func cachedLocation() -> CLLocation? {
    locationManager.location
  }

  @MainActor
  private func requestLiveLocation(timeout: TimeInterval = 8) async throws -> CLLocation {
    try await CurrentLocationFetcher().requestLocation(using: locationManager, timeout: timeout)
  }

  private func buildCurrentLocationContent(
    from location: CLLocation,
    source: LocationResultSource
  ) async -> GeneratedContent {
    let mapItem = await reverseGeocode(location: location)
    let details = addressDetails(from: mapItem, fallbackLocation: location)

    return GeneratedContent(properties: [
      "status": "success",
      "source": source.identifier,
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "altitude": location.altitude,
      "accuracy": location.horizontalAccuracy,
      "timestamp": formatDate(location.timestamp),
      "address": details.displayName,
      "message": source.message(for: details.displayName),
      "street": details.street ?? "",
      "city": details.city ?? "",
      "region": details.region ?? "",
      "postalCode": details.postalCode ?? "",
      "country": details.country ?? "",
      "isoCountryCode": details.isoCountryCode ?? "",
      "note": source.note ?? "",
    ])
  }

  private func reverseGeocode(location: CLLocation) async -> MKMapItem? {
    guard let request = MKReverseGeocodingRequest(location: location) else {
      return nil
    }

    return try? await request.mapItems.first
  }

  private func geocodeAddress(address: String?) async -> GeneratedContent {
    guard let address = address, !address.isEmpty else {
      return createErrorOutput(error: LocationError.missingAddress)
    }

    do {
      guard let request = MKGeocodingRequest(addressString: address) else {
        return createErrorOutput(error: LocationError.geocodingFailed)
      }

      let mapItems = try await request.mapItems
      guard let mapItem = mapItems.first else {
        return createErrorOutput(error: LocationError.geocodingFailed)
      }

      let details = addressDetails(from: mapItem, fallbackLocation: mapItem.location)
      let location = mapItem.location

      return GeneratedContent(properties: [
        "status": "success",
        "query": address,
        "latitude": location.coordinate.latitude,
        "longitude": location.coordinate.longitude,
        "formattedAddress": details.displayName,
        "country": details.country ?? "",
        "state": details.region ?? "",
        "city": details.city ?? "",
        "street": details.street ?? "",
        "postalCode": details.postalCode ?? "",
        "isoCountryCode": details.isoCountryCode ?? "",
        "message": "Location found: \(details.displayName)",
      ])
    } catch {
      return createErrorOutput(error: error)
    }
  }

  private func reverseGeocode(latitude: Double?, longitude: Double?) async -> GeneratedContent {
    guard let latitude = latitude,
      let longitude = longitude
    else {
      return createErrorOutput(error: LocationError.missingCoordinates)
    }

    let location = CLLocation(latitude: latitude, longitude: longitude)

    do {
      guard let request = MKReverseGeocodingRequest(location: location) else {
        return createErrorOutput(error: LocationError.reverseGeocodingFailed)
      }
      let mapItems = try await request.mapItems

      guard let mapItem = mapItems.first else {
        return createErrorOutput(error: LocationError.reverseGeocodingFailed)
      }

      let details = addressDetails(from: mapItem, fallbackLocation: location)
      let address = details.displayName

      return GeneratedContent(properties: [
        "status": "success",
        "latitude": latitude,
        "longitude": longitude,
        "address": address,
        "country": details.country ?? "",
        "state": details.region ?? "",
        "city": details.city ?? "",
        "street": details.street ?? "",
        "postalCode": details.postalCode ?? "",
        "isoCountryCode": details.isoCountryCode ?? "",
        "message": "Address: \(address)",
      ])
    } catch {
      return createErrorOutput(error: error)
    }
  }

  private func searchPlaces(query: String?, radius: Double?) async -> GeneratedContent {
    guard let query = query, !query.isEmpty else {
      return createErrorOutput(error: LocationError.missingSearchQuery)
    }

    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query

    // Set search region if we have current location
    if let location = locationManager.location {
      let searchRadius = radius ?? 1000  // Default 1km
      request.region = MKCoordinateRegion(
        center: location.coordinate,
        latitudinalMeters: searchRadius * 2,
        longitudinalMeters: searchRadius * 2
      )
    }

    let search = MKLocalSearch(request: request)

    do {
      let response = try await search.start()

      var placesDescription = ""

      for (index, item) in response.mapItems.prefix(10).enumerated() {
        let distance: String
        if let userLocation = locationManager.location {
          let placeLocation = CLLocation(
            latitude: item.location.coordinate.latitude,
            longitude: item.location.coordinate.longitude
          )
          let meters = userLocation.distance(from: placeLocation)
          distance = formatDistance(meters)
        } else {
          distance = "Unknown distance"
        }

        placesDescription += "\(index + 1). \(item.name ?? "Unknown Place")\n"
        if let address = formatMapItemAddress(item) {
          placesDescription += "   Address: \(address)\n"
        }
        placesDescription += "   Distance: \(distance)\n"
        if let phone = item.phoneNumber {
          placesDescription += "   Phone: \(phone)\n"
        }
        placesDescription += "\n"
      }

      if placesDescription.isEmpty {
        placesDescription = "No places found matching '\(query)'"
      }

      return GeneratedContent(properties: [
        "status": "success",
        "query": query,
        "resultCount": response.mapItems.count,
        "places": placesDescription.trimmingCharacters(in: .whitespacesAndNewlines),
        "message": "Found \(response.mapItems.count) place(s)",
      ])
    } catch {
      return createErrorOutput(error: error)
    }
  }

  private func calculateDistance(arguments: Arguments) -> GeneratedContent {
    guard let lat1 = arguments.latitude,
      let lon1 = arguments.longitude,
      let lat2 = arguments.latitude2,
      let lon2 = arguments.longitude2
    else {
      return createErrorOutput(error: LocationError.missingCoordinates)
    }

    let location1 = CLLocation(latitude: lat1, longitude: lon1)
    let location2 = CLLocation(latitude: lat2, longitude: lon2)

    let distance = location1.distance(from: location2)

    // Calculate bearing
    let bearing = calculateBearing(from: location1, to: location2)
    let direction = compassDirection(from: bearing)

    return GeneratedContent(properties: [
      "status": "success",
      "location1_latitude": lat1,
      "location1_longitude": lon1,
      "location2_latitude": lat2,
      "location2_longitude": lon2,
      "distanceMeters": distance,
      "distanceKilometers": distance / 1000,
      "distanceMiles": distance / 1609.344,
      "formattedDistance": formatDistance(distance),
      "bearing": bearing,
      "direction": direction,
      "message": "Distance: \(formatDistance(distance)) \(direction)",
    ])
  }

  private func formatAddress(mapItem: MKMapItem?) -> String {
    addressDetails(from: mapItem, fallbackLocation: mapItem?.location).displayName
  }

  private func formatDistance(_ meters: Double) -> String {
    if meters < 1000 {
      return String(format: "%.0f meters", meters)
    } else if meters < 10000 {
      return String(format: "%.1f km", meters / 1000)
    } else {
      return String(format: "%.0f km", meters / 1000)
    }
  }

  private func calculateBearing(from: CLLocation, to: CLLocation) -> Double {
    let lat1 = from.coordinate.latitude.degreesToRadians
    let lon1 = from.coordinate.longitude.degreesToRadians
    let lat2 = to.coordinate.latitude.degreesToRadians
    let lon2 = to.coordinate.longitude.degreesToRadians

    let dLon = lon2 - lon1

    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)

    let radiansBearing = atan2(y, x)
    let degreesBearing = radiansBearing.radiansToDegrees

    return (degreesBearing + 360).truncatingRemainder(dividingBy: 360)
  }

  private func compassDirection(from bearing: Double) -> String {
    let directions = [
      "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
    ]
    let index = Int((bearing + 11.25) / 22.5) % 16
    return directions[index]
  }

  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter.string(from: date)
  }

  private func requestLocationPermission() async -> GeneratedContent {
    // Create a location delegate to handle authorization changes
    let delegate = LocationDelegate()
    locationManager.delegate = delegate

    // Request permission
    #if os(macOS)
      // On macOS, just start monitoring which will trigger permission dialog
      locationManager.startUpdatingLocation()
      locationManager.stopUpdatingLocation()
    #else
      locationManager.requestWhenInUseAuthorization()
    #endif

    // Return informative message
    return GeneratedContent(properties: [
      "status": "permission_requested",
      "message":
        "Location permission requested. Please allow location access in the system alert and try again.",
      "instruction":
        "After granting permission, please run this tool again to get your location.",
    ])
  }

  private func createErrorOutput(error: Error) -> GeneratedContent {
    return GeneratedContent(properties: [
      "status": "error",
      "error": error.localizedDescription,
      "message": "Failed to perform location operation",
    ])
  }
  
  /// Checks if location authorization is sufficient for the current platform
  @MainActor
  private func checkLocationAuthorization() -> AuthorizationResult {
    let status = locationManager.authorizationStatus

    guard CLLocationManager.locationServicesEnabled() else {
      return AuthorizationResult(
        status: status,
        isAuthorized: false,
        result: createErrorOutput(error: LocationError.locationServicesDisabled)
      )
    }

    #if os(iOS) || os(visionOS)
      if status == .authorizedAlways || status == .authorizedWhenInUse {
        return AuthorizationResult(status: status, isAuthorized: true, result: nil)
      }
    #elseif os(macOS)
      if status == .authorizedAlways {
        return AuthorizationResult(status: status, isAuthorized: true, result: nil)
      }
    #else
      if status == .authorizedAlways || status == .authorizedWhenInUse {
        return AuthorizationResult(status: status, isAuthorized: true, result: nil)
      }
    #endif

    if status == .notDetermined {
      return AuthorizationResult(status: status, isAuthorized: false, result: nil)
    }

    return AuthorizationResult(
      status: status,
      isAuthorized: false,
      result: createErrorOutput(error: LocationError.authorizationDenied)
    )
  }
}

private struct AuthorizationResult {
  let status: CLAuthorizationStatus
  let isAuthorized: Bool
  let result: GeneratedContent?
}

private enum LocationResultSource {
  case live
  case cached

  func message(for address: String) -> String {
    switch self {
    case .live:
      return "Current location: \(address)"
    case .cached:
      return "Last known location: \(address)"
    }
  }

  var note: String? {
    switch self {
    case .live:
      return nil
    case .cached:
      return "Using last known location while waiting for a precise update."
    }
  }

  var identifier: String {
    switch self {
    case .live:
      return "live"
    case .cached:
      return "cached"
    }
  }
}

private struct AddressDetails {
  let displayName: String
  let street: String?
  let city: String?
  let region: String?
  let postalCode: String?
  let country: String?
  let isoCountryCode: String?
}

@MainActor
final class CurrentLocationFetcher: NSObject, @MainActor CLLocationManagerDelegate {
  private var continuation: CheckedContinuation<CLLocation, Error>?
  private var timeoutTask: Task<Void, Never>?

  @MainActor
  func requestLocation(
    using manager: CLLocationManager,
    timeout: TimeInterval = 8
  ) async throws -> CLLocation {
    if continuation != nil {
      throw LocationError.operationInProgress
    }

    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      manager.delegate = self

      #if os(macOS)
        manager.startUpdatingLocation()
      #else
        manager.requestLocation()
      #endif

      timeoutTask = Task { [weak self, weak manager] in
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        guard let manager else { return }
        await MainActor.run {
          guard let self else { return }
          self.handleTimeout(manager: manager)
        }
      }
    }
  }

  @MainActor
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    if let continuation = cleanup(manager: manager) {
      continuation.resume(returning: location)
    }
  }

  @MainActor
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    if let continuation = cleanup(manager: manager) {
      continuation.resume(throwing: error)
    }
  }

  @MainActor
  private func handleTimeout(manager: CLLocationManager) {
    guard let continuation = cleanup(manager: manager) else { return }
    continuation.resume(throwing: LocationError.locationTimeout)
  }

  @MainActor
  private func cleanup(manager: CLLocationManager)
    -> CheckedContinuation<CLLocation, Error>? {
    timeoutTask?.cancel()
    timeoutTask = nil
    #if os(macOS)
      manager.stopUpdatingLocation()
    #endif
    manager.delegate = nil
    let continuation = self.continuation
    self.continuation = nil
    return continuation
  }
}

private func addressDetails(
  from mapItem: MKMapItem?,
  fallbackLocation: CLLocation?
) -> AddressDetails {
  guard let placemark = mapItem?.placemark else {
    if let location = fallbackLocation {
      return AddressDetails(
        displayName: coordinateDescription(for: location),
        street: nil,
        city: nil,
        region: nil,
        postalCode: nil,
        country: nil,
        isoCountryCode: nil
      )
    }

    return AddressDetails(
      displayName: "Unknown location",
      street: nil,
      city: nil,
      region: nil,
      postalCode: nil,
      country: nil,
      isoCountryCode: nil
    )
  }

  let streetComponents = [placemark.subThoroughfare, placemark.thoroughfare]
    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
  let street =
    streetComponents.isEmpty ? nil : streetComponents.joined(separator: " ").trimmingCharacters(in: .whitespaces)

  let city = placemark.locality?.trimmingCharacters(in: .whitespacesAndNewlines)
  let region = (placemark.administrativeArea ?? placemark.subAdministrativeArea)?
    .trimmingCharacters(in: .whitespacesAndNewlines)
  let postalCode = placemark.postalCode?.trimmingCharacters(in: .whitespacesAndNewlines)
  let country = placemark.country?.trimmingCharacters(in: .whitespacesAndNewlines)
  let isoCountryCode = placemark.isoCountryCode?.trimmingCharacters(in: .whitespacesAndNewlines)

  var components: [String] = []
  if let street { components.append(street) }
  if let city, !city.isEmpty { components.append(city) }
  if let region, !region.isEmpty { components.append(region) }
  if let country, !country.isEmpty { components.append(country) }

  var displayName = components.joined(separator: ", ")
  if displayName.isEmpty {
    if let name = mapItem?.name, !name.isEmpty {
      displayName = name
    } else if let location = fallbackLocation {
      displayName = coordinateDescription(for: location)
    } else {
      displayName = "Unknown location"
    }
  }

  return AddressDetails(
    displayName: displayName,
    street: street,
    city: city,
    region: region,
    postalCode: postalCode,
    country: country,
    isoCountryCode: isoCountryCode
  )
}

private func coordinateDescription(for location: CLLocation) -> String {
  String(
    format: "%.4f, %.4f",
    location.coordinate.latitude,
    location.coordinate.longitude
  )
}

// Helper function to format map item address
private func formatMapItemAddress(_ mapItem: MKMapItem) -> String? {
  addressDetails(from: mapItem, fallbackLocation: mapItem.location).displayName
}

extension Double {
  var degreesToRadians: Double { self * .pi / 180 }
  var radiansToDegrees: Double { self * 180 / .pi }
}

enum LocationError: Error, LocalizedError {
  case invalidAction
  case authorizationDenied
  case authorizationNotDetermined
  case locationServicesDisabled
  case locationUnavailable
  case locationTimeout
  case operationInProgress
  case missingAddress
  case missingCoordinates
  case missingSearchQuery
  case geocodingFailed
  case reverseGeocodingFailed

  var errorDescription: String? {
    switch self {
    case .invalidAction:
      return "Invalid action. Use 'current', 'geocode', 'reverse', 'search', or 'distance'."
    case .authorizationDenied:
      return "Location access denied. Please grant permission in Settings."
    case .authorizationNotDetermined:
      return "Location permission not yet determined. Please grant permission when prompted."
    case .locationServicesDisabled:
      return "Location services are disabled. Enable Location Services to continue."
    case .locationUnavailable:
      return "Current location is unavailable."
    case .locationTimeout:
      return "Timed out while waiting for an updated location."
    case .operationInProgress:
      return "A location request is already in progress."
    case .missingAddress:
      return "Address is required for geocoding."
    case .missingCoordinates:
      return "Latitude and longitude are required."
    case .missingSearchQuery:
      return "Search query is required."
    case .geocodingFailed:
      return "Failed to find location for the given address."
    case .reverseGeocodingFailed:
      return "Failed to find address for the given coordinates."
    }
  }
}

// Location delegate to handle authorization changes
class LocationDelegate: NSObject, CLLocationManagerDelegate {
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    // This will be called when authorization status changes
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    // Required delegate method for requestLocation()
    // We don't need to do anything here as we're just requesting permission
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // Handle location errors
    print("Location error: \(error.localizedDescription)")
  }
}
