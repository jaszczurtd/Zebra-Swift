import Foundation
import ExternalAccessory
import CoreBluetooth
import UIKit

@objc(ZebraPluginBtPrint)
class ZebraPluginBtPrint: CDVPlugin {
    //plugin code
    var printerName: String?
    private var serialNumber: String?
    var isConnected: Bool = false
    var printerConnection: MfiBtPrinterConnection?
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var callbackID: String?
    
    var currentBTState: CBManagerState = .poweredOff
    var savedData: String?

    let OK_msg = "ok"
    var cancelText = "Cancel"
    var howLongScanning: TimeInterval = 20
    var delayTime: Int = 0
    var howLongKeepPrinterConnection: Double = 30.0
    let printerNotFoundDelayTime: Double = 10.0
    var printerFound: Bool = false
    
    let BT_Error_Message = "Bluetooth is turned off. To connect to Bluetooth devices, turn on Bluetooth in the system settings."
 
   /**
     Initializes the printer connection process.
     This method is responsible for initiating the process of finding and connecting to a Zebra printer. It calls `findConnectedPrinter`,
     a method that searches for a connected printer that supports the specified protocol string. If a compatible printer is found and successfully connected,
     the `isConnected` property of the class is updated accordingly.
     */
    @objc func initialize(_ command: CDVInvokedUrlCommand) {
        
        deb("initialize function called")
        deb("\(command.arguments)")

        //
        // Load parameters
        
        //parameter 0 - delay (miliseconds) until BT is closed
        if let delayTime = command.arguments[0] as? Int {
            self.delayTime = delayTime
            
            deb("delayTime: \(self.delayTime)")
            
            waitForMilliseconds(milliseconds: self.delayTime) {
                self.deb("BT timeout \(self.delayTime) has been reached - disconnecting Bluetooth")
                
                self.setPluginAsDisconnected()
                
                if self.centralManager != nil {
                    if self.centralManager.isScanning {
                        self.centralManager.stopScan()
                        self.centralManager = nil
                        self.deb("Bluetooth scanning stopped.")
                    }
                }
            }
            
        } else {
            deb("delayTime: invalid value: \(command.arguments[0])")
        }
        
        initializeBluetooth(timeout: howLongScanning) { bool in
            self.deb("Bluetooth enabled: \(bool)")
            
            self.findConnectedPrinter { [weak self] result in
                if let strongSelf = self {
                    strongSelf.isConnected = result
                }
            }
        }
     }
    
    @objc func print(_ command: CDVInvokedUrlCommand) {
        callbackID = command.callbackId
        printerFound = false
        
        initializeBluetooth(timeout: howLongScanning) { result in
            if result {
                guard let printerName = command.arguments[0] as? String else {
                    DispatchQueue.main.async {
                        self.sendErrorCallbackAndMessageWith(message: "invalid printer name")
                    }
                    return
                }
                self.deb("selected printer name: \(printerName)")
                self.printerName = printerName
                
                guard let data = command.arguments[1] as? String else {
                    DispatchQueue.main.async {
                        self.sendErrorCallbackAndMessageWith(message: "invalid printer data")
                    }
                    return
                }
                self.savedData = data

                self.findConnectedPrinter { [weak self] printerPaired in
                    if let strongSelf = self {
                        if printerPaired {
                            DispatchQueue.global(qos: .userInitiated).async {
                                if strongSelf.printerName == printerName {
                                    let pluginResult = strongSelf.justPrint(strongSelf.savedData)
                                    DispatchQueue.main.async {
                                        strongSelf.commandDelegate!.send(CDVPluginResult(status: pluginResult.1, messageAs: pluginResult.0), callbackId: command.callbackId)
                                    }
                                } else {
                                    DispatchQueue.main.async {
                                        strongSelf.sendErrorCallbackAndMessageWith(message: "Wrong printer selected")
                                    }
                                }
                            }
                        } else {
                            strongSelf.startScanning()
                        }
                    }
                }
            } else {
                self.sendErrorCallbackAndMessageWith(message: self.BT_Error_Message)
            }
        }
    }
    
