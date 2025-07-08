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
    var locationRefreshTimer: Timer?
    var locationCountdownTimer: Timer?
    var secondsUntilRefresh: Int = 30
    var playedLocations = Set<String>()
    var stillInLocation: String? = nil
    var justPlayedLocation: String? = nil
    
    static let proxyBaseURL = Config.proxyBaseURL
    static let claudeProxyURL = URL(string: "\(proxyBaseURL)/api/claude")!
    static let ttsProxyURL = URL(string: "\(proxyBaseURL)/api/tts")!
    let claudeClientAPIKey = Config.claudeClientAPIKey
    
    func startLocationTimers() {
        // Start 30-second location refresh timer
        locationRefreshTimer?.invalidate()
        locationCountdownTimer?.invalidate()
        secondsUntilRefresh = 30
        locationRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.fetchAndShowLocation()
            self?.secondsUntilRefresh = 30
        }
        locationCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.secondsUntilRefresh > 0 {
                self.secondsUntilRefresh -= 1
                self.updateListTemplate()
            }
        }
    }
    func stopLocationTimers() {
        locationRefreshTimer?.invalidate()
        locationCountdownTimer?.invalidate()
    }
    
    init(ic: CPInterfaceController) {
        self.ic = ic
        super.init()
        locationManager.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        presentListTemplate()
        locationRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.fetchAndShowLocation(isTimer: true)
            self?.secondsUntilRefresh = 30
        }
        locationCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.secondsUntilRefresh > 0 {
                self.secondsUntilRefresh -= 1
                self.updateListTemplate()
            }
        }
        // Fetch location immediately on launch
        fetchAndShowLocation()
        secondsUntilRefresh = 30
    }
    
    deinit {
        stopLocationTimers()
    }
    
    func presentListTemplate() {
        uiState = .idle
    }
    
    func fetchAndShowLocation(isTimer: Bool = false) {
        speechCancelled = false
        uiState = .gettingLocation
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
        // If this is a timer-based refresh, block replay if already played
        if isTimer, let place = currentPlace, playedLocations.contains(place) {
            justPlayedLocation = place
            stillInLocation = nil
            updateListTemplate()
            return
        }
        justPlayedLocation = nil
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
                // If the location changed, clear justPlayedLocation and stillInLocation
                if self.currentPlace != placeShort {
                    self.justPlayedLocation = nil
                    self.stillInLocation = nil
                }
                self.currentPlace = placeShort
                self.uiState = .gotLocation(placeShort)
                self.fetchClaudeSummary(for: placemark)
            } // else: do nothing if no placemark found
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
        // Prevent replaying the same location
        if playedLocations.contains(placeShort) {
            self.stillInLocation = placeShort
            self.justPlayedLocation = nil
            updateListTemplate()
            return
        }
        self.stillInLocation = nil
        self.justPlayedLocation = nil
        playedLocations.insert(placeShort)
        self.uiState = .thinkingOfWhatToSay(placeShort)
        stopLocationTimers() // Stop timers while playing audio
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
                    self.startLocationTimers() // Resume timers on error
                    return
                }
                guard let data = data else {
                    self.uiState = .error("No TTS audio.")
                    self.startLocationTimers() // Resume timers on error
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
                    self.startLocationTimers() // Resume timers on error
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
            justPlayedLocation = place
            stillInLocation = nil
            uiState = .gotLocation(place)
        } else {
            uiState = .idle
        }
        startLocationTimers() // Resume timers after playback
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isPlaying = false
        stopProgressTimer()
        if let place = currentPlace {
            justPlayedLocation = place
            stillInLocation = nil
            uiState = .gotLocation(place)
        } else {
            uiState = .idle
        }
        startLocationTimers() // Resume timers after playback
    }
    
    func updateListTemplate() {
        guard let ic = ic else { return }
        var detail: String? = nil
        var items: [CPListItem] = []
        var locationTitle: String = currentPlace ?? "Unknown location"
        switch uiState {
        case .idle:
            if let justPlayed = justPlayedLocation {
                detail = "Just played \(justPlayed)\nRefreshing in \(secondsUntilRefresh)s"
            } else if let still = stillInLocation {
                detail = "Still in \(still)\nRefreshing in \(secondsUntilRefresh)s"
            } else {
                detail = "Refreshing in \(secondsUntilRefresh)s"
            }
        case .gettingLocation:
            detail = "Getting location…"
        case .gotLocation(let place):
            if let justPlayed = justPlayedLocation {
                detail = "Just played \(justPlayed)\nRefreshing in \(secondsUntilRefresh)s"
            } else if let still = stillInLocation {
                detail = "Still in \(still)\nRefreshing in \(secondsUntilRefresh)s"
            } else {
                detail = place + "\nRefreshing in \(secondsUntilRefresh)s"
            }
            locationTitle = place
        case .thinkingOfWhatToSay(let place):
            detail = "Thinking of what to say about \(place)"
            locationTitle = place
        case .playingAudio(_):
            if let player = audioPlayer, player.duration > 0 {
                let percent = Int((player.currentTime / player.duration) * 100)
                detail = "\(percent)%"
            } else {
                detail = nil
            }
        case .error(let msg):
            detail = msg + "\nRefreshing in \(secondsUntilRefresh)s"
        }
        let playLocationItem = CPListItem(text: "Play location", detailText: detail)
        playLocationItem.handler = { [weak self] _, completion in
            guard let self = self else { completion(); return }
            if let place = self.currentPlace, self.playedLocations.contains(place) {
                self.stillInLocation = place
                self.updateListTemplate()
                completion()
                return
            }
            self.fetchAndShowLocation()
            self.secondsUntilRefresh = 30
            completion()
        }
        items.append(playLocationItem)
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
        let template = CPListTemplate(title: locationTitle, sections: [section])
        self.listTemplate = template
        ic.setRootTemplate(template, animated: false, completion: nil)
    }
}
