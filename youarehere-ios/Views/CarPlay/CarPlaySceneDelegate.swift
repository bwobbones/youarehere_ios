//
//  CarPlaySceneDelegate.swift
//  youarehere-ios
//
//  Created by Gregory Lucas-Smith on 1/7/2024.
//

import CarPlay

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    
    var interfaceController: CPInterfaceController?
    var carPlayContentView: CarPlayContentView?
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {    
        self.interfaceController = interfaceController
        self.carPlayContentView = CarPlayContentView(ic: interfaceController)
    }
    
    private func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController) {
        self.interfaceController = nil
    }
}
