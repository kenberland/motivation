//
//  MotivationGeofenceManager.swift
//  motivation-by-movement
//
//  Created by berlank1 on 8/29/26.
//

import Foundation
import CoreLocation

struct MotivationLocation: Codable {
    let name: String
    let latitude: Double
    let longitude: Double
}

final class MotivationGeofenceManager: NSObject {
    
    static let shared = MotivationGeofenceManager()
    
    private let locationManager = CLLocationManager()
    private let locationsURL = URL(
        string: "https://hero.net/motivation/motivation-locations.json"
    )!
    
    private var monitoredLocations: [MotivationLocation] = []
    
    // Use a larger radius while testing.
    // Once everything works, you can reduce this to 100 meters.
    private let geofenceRadius: CLLocationDistance = 300
    
    private override init() {
        super.init()
        
        NSLog("📍 MotivationGeofenceManager initialized")
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        
        checkAuthorization()
    }
    
    // MARK: - Authorization

    private func checkAuthorization() {
        let status = locationManager.authorizationStatus

        NSLog("🔐 Authorization status: %@", String(describing: status))

        switch status {
        case .notDetermined:
            NSLog("🔐 Requesting Always authorization")
            locationManager.requestAlwaysAuthorization()

        case .authorizedWhenInUse:
            NSLog("⚠️ Only When In Use authorization")
            NSLog("⚠️ User must grant Always in Settings")

        case .authorizedAlways:
            NSLog("✅ Always authorization granted")
            start()

        case .denied:
            NSLog("❌ Location permission denied")

        case .restricted:
            NSLog("❌ Location permission restricted")

        @unknown default:
            NSLog("❓ Unknown authorization status")
        }
    }
    
    func start() {
        NSLog("🚀 MotivationGeofenceManager started")
        
        guard locationManager.authorizationStatus == .authorizedAlways else {
            NSLog("⚠️ Cannot start geofencing: Always authorization is not available")
            return
        }
        
        fetchLocations()
    }
    
    // MARK: - Fetch Locations
    
    private func fetchLocations() {
        NSLog("🌐 Fetching motivation locations from server...")
        
        var request = URLRequest(url: locationsURL)
        
        // Useful while debugging. This prevents URLSession from simply
        // returning its local cached response.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        NSLog("🌐 Request URL: %@", request.url!.absoluteString)
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            
            if let error = error {
                NSLog("❌ Location fetch failed: %@", error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                NSLog("✅ HTTP status: %d", httpResponse.statusCode)
                NSLog("🌐 Response headers: %@", "\(httpResponse.allHeaderFields)")
                NSLog(
                    "🌐 Response URL: %@",
                    httpResponse.url?.absoluteString ?? "nil"
                )
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    NSLog("❌ Server returned HTTP status %d", httpResponse.statusCode)
                    return
                }
            }
            
            guard let data = data else {
                NSLog("❌ Server returned no data")
                return
            }
            
            NSLog("🌐 Received %d bytes", data.count)
            
            do {
                let locations = try JSONDecoder().decode(
                    [MotivationLocation].self,
                    from: data
                )
                
                NSLog("✅ Fetched %d motivation locations", locations.count)
                
                for location in locations {
                    NSLog(
                        "📍 %@: %.6f, %.6f",
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
                    "❌ Failed to decode motivation locations: %@",
                    "\(error)"
                )
            }
        }
        
        task.resume()
    }
    
    // MARK: - Geofencing
    
    private func setupGeofences(_ locations: [MotivationLocation]) {
        monitoredLocations = locations
        
        let newIdentifiers = Set(
            locations.map { $0.name }
        )
        
        // Remove regions that are no longer in the server's JSON.
        for region in locationManager.monitoredRegions {
            if !newIdentifiers.contains(region.identifier) {
                NSLog(
                    "🗑️ Removing old geofence: %@",
                    region.identifier
                )
                
                locationManager.stopMonitoring(for: region)
            }
        }
        
        // Don't register duplicates.
        let currentlyMonitored = Set(
            locationManager.monitoredRegions.map { $0.identifier }
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
            region.notifyOnExit = false
            
            if currentlyMonitored.contains(location.name) {
                NSLog(
                    "ℹ️ Already monitoring: %@",
                    location.name
                )
            } else {
                NSLog(
                    "📍 Registering geofence: %@ " +
                    "(lat: %.6f, lon: %.6f, radius: %.0fm)",
                    location.name,
                    location.latitude,
                    location.longitude,
                    geofenceRadius
                )
                
                locationManager.startMonitoring(for: region)
            }
            
            // Ask iOS whether we are currently inside or outside.
            locationManager.requestState(for: region)
        }
        
        NSLog(
            "📍 iOS currently reports %d monitored regions",
            locationManager.monitoredRegions.count
        )
        
        for region in locationManager.monitoredRegions {
            NSLog(
                "📍 Currently monitored: %@",
                region.identifier
            )
        }
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(for region: CLRegion) {
        guard let location = monitoredLocations.first(
            where: { $0.name == region.identifier }
        ) else {
            NSLog(
                "⚠️ Received event for unknown region: %@",
                region.identifier
            )
            return
        }
        
        NSLog(
            "🚨 Handling geofence event: %@",
            location.name
        )
        
        let event: [String: Any] = [
            "name": location.name,
            "time": ISO8601DateFormatter().string(from: Date())
        ]
        
        guard
            let url = URL(
                string: "https://hero.net/motivation/cgi/event.sh"
            ),
            let jsonData = try? JSONSerialization.data(
                withJSONObject: event
            )
        else {
            NSLog("❌ Failed to create event request")
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
            "🌐 Sending event for %@",
            location.name
        )
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            
            if let error = error {
                NSLog(
                    "❌ Event POST failed: %@",
                    error.localizedDescription
                )
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                NSLog(
                    "✅ Event POST HTTP status: %d",
                    httpResponse.statusCode
                )
            }
            
            NSLog(
                "✅ Event POST completed for %@",
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
            "🔐 Authorization changed: %@",
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
            "✅ iOS accepted monitoring for: %@",
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
            "🔎 Region state — %@: %@",
            region.identifier,
            String(describing: state)
        )
    }
    
    func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        NSLog(
            "🚨🚨🚨 ENTERED REGION: %@",
            region.identifier
        )
        
        handleEvent(for: region)
    }
    
    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        NSLog(
            "❌ Region monitoring failed — %@: %@",
            region?.identifier ?? "unknown",
            error.localizedDescription
        )
    }
    
    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        NSLog(
            "❌ CLLocationManager failed: %@",
            error.localizedDescription
        )
    }
    
    func locationManager(
        _ manager: CLLocationManager,
        didFinishDeferredUpdatesWithError error: Error?
    ) {
        if let error = error {
            NSLog(
                "⚠️ Deferred location updates failed: %@",
                error.localizedDescription
            )
        }
    }
}
