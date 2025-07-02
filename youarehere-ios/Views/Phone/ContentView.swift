//
//  ContentView.swift
//  youarehere-ios
//
//  Created by Gregory Lucas-Smith on 26/6/2024.
//

import SwiftUI
import CoreLocation

class IdentifiableError: Identifiable {
    let id = UUID()
    let error: Error
    init(_ error: Error) { self.error = error }
}

class LocationManagerDelegateWrapper: NSObject, ObservableObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    @Published var lastLocation: CLLocation?
    @Published var error: IdentifiableError?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("didUpdateLocations called with: \(locations)")
        lastLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("didFailWithError: \(error)")
        self.error = IdentifiableError(error)
    }
}

struct ContentView: View {
    @StateObject private var locationManagerDelegate = LocationManagerDelegateWrapper()
    
    var body: some View {
        VStack {
            Spacer()
            Button(action: {
                locationManagerDelegate.locationManager.requestWhenInUseAuthorization()
                locationManagerDelegate.locationManager.requestLocation()
            }) {
                Text("Get Location")
                    .font(.largeTitle)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(20)
                    .padding()
            }
            .accessibility(identifier: "getLocationButton")
            
            if let loc = locationManagerDelegate.lastLocation {
                Text("Latitude: \(loc.coordinate.latitude)")
                    .font(.title2)
                    .accessibility(identifier: "latLabel")
                Text("Longitude: \(loc.coordinate.longitude)")
                    .font(.title2)
                    .accessibility(identifier: "longLabel")
            } else {
                Text("No location yet.")
            }
            Spacer()
        }
        .alert(item: $locationManagerDelegate.error) { identifiableError in
            Alert(title: Text("Location Error"), message: Text(identifiableError.error.localizedDescription), dismissButton: .default(Text("OK")))
        }
    }
}

#Preview {
    ContentView()
}
