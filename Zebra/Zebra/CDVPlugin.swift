import Foundation
import UIKit

@objc class CDVCommandDelegate: NSObject {
    func send(_ pluginResult: CDVPluginResult!, callbackId: String!) {
        if let resultMessage = pluginResult.getMessage() {
            NSLog("Callback ID: \(String(describing: callbackId)), Result: \(pluginResult.getStatus()) / \(resultMessage)")
        } else {
            NSLog("Callback ID: \(String(describing: callbackId)), Result: \(pluginResult.getStatus()) / No Message")
        }
    }
}

@objc class CDVPlugin: NSObject {
    
    var viewController: UIViewController
    var commandDelegate: CDVCommandDelegate?
    
    init(viewController: UIViewController) {
        self.viewController = viewController
        self.commandDelegate = CDVCommandDelegate()
        super.init()
    }
}

