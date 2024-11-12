import Foundation

@objc class CDVInvokedUrlCommand: NSObject {
    var arguments: [Any]
    var callbackId: String
    var className: String
    var methodName: String

    init(arguments: [Any], callbackId: String = "testCallbackId", className: String = "ZebraPlugin", methodName: String = "") {
        self.arguments = arguments
        self.callbackId = callbackId
        self.className = className
        self.methodName = methodName
    }
}
