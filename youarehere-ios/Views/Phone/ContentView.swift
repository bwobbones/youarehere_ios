//
//  ContentView.swift
//  youarehere-ios
//
//  Created by Gregory Lucas-Smith on 26/6/2024.
//

import SwiftUI
import CoreLocation
import AVFoundation
import Foundation

class IdentifiableError: Identifiable {
    let id = UUID()
    let error: Error
    init(_ error: Error) { self.error = error }
}

private let proxyBaseURL = Config.proxyBaseURL
private let claudeProxyURL = URL(string: "\(proxyBaseURL)/api/claude")!
private let ttsProxyURL = URL(string: "\(proxyBaseURL)/api/tts")!
let claudeClientAPIKey = Config.claudeClientAPIKey

enum PhoneUIState {
    case idle
    case gettingLocation
    case gotLocation(String)
    case thinkingOfWhatToSay(String)
    case playingAudio(String)
    case error(String)
}

class LocationManagerDelegateWrapper: NSObject, ObservableObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    let audioPlayerDelegate = AudioPlayerDelegate()
    @Published var lastLocation: CLLocation?
    @Published var error: IdentifiableError?
    @Published var isLoading: Bool = false
    @Published var isPlaying: Bool = false
    @Published var uiState: PhoneUIState = .idle
    var audioPlayer: AVAudioPlayer?
    var audioTask: URLSessionDataTask?
    var speechCancelled = false
    var currentPlace: String? = nil
    var progressTimer: Timer?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestLocation() {
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
        self.uiState = .error("Location error: \(error.localizedDescription)")
    }

    func fetchClaudeSummary(for placemark: CLPlacemark) {
        guard let placeShort = currentPlace else { return }
        self.uiState = .thinkingOfWhatToSay(placeShort)
        let prompt = "You are an expert tour guide. Speak as an authority on the subject. Do not ask the user for clarifications or questions. Tell me something interesting about \(placeShort)."
        var request = URLRequest(url: claudeProxyURL)
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
        var request = URLRequest(url: ttsProxyURL)
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
                    self.audioPlayer?.delegate = self.audioPlayerDelegate
                    self.audioPlayerDelegate.onFinish = { [weak self] in
                        self?.isPlaying = false
                        self?.stopProgressTimer()
                        if let place = self?.currentPlace {
                            self?.uiState = .gotLocation(place)
                        } else {
                            self?.uiState = .idle
                        }
                    }
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
            self?.objectWillChange.send()
        }
    }

    func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onFinish?()
    }
}

struct ContentView: View {
    @StateObject private var locationManagerDelegate = LocationManagerDelegateWrapper()
    
    var body: some View {
        VStack {
            Spacer()
            Button(action: {
                locationManagerDelegate.speechCancelled = false
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
            statusView
            if locationManagerDelegate.isPlaying {
                Button(action: {
                    locationManagerDelegate.speechCancelled = true
                    locationManagerDelegate.stopAudio()
                }) {
                    Text("Stop")
                        .font(.title2)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
                .padding(.horizontal)
            }
            Spacer()
        }
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        .alert(item: $locationManagerDelegate.error) { err in
            Alert(title: Text("Location Error"), message: Text(err.error.localizedDescription), dismissButton: .default(Text("OK")))
        }
    }
    
    @ViewBuilder
    var statusView: some View {
        switch locationManagerDelegate.uiState {
        case .idle:
            EmptyView()
        case .gettingLocation:
            Text("Getting location…")
                .font(.title2)
                .padding()
        case .gotLocation(let place):
            Text(place)
                .font(.title2)
                .padding()
        case .thinkingOfWhatToSay(let place):
            Text("Thinking of what to say about \(place)")
                .font(.title2)
                .padding()
        case .playingAudio(_):
            if let player = locationManagerDelegate.audioPlayer, player.duration > 0 {
                let percent = Int((player.currentTime / player.duration) * 100)
                Text("\(percent)%")
                    .font(.title2)
                    .padding()
            } else {
                EmptyView()
            }
        case .error(let msg):
            Text(msg)
                .font(.title2)
                .padding()
        }
    }
}

#Preview {
    ContentView()
}
