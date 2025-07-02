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
    @Published var placeString: String? = nil

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("didUpdateLocations called with: \(locations)")
        lastLocation = locations.last
        if let loc = locations.last {
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
                if let error = error {
                    print("Reverse geocoding failed: \(error)")
                    self?.placeString = nil
                    return
                }
                if let placemark = placemarks?.first {
                    let place = [placemark.name, placemark.locality, placemark.country].compactMap { $0 }.joined(separator: ", ")
                    print("Placemark: \(place)")
                    self?.placeString = place
                } else {
                    print("No placemark found")
                    self?.placeString = nil
                }
            }
        }
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
            
            if let place = locationManagerDelegate.placeString {
                Text(place)
                    .font(.title2)
                    .accessibility(identifier: "placeLabel")
            } else {
                Text("No place yet.")
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
