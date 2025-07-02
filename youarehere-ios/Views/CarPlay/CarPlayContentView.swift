//
//  CarPlayContentView.swift
//  youarehere-ios
//
//  Created by Gregory Lucas-Smith on 2/7/2024.
//

import Foundation
import CarPlay
import Combine
import AVFoundation
import UIKit
import CoreLocation

class CarPlayContentView: NSObject {
    
    var ic: CPInterfaceController?
    let locationManager = CLLocationManager()
    
    init(ic: CPInterfaceController) {
        self.ic = ic
        super.init()
        locationManager.delegate = self
        presentGridTemplate()
    }
    
    func presentGridTemplate() {
        let button = CPGridButton(titleVariants: ["Get Location"], image: UIImage(systemName: "location.circle")!) { [weak self] _ in
            self?.fetchAndShowLocation()
        }
        let gridTemplate = CPGridTemplate(title: "You Are Here", gridButtons: [button])
        ic?.setRootTemplate(gridTemplate, animated: true, completion: nil)
        }
    
    func fetchAndShowLocation() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }
}

extension CarPlayContentView: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("didUpdateLocations called with: \(locations)")
        guard let loc = locations.last else { return }
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
            if let error = error {
                print("Reverse geocoding failed: \(error)")
                return
            }
            if let placemark = placemarks?.first {
                let placeString = [placemark.name, placemark.locality, placemark.country].compactMap { $0 }.joined(separator: ", ")
                print("Placemark: \(placeString)")
                let alert = CPAlertTemplate(titleVariants: [placeString], actions: [
                    CPAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
                        self?.presentGridTemplate()
                    })
                ])
                self?.ic?.presentTemplate(alert, animated: true, completion: nil)
            } else {
                print("No placemark found")
                let alert = CPAlertTemplate(titleVariants: ["No place found"], actions: [
                    CPAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
                        self?.presentGridTemplate()
                    })
                ])
                self?.ic?.presentTemplate(alert, animated: true, completion: nil)
            }
        }
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("didFailWithError: \(error)")
        let alert = CPAlertTemplate(titleVariants: ["Location Error"], actions: [
            CPAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
                self?.presentGridTemplate()
            })
        ])
        ic?.presentTemplate(alert, animated: true, completion: nil)
    }
}
