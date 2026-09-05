//
//  MotivationGeofenceManager.swift
//  motivation-by-movement
//
//  Created by berlank1 on 8/29/26.
//

import Foundation
import Combine
import CoreLocation

struct MotivationLocation: Codable {
    let name: String
    let latitude: Double
    let longitude: Double
}

struct MotivationActivity: Identifiable {
    let id = UUID()
    let name: String
    let movementType: String
    let time: Date
}

final class MotivationGeofenceManager: NSObject, ObservableObject {

    static let shared = MotivationGeofenceManager()

    // Published state for the UI.
    @Published private(set) var launchTime = Date()
    @Published private(set) var fencedLocations: [MotivationLocation] = []
    @Published private(set) var recentActivities: [MotivationActivity] = []

    private let locationManager = CLLocationManager()
    private let locationsURL = URL(
        string: "https://hero.net/motivation/motivation-locations.json"
    )!

    private var monitoredLocations: [MotivationLocation] = []
    
    // 125m comfortably covers a house or business while keeping nearby
    // locations (e.g. 7-Eleven and Dwight and Dana, ~274m apart) disjoint.
    private let geofenceRadius: CLLocationDistance = 125
    
    private override init() {
        super.init()
        
        NSLog("MotivationGeofenceManager initialized")
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        
        checkAuthorization()
    }
    
    // MARK: - Authorization

    private func checkAuthorization() {
        let status = locationManager.authorizationStatus

        NSLog("Authorization status: %@", String(describing: status))

        switch status {
        case .notDetermined:
            NSLog("Requesting Always authorization")
            locationManager.requestAlwaysAuthorization()

        case .authorizedWhenInUse:
            NSLog("Only When In Use authorization")
            NSLog("User must grant Always in Settings")

        case .authorizedAlways:
            NSLog("Always authorization granted")
            start()

        case .denied:
            NSLog("Location permission denied")

        case .restricted:
            NSLog("Location permission restricted")

        @unknown default:
            NSLog("Unknown authorization status")
        }
    }
    
    func start() {
        NSLog("MotivationGeofenceManager started")
        
        guard locationManager.authorizationStatus == .authorizedAlways else {
            NSLog("Cannot start geofencing: Always authorization is not available")
            return
        }
        
        locationManager.startMonitoringSignificantLocationChanges()
        fetchLocations()
    }
    
    // MARK: - Fetch Locations
    
    private func fetchLocations() {
        NSLog("Fetching motivation locations from server...")
        
        var request = URLRequest(url: locationsURL)
        
        // Useful while debugging. This prevents URLSession from simply
        // returning its local cached response.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        NSLog("Request URL: %@", request.url!.absoluteString)
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            
            if let error = error {
                NSLog("Location fetch failed: %@", error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                NSLog("HTTP status: %d", httpResponse.statusCode)
                NSLog("Response headers: %@", "\(httpResponse.allHeaderFields)")
                NSLog(
                    "Response URL: %@",
                    httpResponse.url?.absoluteString ?? "nil"
                )
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    NSLog("Server returned HTTP status %d", httpResponse.statusCode)
                    return
                }
            }
            
            guard let data = data else {
                NSLog("Server returned no data")
                return
            }
            
            NSLog("Received %d bytes", data.count)
            
            do {
                let locations = try JSONDecoder().decode(
                    [MotivationLocation].self,
                    from: data
                )
                
                NSLog("Fetched %d motivation locations", locations.count)
                
                for location in locations {
                    NSLog(
                        "%@: %.6f, %.6f",
                        location.name,
                        location.latitude,
                        location.longitude
                    )
                }
                
                DispatchQueue.main.async {
                    self?.setupGeofences(locations)
                }
                
            } catch {
                NSLog(
                    "Failed to decode motivation locations: %@",
                    "\(error)"
                )
            }
        }
        
