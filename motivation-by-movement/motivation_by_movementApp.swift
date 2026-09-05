//
//  motivation_by_movementApp.swift
//  motivation-by-movement
//
//  Created by berlank1 on 8/29/26.
//

import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        if launchOptions?[.location] != nil {
            NSLog("📍 App relaunched by iOS for location event")
            _ = MotivationGeofenceManager.shared
        }
        return true
    }
}

@main
struct motivation_by_movementApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
