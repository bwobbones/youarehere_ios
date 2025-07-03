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
    @Published var isLoading: Bool = false

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestLocation() {
        isLoading = true
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("didUpdateLocations called with: \(locations)")
        lastLocation = locations.last
        if let loc = locations.last {
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
                guard let self = self else { return }
                self.isLoading = false
                if let error = error {
                    print("Reverse geocoding failed: \(error)")
                    return
                }
                if let placemark = placemarks?.first {
                    self.placeString = [placemark.name, placemark.locality, placemark.country].compactMap { $0 }.joined(separator: ", ")
                    print("Placemark: \(self.placeString ?? "")")
                } else {
                    self.placeString = "No place yet."
                    print("No placemark found")
                }
            }
        } else {
            isLoading = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("didFailWithError: \(error)")
        self.error = IdentifiableError(error)
        isLoading = false
    }
}

struct ContentView: View {
    @StateObject private var locationManagerDelegate = LocationManagerDelegateWrapper()
    
    var body: some View {
        VStack {
            Spacer()
            Button(action: {
                locationManagerDelegate.requestLocation()
            }) {
                Text("Get Location")
                    .font(.largeTitle)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(24)
            }
            .padding(.horizontal)
            if locationManagerDelegate.isLoading {
                ProgressView()
                    .padding()
            }
            Text(locationManagerDelegate.placeString ?? "No place yet.")
                .font(.title2)
                .padding()
            Spacer()
        }
        .alert(item: $locationManagerDelegate.error) { err in
            Alert(title: Text("Location Error"), message: Text(err.error.localizedDescription), dismissButton: .default(Text("OK")))
        }
    }
}

#Preview {
    ContentView()
}
