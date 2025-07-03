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

class CarPlayContentView: NSObject, CLLocationManagerDelegate {
    
    var ic: CPInterfaceController?
    let locationManager = CLLocationManager()
    var placeString: String? = nil
    var listTemplate: CPListTemplate?
    var isLoading: Bool = false
    
    init(ic: CPInterfaceController) {
        self.ic = ic
        super.init()
        locationManager.delegate = self
        presentListTemplate()
    }
    
    func presentListTemplate() {
        let detail = isLoading ? "Getting location…" : (placeString ?? "No place yet.")
        let item = CPListItem(text: "Get Location", detailText: detail)
        item.handler = { [weak self] _, completion in
            print("[CarPlay] Get Location row tapped")
            self?.fetchAndShowLocation()
            completion()
        }
        let section = CPListSection(items: [item])
        let template = CPListTemplate(title: "You Are Here", sections: [section])
        self.listTemplate = template
        ic?.setRootTemplate(template, animated: true, completion: nil)
    }
    
    func fetchAndShowLocation() {
        print("[CarPlay] fetchAndShowLocation called")
        print("[CarPlay] Requesting location authorization and location")
        isLoading = true
        updateListTemplate()
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("[CarPlay] didUpdateLocations called with: \(locations)")
        isLoading = false
        guard let loc = locations.last else { return }
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
            guard let self = self else { return }
            if let error = error {
                print("[CarPlay] Reverse geocoding failed: \(error)")
            }
            if let placemark = placemarks?.first {
                self.placeString = [placemark.name, placemark.locality, placemark.country].compactMap { $0 }.joined(separator: ", ")
                print("[CarPlay] Placemark: \(self.placeString ?? "")")
            } else {
                self.placeString = "No place yet."
                print("[CarPlay] No placemark found")
            }
            self.updateListTemplate()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[CarPlay] didFailWithError: \(error)")
        isLoading = false
        placeString = "No place yet."
        updateListTemplate()
    }
    
    func updateListTemplate() {
        guard let ic = ic else { return }
        let detail = isLoading ? "Getting location…" : (placeString ?? "No place yet.")
        let item = CPListItem(text: "Get Location", detailText: detail)
        item.handler = { [weak self] _, completion in
            print("[CarPlay] Get Location row tapped (updateListTemplate)")
            self?.fetchAndShowLocation()
            completion()
        }
        let section = CPListSection(items: [item])
        let template = CPListTemplate(title: "You Are Here", sections: [section])
        self.listTemplate = template
        ic.setRootTemplate(template, animated: false, completion: nil)
    }
}
