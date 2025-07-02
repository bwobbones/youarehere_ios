//
//  youarehere_iosApp.swift
//  youarehere-ios
//
//  Created by Gregory Lucas-Smith on 26/6/2024.
//

import SwiftUI

@main
struct youarehere_iosApp: App { 
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AudioManager.shared)
                .onAppear {
                    AudioManager.shared.handleBackgroundAudio()
                }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }
}