    func justPrint(_ data: String?) -> (String, CDVCommandStatus) {
        
        var printError: Error?
        
        deb("data to print: \(data ?? "no data!")")
        deb("printerConnection is initialized: \(String(describing: printerConnection))")
        
        do {
            printerConnection?.close()
            printerConnection?.open()
            let printer = try ZebraPrinterFactory.getInstance(printerConnection)
            let lang = printer.getControlLanguage()
            
            deb("printer language: \(lang)")
            
            if lang != PRINTER_LANGUAGE_CPCL {
                let tool = printer.getToolsUtil()
                try tool?.sendCommand(data)
            }
        } catch {
            printError = error
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + howLongKeepPrinterConnection) { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf.printerConnection?.close()
            strongSelf.setPluginAsDisconnected()
            strongSelf.deb("Connection closed after delay to allow for data processing.")
        }
 
        if let error = printError {
            return (error.localizedDescription, CDVCommandStatus_ERROR)
        } else {
            return (OK_msg, CDVCommandStatus_OK)
        }
    }
    
    /**
     Generar bluetooth connection status callback function
     */
    @objc func status(_ command: CDVInvokedUrlCommand) {
        var pluginResult : CDVPluginResult?
        
        if currentBTState == .poweredOn {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        } else {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR)
        }
        
        deb("current bluetooth connection status: \(currentBTState)")
        
        self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }
}

extension ZebraPluginBtPrint: CBCentralManagerDelegate, CBPeripheralDelegate{

    private func deb(_ data: String) {
        NSLog("BT_PRINT_DBG: " + data)
    }
    
    @objc private func connectToPrinter( completion: (Bool) -> Void) {
        
        if let pc = printerConnection, pc.isConnected() {
            deb("Reusing existing connection")
            completion(true)
            return
        }
        
        guard let serial = serialNumber else {
            deb("Invalid printer serial number provided for connection")
            return
        }
        guard let pc = MfiBtPrinterConnection(serialNumber: serial) else {
            deb("Error while trying to connect to \(serial) printer")
            return
        }
        printerConnection = pc
        pc.open()
        let connected = pc.isConnected()
        if  connected {
            deb("printer \(serial) is connected")
        } else {
            deb("cannot connect to printer \(serial)")
        }
        completion(connected)
    }

    @objc func findConnectedPrinter(completion: (Bool) -> Void) {
        let manager = EAAccessoryManager.shared()
        let connectedDevices = manager.connectedAccessories
        var deviceConnected = false
        
        deb("connected devices array: \(connectedDevices)")
        
        if connectedDevices.isEmpty {
            deviceConnected = false
            completion(false)
            return
        }
        
        deb("trying to find printer: \(printerName ?? "(no printer name specified)")")
        
        for device in connectedDevices {
            deb("found device name: \(device.name)")
            
            if device.protocolStrings.contains("com.zebra.rawport") &&
                device.name == printerName {
                serialNumber = device.serialNumber
                deviceConnected = true
                deb("Zebra \(device.name) device found with serial number -> \(serialNumber ?? "N.D")")
                connectToPrinter(completion: { completed in
                    completion(completed)
                })
            }
        }
        
        if(!deviceConnected){
            completion(false)
        }
    }
    
    func waitForMilliseconds(milliseconds: Int, completion: @escaping () -> Void) {
        let delayTime = DispatchTime.now() + .milliseconds(milliseconds)
        
        DispatchQueue.main.asyncAfter(deadline: delayTime) {
            completion()
        }
    }

    func showAlert(_ title: String) {
        let alert = UIAlertController(title: "Info", message: title, preferredStyle: .alert)
        
        let okAction = UIAlertAction(title: cancelText, style: .default, handler: nil)
        alert.addAction(okAction)
        
        self.viewController.present(alert, animated: true, completion: nil)
    }
    
    func showBTErrorMessage() {
        showAlert(BT_Error_Message)
    }
    
