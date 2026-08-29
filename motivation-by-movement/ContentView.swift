//
//  ContentView.swift
//  motivation-by-movement
//
//  Created by berlank1 on 8/29/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        Color.clear
            .onAppear {
                MotivationGeofenceManager.shared.start()
            }
    }
}

#Preview {
    ContentView()
}
