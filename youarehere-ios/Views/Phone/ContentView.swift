//
//  ContentView.swift
//  youarehere-ios
//
//  Created by Gregory Lucas-Smith on 26/6/2024.
//

import SwiftUI
import LocationProvider

struct ContentView: View {
    
    @ObservedObject var locationProvider : LocationProvider
    
     init() {
         locationProvider = LocationProvider()
         do {try locationProvider.start()}
         catch {
             print("No location access.")
             locationProvider.requestAuthorization()
         }
     }
    
    var body: some View {
        VStack {
            MapView()
                .frame(height: 300)
            
            CircleImage()
                .offset(y: -130)
                .padding(.bottom, -130)
            
            VStack(alignment: .leading) {
                Text("Turtle Rock")
                    .font(.title)
                    .foregroundColor(.black)
                HStack {
                    Text("Joshua Tree National Park")
                        .font(.subheadline)
                    Spacer()
                    Text("California")
                        .font(.subheadline)
                }
                
                Divider()
                
                Text("About Turtle Rock")
                    .font(.title2)
                Text("latitude \(locationProvider.location?.coordinate.latitude ?? 0)")
                    .accessibility(identifier: "latLabel")
                Text("longitude \(locationProvider.location?.coordinate.longitude ?? 0)")
                    .accessibility(identifier: "longLabel")
            }
            .padding()
            
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
