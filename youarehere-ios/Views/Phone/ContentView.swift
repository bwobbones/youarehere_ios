//
//  ContentView.swift
//  youarehere-ios
//
//  Created by Gregory Lucas-Smith on 26/6/2024.
//

import SwiftUI
import CoreLocation
import AVFoundation

class IdentifiableError: Identifiable {
    let id = UUID()
    let error: Error
    init(_ error: Error) { self.error = error }
}

let claudeProxyURL = URL(string: "https://claude-proxy-hfel3gev0-gregs-projects-58823ca2.vercel.app/api/claude")!
let claudeClientAPIKey = "sumpleriltskin"

class LocationManagerDelegateWrapper: NSObject, ObservableObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    let audioPlayerDelegate = AudioPlayerDelegate()
    @Published var lastLocation: CLLocation?
    @Published var error: IdentifiableError?
    @Published var placeString: String? = nil
    @Published var isLoading: Bool = false
    @Published var isPlaying: Bool = false
    var audioPlayer: AVAudioPlayer?
    var audioTask: URLSessionDataTask?
    var speechCancelled = false

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
                    let place = [placemark.name, placemark.locality, placemark.country].compactMap { $0 }.joined(separator: ", ")
                    self.placeString = place
                    self.fetchClaudeSummary(for: placemark)
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

    func fetchClaudeSummary(for placemark: CLPlacemark) {
        isLoading = true
        self.placeString = "Getting summary…"
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
                    self?.placeString = "Error: \(error.localizedDescription)"
                    return
                }
                guard let data = data else {
                    self?.placeString = "No summary found."
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
                    self?.placeString = "No summary found."
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
        print("[TTS] Sending request for text: \(text.prefix(100))")
        audioTask?.cancel()
        audioTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[TTS] Error: \(error)")
                    self?.placeString = "TTS error: \(error.localizedDescription)"
                    return
                }
                if let httpResponse = response as? HTTPURLResponse {
                    print("[TTS] HTTP status: \(httpResponse.statusCode)")
                }
                guard let data = data else {
                    print("[TTS] No data received")
                    self?.placeString = "No TTS audio."
                    return
                }
                print("[TTS] First 100 bytes: \(String(data: data.prefix(100), encoding: .utf8) ?? "<binary>")")
                print("[TTS] Received audio data, size: \(data.count) bytes")
                do {
                    self?.audioPlayer = try AVAudioPlayer(data: data)
                    self?.audioPlayer?.delegate = self?.audioPlayerDelegate
                    self?.audioPlayerDelegate.onFinish = { [weak self] in
                        print("[TTS] Playback finished")
                        self?.isPlaying = false
                    }
                    self?.isPlaying = true
                    self?.placeString = "Playing audio…"
                    print("[TTS] Starting playback")
                    self?.audioPlayer?.play()
                } catch {
                    print("[TTS] Audio playback error: \(error)")
                    self?.placeString = "Audio playback error."
                }
            }
        }
        audioTask?.resume()
    }

    func stopAudio() {
        audioTask?.cancel()
        audioPlayer?.stop()
        isPlaying = false
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
            if let status = locationManagerDelegate.placeString, !status.isEmpty {
                Text(status)
                    .font(.title2)
                    .padding()
            }
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
}

#Preview {
    ContentView()
}
