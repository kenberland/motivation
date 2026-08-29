import Foundation
import CoreLocation

struct MotivationLocation: Codable {
    let name: String
    let latitude: Double
    let longitude: Double
}

class MotivationGeofenceManager: NSObject {
    static let shared = MotivationGeofenceManager()
    private let locationManager = CLLocationManager()
    private let locationsURL = URL(string: "https://hero.net/motivation/motivation-locations.json")!
    private var monitoredLocations: [MotivationLocation] = []

    private override init() {
        super.init()
        NSLog("MotivationGeofenceManager initialized")
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
    }

    func start() {
        NSLog("MotivationGeofenceManager started")
        fetchLocations()
    }

    private func fetchLocations() {
        NSLog("Fetching motivation locations from server...")
        let task = URLSession.shared.dataTask(with: locationsURL) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                NSLog("Failed to fetch locations: %@", error?.localizedDescription ?? "unknown error")
                return
            }
            do {
                let locations = try JSONDecoder().decode([MotivationLocation].self, from: data)
                NSLog("Fetched locations: \(locations)")
                DispatchQueue.main.async {
                    self?.setupGeofences(locations)
                }
            } catch {
                print("Failed to decode locations: \(error)")
            }
        }
        task.resume()
    }

    private func setupGeofences(_ locations: [MotivationLocation]) {
        monitoredLocations = locations
        for location in locations {
            let center = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            let region = CLCircularRegion(center: center, radius: 100, identifier: location.name)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            locationManager.startMonitoring(for: region)
            NSLog("Geofencing enabled for: %@ (lat: %f, lon: %f)", location.name, location.latitude, location.longitude)
        }
    }

    private func handleEvent(for region: CLRegion) {
        guard let location = monitoredLocations.first(where: { $0.name == region.identifier }) else { return }
        let event: [String: Any] = [
            "name": location.name,
            "time": ISO8601DateFormatter().string(from: Date())
        ]
        guard let url = URL(string: "https://hero.net/motivation/cgi/event.sh"),
              let jsonData = try? JSONSerialization.data(withJSONObject: event) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Event POST failed: \(error)")
            }
        }
        task.resume()
    }
}

extension MotivationGeofenceManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedAlways {
            start()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {}

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        handleEvent(for: region)
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("Monitoring failed: \(error)")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed: \(error)")
    }
}
