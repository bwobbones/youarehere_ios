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
    var isPlaying = false
    var audioPlayer: AVAudioPlayer?
    var audioTask: URLSessionDataTask?
    var speechCancelled = false
    
    let claudeProxyURL = URL(string: "https://claude-proxy-hfel3gev0-gregs-projects-58823ca2.vercel.app/api/claude")!
    let claudeClientAPIKey = "sumpleriltskin"
    
    init(ic: CPInterfaceController) {
        self.ic = ic
        super.init()
        locationManager.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
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
        speechCancelled = false
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
                let place = [placemark.name, placemark.locality, placemark.country].compactMap { $0 }.joined(separator: ", ")
                self.placeString = place
                self.fetchClaudeSummary(for: placemark)
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
    
    func fetchClaudeSummary(for placemark: CLPlacemark) {
        isLoading = true
        updateListTemplate(with: "Getting summary…")
        let name = placemark.name ?? ""
        let state = placemark.administrativeArea ?? ""
        let country = placemark.country ?? ""
        let placeShort = [name, state, country].filter { !$0.isEmpty }.joined(separator: ", ")
        let prompt = "Tell me something interesting about \(placeShort)."
        var request = URLRequest(url: claudeProxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(claudeClientAPIKey, forHTTPHeaderField: "x-client-key")
        let body = ["prompt": prompt]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.updateListTemplate(with: "Error: \(error.localizedDescription)")
                    return
                }
                guard let data = data else {
                    self?.updateListTemplate(with: "No summary found.")
                    return
                }
                var summary: String? = nil
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let contentArray = json["content"] as? [[String: Any]],
                   let firstContent = contentArray.first,
                   let s = firstContent["text"] as? String {
                    summary = s
                }
                if let summary = summary, self?.speechCancelled == false {
                    self?.fetchAndPlayTTS(for: summary)
                } else {
                    self?.updateListTemplate(with: "No summary found.")
                }
            }
        }.resume()
    }
    
    func fetchAndPlayTTS(for text: String) {
        let ttsURL = URL(string: "https://claude-proxy-hgt1osfrv-gregs-projects-58823ca2.vercel.app/api/tts")!
        var request = URLRequest(url: ttsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["text": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        audioTask?.cancel()
        audioTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.updateListTemplate(with: "TTS error: \(error.localizedDescription)")
                    return
                }
                guard let data = data else {
                    self?.updateListTemplate(with: "No TTS audio.")
                    return
                }
                do {
                    self?.audioPlayer = try AVAudioPlayer(data: data)
                    self?.audioPlayer?.delegate = self
                    self?.isPlaying = true
                    self?.audioPlayer?.play()
                } catch {
                    self?.updateListTemplate(with: "Audio playback error.")
                }
            }
        }
        audioTask?.resume()
    }
    
    func stopAudio() {
        audioTask?.cancel()
        audioPlayer?.stop()
        isPlaying = false
        updateListTemplate()
    }
    
    func updateListTemplate(with detailOverride: String? = nil) {
        guard let ic = ic else { return }
        let detail = isLoading ? (detailOverride ?? "Getting location…") : nil
        let getLocationItem = CPListItem(text: "Get Location", detailText: detail)
        getLocationItem.handler = { [weak self] _, completion in
            print("[CarPlay] Get Location row tapped (updateListTemplate)")
            self?.fetchAndShowLocation()
            completion()
        }
        var items = [getLocationItem]
        if isPlaying {
            let stopItem = CPListItem(text: "Stop", detailText: nil)
            stopItem.handler = { [weak self] _, completion in
                self?.speechCancelled = true
                self?.stopAudio()
                completion()
            }
            items.append(stopItem)
        }
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "You Are Here", sections: [section])
        self.listTemplate = template
        ic.setRootTemplate(template, animated: false, completion: nil)
    }
}

extension CarPlayContentView: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        updateListTemplate()
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isPlaying = false
        updateListTemplate()
    }
}
