//
//  CarPlayContentView.swift
//  youarehere-ios
//
//  Created by Gregory Lucas-Smith on 2/7/2024.
//

import Foundation
import CarPlay
import LocationProvider
import Combine

class CarPlayContentView {
    
    var cancellableLocation: AnyCancellable?
    var locationProvider: LocationProvider = LocationProvider()
    var ic: CPInterfaceController?
    
    var loc2: CLLocation?
    
    init(ic: CPInterfaceController) {
        
        print("initing")
        print(self.locationProvider)
         
        do {try locationProvider.start()}
        catch {
            print("No location access.")
            locationProvider.requestAuthorization()
        }
        setupSink()
        
        self.ic = ic
    }
    
    func setupSink() {
        cancellableLocation = locationProvider.locationWillChange.sink { loc in
            self.loc2 = loc
            self.ic?.setRootTemplate(self.regenerateTemplate(), animated: true, completion:nil)
        }
    }

    private func regenerateTemplate() -> CPListTemplate {
        print("rebuilding...")
        let newItems: [CPListItem] = [CPListItem(text:"Hello world", detailText: String(loc2?.coordinate.latitude ?? 0.0), image: UIImage(systemName: "globe"))]
        let section: CPListSection = CPListSection(items: newItems)
        return CPListTemplate(title: String(loc2?.coordinate.latitude ?? 0.0), sections: [section])
    }
    
    
    
    var template: CPListTemplate {
        return CPListTemplate(title: "Hello world", sections: [self.section])
    }
    
    var items: [CPListItem] {
        return [CPListItem(text:"Hello world", detailText: String(loc2?.coordinate.latitude ?? 0.0), image: UIImage(systemName: "globe"))]
    }
    
    private var section: CPListSection {
        return CPListSection(items: items)
    }
}
