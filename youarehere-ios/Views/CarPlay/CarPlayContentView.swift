//
//  CarPlayContentView.swift
//  youarehere-ios
//
//  Created by Gregory Lucas-Smith on 2/7/2024.
//

import Foundation
import CarPlay

class CarPlayHelloWorld {
    var template: CPListTemplate {
        return CPListTemplate(title: "Hello world", sections: [self.section])
    }
    
    var items: [CPListItem] {
        return [CPListItem(text:"Hello world", detailText: landmarks[0].name, image: UIImage(systemName: "globe"))]
    }
    
    private var section: CPListSection {
        return CPListSection(items: items)
    }
}