        task.resume()
    }
    
    // MARK: - Geofencing
    
    private func setupGeofences(_ locations: [MotivationLocation]) {
        monitoredLocations = locations
        fencedLocations = locations

        let newIdentifiers = Set(
            locations.map { $0.name }
        )
        
        // Remove regions that are no longer in the server's JSON.
        for region in locationManager.monitoredRegions {
            if !newIdentifiers.contains(region.identifier) {
                NSLog(
                    "Removing old geofence: %@",
                    region.identifier
                )
                
                locationManager.stopMonitoring(for: region)
            }
        }
        
        // Index existing monitored regions by identifier so we can replace
        // any whose geometry no longer matches what we intend to monitor.
        let existingByID = Dictionary(
            locationManager.monitoredRegions.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for location in locations {
            let center = CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            )

            let region = CLCircularRegion(
                center: center,
                radius: geofenceRadius,
                identifier: location.name
            )

            region.notifyOnEntry = true
            region.notifyOnExit = true

            // If a region with this identifier is already monitored but its
            // radius/center differs from what we now want (e.g. a stale
            // region left over from a previous run), it must be removed and
            // re-registered. Otherwise iOS keeps monitoring the old geometry
            // while requestState below queries our new object — the two
            // diverge and exit callbacks never match our expectations.
            if let existing = existingByID[location.name] as? CLCircularRegion {
                let sameGeometry =
                    existing.radius == region.radius &&
                    existing.center.latitude == region.center.latitude &&
                    existing.center.longitude == region.center.longitude

                if sameGeometry {
                    NSLog("Already monitoring (matching geometry): %@", location.name)
                    locationManager.requestState(for: existing)
                    continue
                }

                NSLog(
                    "Replacing stale geofence: %@ (old radius %.0fm -> %.0fm)",
                    location.name,
                    existing.radius,
                    region.radius
                )
                locationManager.stopMonitoring(for: existing)
            }

            NSLog(
                "Registering geofence: %@ (lat: %.6f, lon: %.6f, radius: %.0fm)",
                location.name,
                location.latitude,
                location.longitude,
                geofenceRadius
            )

            locationManager.startMonitoring(for: region)
            locationManager.requestState(for: region)
        }
        
        NSLog(
            "iOS currently reports %d monitored regions",
            locationManager.monitoredRegions.count
        )
        
        for region in locationManager.monitoredRegions {
            NSLog(
                "Currently monitored: %@",
                region.identifier
            )
        }
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(for region: CLRegion, activity: String) {
        guard let location = monitoredLocations.first(
            where: { $0.name == region.identifier }
        ) else {
            NSLog(
                "Received event for unknown region: %@",
                region.identifier
            )
            return
        }

        NSLog(
            "Handling geofence event: %@ (%@)",
            location.name,
            activity
        )

        let record = MotivationActivity(
            name: location.name,
            movementType: activity,
            time: Date()
        )
        DispatchQueue.main.async {
            self.recentActivities.insert(record, at: 0)
            if self.recentActivities.count > 50 {
                self.recentActivities.removeLast(
                    self.recentActivities.count - 50
                )
            }
        }

        // The backend validates against a strict JSON schema: it requires
        // exactly these keys and rejects any that are missing or extra.
        // created_at is Unix epoch seconds (UTC) sent as a string,
        // movement_type must be "enter" or "exit".
        let event: [String: Any] = [
            "event_id": UUID().uuidString,
            "created_at": String(Int(Date().timeIntervalSince1970)),
            "name": location.name,
            "movement_type": activity
        ]
        
        guard
            let url = URL(
                string: "https://hero.net/motivation/cgi/event.sh"
            ),
            let jsonData = try? JSONSerialization.data(
                withJSONObject: event
            )
        else {
            NSLog("Failed to create event request")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = jsonData
        
        NSLog(
            "Sending event for %@",
            location.name
        )
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            
            if let error = error {
                NSLog(
                    "Event POST failed: %@",
                    error.localizedDescription
                )
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                NSLog(
                    "Event POST HTTP status: %d",
                    httpResponse.statusCode
                )
            }
            
            NSLog(
                "Event POST completed for %@",
                location.name
            )
        }
        
        task.resume()
    }
}

// MARK: - CLLocationManagerDelegate

extension MotivationGeofenceManager: CLLocationManagerDelegate {
    
    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        NSLog(
            "Authorization changed: %@",
            String(describing: status)
        )
        
        if status == .authorizedAlways {
            start()
        }
    }
    
    func locationManager(
        _ manager: CLLocationManager,
        didStartMonitoringFor region: CLRegion
    ) {
        NSLog(
            "iOS accepted monitoring for: %@",
            region.identifier
        )
        
        manager.requestState(for: region)
    }
    
    func locationManager(
        _ manager: CLLocationManager,
        didDetermineState state: CLRegionState,
        for region: CLRegion
    ) {
        NSLog(
            "Region state — %@: %@",
            region.identifier,
            String(describing: state)
        )
    }
    
    func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        NSLog(
            "ENTERED REGION: %@",
            region.identifier
        )
        
        handleEvent(for: region, activity: "enter")
    }

    func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        NSLog(
            "EXITED REGION: %@",
            region.identifier
        )

        handleEvent(for: region, activity: "exit")
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        NSLog(
            "Region monitoring failed — %@: %@",
            region?.identifier ?? "unknown",
            error.localizedDescription
        )
    }
    
    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        NSLog(
            "CLLocationManager failed: %@",
            error.localizedDescription
        )
    }
    
    func locationManager(
        _ manager: CLLocationManager,
        didFinishDeferredUpdatesWithError error: Error?
    ) {
        if let error = error {
            NSLog(
                "Deferred location updates failed: %@",
                error.localizedDescription
            )
        }
    }
}
