import Foundation

let CDVCommandStatus_OK = CDVCommandStatus.ok
let CDVCommandStatus_ERROR = CDVCommandStatus.error

// Stworzenie klasy CDVPluginResult, która wspiera 'messageAs'
@objc class CDVPluginResult: NSObject {
    var status: CDVCommandStatus
    var message: Any?

    init(status: CDVCommandStatus, messageAs message: Any?) {
        self.status = status
        self.message = message
    }
    
    init(status: CDVCommandStatus) {
        self.status = status
    }

    func getStatus() -> CDVCommandStatus {
        return self.status
    }

    func getMessage() -> Any? {
        return self.message
    }
}

// Enum CDVCommandStatus zgodny z Cordova
@objc enum CDVCommandStatus: Int {
    case ok = 0
    case error = 1
}

