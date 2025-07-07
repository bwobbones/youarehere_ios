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

// Helper to load config values from Config.plist
func loadConfigValue(_ key: String) -> String {
    guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
          let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
          let value = plist[key] as? String else {
        fatalError("Missing or invalid Config.plist value for \(key)")
    }
    return value
}

class CarPlayContentView: NSObject, CLLocationManagerDelegate, AVAudioPlayerDelegate {
    
    enum CarPlayUIState {
        case idle
        case gettingLocation
        case gotLocation(String)
        case thinkingOfWhatToSay(String)
        case playingAudio(String)
        case error(String)
    }
    
        var ic: CPInterfaceController?
    let locationManager = CLLocationManager()
    var listTemplate: CPListTemplate?
    var isLoading: Bool = false
    var isPlaying = false
    var audioPlayer: AVAudioPlayer?
    var audioTask: URLSessionDataTask?
    var speechCancelled = false
    var currentPlace: String? = nil
    var progressTimer: Timer?
    var uiState: CarPlayUIState = .idle { didSet { updateListTemplate() } }
    
    static let proxyBaseURL = loadConfigValue("ProxyBaseURL")
    static let claudeProxyURL = URL(string: "\(proxyBaseURL)/api/claude")!
    static let ttsProxyURL = URL(string: "\(proxyBaseURL)/api/tts")!
    let claudeClientAPIKey = loadConfigValue("ClaudeClientAPIKey")
    
    init(ic: CPInterfaceController) {
        self.ic = ic
        super.init()
        locationManager.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        presentListTemplate()
    }
    
    func presentListTemplate() {
        uiState = .idle
    }
    
    func fetchAndShowLocation() {
        speechCancelled = false
        uiState = .gettingLocation
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
            guard let self = self else { return }
            if let error = error {
                self.uiState = .error("Reverse geocoding failed: \(error.localizedDescription)")
                return
            }
            if let placemark = placemarks?.first {
                let areaOfInterest = placemark.areasOfInterest?.first
                let locality = placemark.locality
                let subLocality = placemark.subLocality
                let state = placemark.administrativeArea
                let country = placemark.country
                let placeShort = [areaOfInterest, locality, subLocality, state, country].compactMap { $0 }.joined(separator: ", ")
                self.currentPlace = placeShort
                self.uiState = .gotLocation(placeShort)
                self.fetchClaudeSummary(for: placemark)
            } else {
                self.uiState = .error("No place found")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        uiState = .error("Location error: \(error.localizedDescription)")
    }
    
    func fetchClaudeSummary(for placemark: CLPlacemark) {
        guard let placeShort = currentPlace else { return }
        self.uiState = .thinkingOfWhatToSay(placeShort)
        let prompt = "You are an expert tour guide. Speak as an authority on the subject. Do not ask the user for clarifications or questions. Tell me something interesting about \(placeShort)."
        var request = URLRequest(url: CarPlayContentView.claudeProxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(claudeClientAPIKey, forHTTPHeaderField: "x-client-key")
        let body = ["prompt": prompt]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.uiState = .error("Claude error: \(error.localizedDescription)")
                    return
                }
                guard let data = data else {
                    self.uiState = .error("No summary found.")
                    return
                }
                var summary: String? = nil
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let contentArray = json["content"] as? [[String: Any]],
                   let firstContent = contentArray.first,
                   let s = firstContent["text"] as? String {
                    summary = s
                }
                if let summary = summary, self.speechCancelled == false {
                    self.fetchAndPlayTTS(for: summary)
                } else {
                    self.uiState = .error("No summary found.")
                }
            }
        }.resume()
    }
    
    func fetchAndPlayTTS(for text: String) {
        guard let placeShort = currentPlace else { return }
        self.uiState = .thinkingOfWhatToSay(placeShort)
        var request = URLRequest(url: CarPlayContentView.ttsProxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["text": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        audioTask?.cancel()
        audioTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.uiState = .error("TTS error: \(error.localizedDescription)")
                    return
                }
                guard let data = data else {
                    self.uiState = .error("No TTS audio.")
                    return
                }
                do {
                    self.audioPlayer = try AVAudioPlayer(data: data)
                    self.audioPlayer?.delegate = self
                    self.isPlaying = true
                    self.startProgressTimer()
                    self.uiState = .playingAudio(placeShort)
                    self.audioPlayer?.play()
                } catch {
                    self.uiState = .error("Audio playback error.")
                }
            }
        }
        audioTask?.resume()
    }
    
    func stopAudio() {
        audioTask?.cancel()
        audioPlayer?.stop()
        isPlaying = false
        stopProgressTimer()
        if let place = currentPlace {
            uiState = .gotLocation(place)
        } else {
            uiState = .idle
        }
    }
    
    func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateListTemplate()
        }
    }
    
    func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        stopProgressTimer()
        if let place = currentPlace {
            uiState = .gotLocation(place)
        } else {
            uiState = .idle
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isPlaying = false
        stopProgressTimer()
        if let place = currentPlace {
            uiState = .gotLocation(place)
        } else {
            uiState = .idle
        }
    }
    
    func updateListTemplate() {
        guard let ic = ic else { return }
        var detail: String? = nil
        var items: [CPListItem] = []
        switch uiState {
        case .idle:
            detail = nil
        case .gettingLocation:
            detail = "Getting location…"
        case .gotLocation(let place):
            detail = place
        case .thinkingOfWhatToSay(let place):
            detail = "Thinking of what to say about \(place)"
        case .playingAudio(_):
            if let player = audioPlayer, player.duration > 0 {
                let percent = Int((player.currentTime / player.duration) * 100)
                detail = "\(percent)%"
            } else {
                detail = nil
            }
        case .error(let msg):
            detail = msg
        }
        let getLocationItem = CPListItem(text: "Get Location", detailText: detail)
        getLocationItem.handler = { [weak self] _, completion in
            self?.fetchAndShowLocation()
            completion()
        }
        items.append(getLocationItem)
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
