//
//  ContentView.swift
//  motivation-by-movement
//
//  Created by berlank1 on 8/29/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var manager = MotivationGeofenceManager.shared

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        NavigationView {
            List {
                Section("Status") {
                    LabeledContent("Launched",
                                   value: Self.timeFormatter.string(from: manager.launchTime))
                }

                Section("Fenced Locations") {
                    if manager.fencedLocations.isEmpty {
                        Text("No locations yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(manager.fencedLocations, id: \.name) { loc in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.name)
                                Text(String(format: "%.5f, %.5f",
                                            loc.latitude, loc.longitude))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Recent Activity") {
                    if manager.recentActivities.isEmpty {
                        Text("No activity yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(manager.recentActivities) { act in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(act.name)
                                    Text(Self.timeFormatter.string(from: act.time))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(act.movementType)
                                    .font(.caption.bold())
                                    .foregroundStyle(act.movementType == "enter" ? .green : .orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Motivation")
        }
        .onAppear {
            MotivationGeofenceManager.shared.start()
        }
    }
}

#Preview {
    ContentView()
}