    private func sendErrorCallbackWith(message: String) {
        deb(message)
        var pluginResult : CDVPluginResult?
        if let callbackId = self.callbackID {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: message)
            self.commandDelegate!.send(pluginResult, callbackId: callbackId)
        }
    }
    
    private func sendErrorCallbackAndMessageWith(message: String) {
        self.showAlert(message)
        
        var pluginResult : CDVPluginResult?
        if let callbackId = self.callbackID {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: message)
            self.commandDelegate!.send(pluginResult, callbackId: callbackId)
        }
    }
    
    /// ----------------------- BLUETOOTH MANAGEMENT -----------------------

    func startScanning() {
        if let manager = centralManager, manager.state == .poweredOn {
            deb("started scanning for peripherials")
            manager.scanForPeripherals(withServices: nil, options: nil)
            
            DispatchQueue.global().asyncAfter(deadline: .now() + printerNotFoundDelayTime) { [weak self] in
                guard let strongSelf = self else { return }
               
                if !strongSelf.printerFound {
                    manager.stopScan()
                    strongSelf.sendErrorCallbackWith(message: "printer not found")
                }
            }
        } else {
            sendErrorCallbackAndMessageWith(message: "Cannot scan, Bluetooth is not powered on.")
        }
    }
    
    // bluetooth status listener
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
        switch central.state {
        case .poweredOn:
            deb("Bluetooth on")
        case .poweredOff:
            setPluginAsDisconnected()
            showAlert("Bluetooth is powered off.")
        case .resetting:
            showAlert("Bluetooth is resetting.")
        case .unauthorized:
            showAlert("Bluetooth is unauthorized.")
        case .unsupported:
            showAlert("Bluetooth is unsupported on this device.")
        case .unknown:
            showAlert("Bluetooth state is unknown.")
        @unknown default:
            showAlert("Unknown Bluetooth state.")
        }
        
        currentBTState = central.state
    }
        
    // Found new peripheral
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // check for zq610 printer and update modal

        if connectedPeripheral != nil {
            reconnectToPeripheral()
            return
        }
        
        deb("BT device found: \(peripheral.identifier.uuidString ) \(peripheral.name ?? "") and looking for: \(self.printerName?.lowercased() ?? "no name")")
        
        // Autoconnect if printerName are available
        if let name = peripheral.name?.lowercased(), self.printerName != nil, name == self.printerName?.lowercased() {
            
            deb("Making connection to: \(peripheral)")
            connectedPeripheral = peripheral
            printerFound = true
            centralManager.stopScan()
            centralManager.connect(peripheral, options: nil)
            return
        }
    }
    
    func reconnectToPeripheral() {
        if let peripheral = connectedPeripheral {
            centralManager.connect(peripheral, options: nil)
            deb("Reconnecting to previously connected peripheral: \(peripheral.name ?? "unknown")")
        } else {
            deb("No previously connected peripheral found. Starting a new scan.")
            startScanning()
        }
    }
    
    // Disconnect from peripheral
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        
        deb("Disconnected from peripheral: \(peripheral.name ?? "unknown"), Error: \(error?.localizedDescription ?? "none")")
        reconnectToPeripheral()
    }
    
    func setPluginAsDisconnected() {
        isConnected = false
        printerConnection = nil
    }
    
    func initializeBluetooth(timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        let startTime = Date()
        
        func checkBluetoothPeriodically() {
            if currentBTState == .poweredOn {
                
                deb("BT is enabled, returning success")
                completion(true)
                return
            }
            
            if Date().timeIntervalSince(startTime) >= timeout {
                deb("Timeout reached, bt is still not ready.")
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                checkBluetoothPeriodically()
            }
        }
        
        checkBluetoothPeriodically()
    }

// deviceSelected :
// 1. Get the device name
// 2. Connect to the device
// 3. Send the device name to the cordova plugin
// 4. Close the alert
// 5. Print the data
// 6. Return the result to the cordova plugin

    // Connected to peripheral
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {

        guard let deviceName = peripheral.name else {
            sendErrorCallbackWith(message: "cannot get device name from connection")
            return
        }
        
        deb("connected with device \(deviceName)")

        if deviceName == printerName {
            connectedPeripheral = peripheral
            printerFound = true

            peripheral.delegate = self
            peripheral.discoverServices(nil)
        } else {
            sendErrorCallbackWith(message: "connected device \(deviceName) is not \(printerName ?? "(no name provided)")")
        }
        
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
        if let error = error {
            sendErrorCallbackWith(message: "Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            sendErrorCallbackWith(message: "No services on device \(peripheral.name ?? "unknown")")
            return
        }
        
        deb("Found \(services.count) services for peripheral: \(peripheral.name ?? "Unknown")")
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        deb("current bluetooth connection status: \(currentBTState)")
        
        if let error = error {
            sendErrorCallbackWith(message: "Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            sendErrorCallbackWith(message: "No characteristics for service: \(service.uuid)")
            return
        }
        
        deb("Found \(characteristics.count) characteristics for service: \(service.uuid)")

        for characteristic in characteristics {
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                if let data = self.savedData {
                    let dataToPrint = Data(data.utf8)
                    
                    let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
                                    
                    peripheral.writeValue(dataToPrint, for: characteristic, type: writeType)
                    deb("Data written to characteristic: \(characteristic.uuid)")
                    
                    self.savedData = nil
                    
                    if let callbackId = self.callbackID {
                        self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: OK_msg), callbackId: callbackId)
                    }

                    break
                }
            }
        }
    }
 
}
