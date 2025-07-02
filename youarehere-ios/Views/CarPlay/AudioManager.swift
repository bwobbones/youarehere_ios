import AVFoundation

class AudioManager: ObservableObject {
    static let shared = AudioManager()
    var player: AVPlayer?

    func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
    }

    func playAudio(from url: URL) {
        configureAudioSession()
        player = AVPlayer(url: url)
        player?.play()
    }

    func handleBackgroundAudio() {
//        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
//        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc func appDidEnterBackground() {
        player?.play()
    }

    @objc func appWillEnterForeground() {
        player?.play()
    }
}
