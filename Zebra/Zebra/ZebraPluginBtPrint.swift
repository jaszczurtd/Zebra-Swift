import Foundation
import ExternalAccessory
import CoreBluetooth
import UIKit

@objc(ZebraPluginBtPrint)
class ZebraPluginBtPrint: CDVPlugin {
    //plugin code
    var wildcard: String?
    var printerName: String?
    private var serialNumber: String?
    var isConnected: Bool = false
    var printerConnection: MfiBtPrinterConnection?
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    var alertController: UIAlertController?
    
    var currentBTState: CBManagerState = .poweredOff
    var savedData: String?

    var cancelText: String = "Cancel"
    var howLongScanning: TimeInterval = 20
    var delayTime: Int = 0
    
    @objc private func connectToPrinter( completion: (Bool) -> Void) {
        guard let serial = serialNumber else {
            NSLog("Invalid printer serial number provided for connection")
            return
        }
        guard let pc = MfiBtPrinterConnection(serialNumber: serial) else {
            NSLog("Error while trying to connect to \(serial) printer")
            return
        }
        printerConnection = pc
        pc.open()
        let connected = pc.isConnected()
        if  connected {
            NSLog("printer \(serial) is connected")
        } else {
            NSLog("cannot connect to printer \(serial)")
        }
        completion(connected)
    }

    @objc func findConnectedPrinter(completion: (Bool) -> Void) {
        let manager = EAAccessoryManager.shared()
        let connectedDevices = manager.connectedAccessories
        var deviceConnected = false
        
        NSLog("connected devices array: \(connectedDevices)")
        
        if connectedDevices.isEmpty {
            deviceConnected = false
            completion(false)
            return
        }
        
        NSLog("trying to find printer: \(printerName ?? "(no printer name specified)")")
        
        for device in connectedDevices {
            NSLog("found device name: \(device.name)")
            
            if device.protocolStrings.contains("com.zebra.rawport") &&
                device.name == printerName {
                serialNumber = device.serialNumber
                deviceConnected = true
                NSLog("Zebra \(device.name) device found with serial number -> \(serialNumber ?? "N.D")")
                connectToPrinter(completion: { completed in
                    completion(completed)
                })
            }
        }
        
        if(!deviceConnected){
            completion(false)
        }
    }
    
    /**
     Initializes the printer connection process.
     This method is responsible for initiating the process of finding and connecting to a Zebra printer. It calls `findConnectedPrinter`,
     a method that searches for a connected printer that supports the specified protocol string. If a compatible printer is found and successfully connected,
     the `isConnected` property of the class is updated accordingly.
     */
    @objc func initialize(_ command: CDVInvokedUrlCommand) {
        
        NSLog("BT_PRINT_DEBUG: initialize function called")
        
        //
        // Load parameters
        
        //parameter 0 - delay (miliseconds) until BT is closed
        if let delayTime = command.arguments[0] as? Int {
            self.delayTime = delayTime
            
            NSLog("delayTime: \(self.delayTime)")
            
            waitForMilliseconds(milliseconds: self.delayTime) {
                NSLog("BT timeout \(self.delayTime) has been reached - disconnecting Bluetooth")
                
                if self.centralManager != nil {
                    if self.centralManager.isScanning {
                        self.centralManager.stopScan()
                        self.centralManager = nil
                        self.setPluginAsDisconnected()
                        NSLog("Bluetooth scanning stopped.")
                    }
                }
            }
            
        } else {
            NSLog("delayTime: invalid value: \(command.arguments[0])")
        }
        
        // parameters : Wildcard | Pattern for name search
        let wildcardParam: String? = command.arguments.count > 1 ? (command.arguments[1] as? String ) : nil
        self.wildcard = wildcardParam != "" ? wildcardParam : nil

        // parameters : Printer name | Name of the printer for a direct bluetooth connection
        let printerNameParam: String? = command.arguments.count > 2 ?  (command.arguments[2] as! String) : nil
        self.printerName = printerNameParam != "" ? printerNameParam : nil
        
        // parameters : Cancel button name | Name of the button for close the bluetooth modals
        let cancelButtonParam: String = command.arguments.count > 3 ? (command.arguments[3] as! String ) : "Cancel"
        self.cancelText = cancelButtonParam

        // parameters : for how long plugin is trying to scan for bluetooth devices?
        let howlong: Int = command.arguments.count > 4 ? (command.arguments[4] as! Int ) :  20
        self.howLongScanning = TimeInterval(howlong)
        
        NSLog("\(command.arguments[1])")
        NSLog("Wildcard: \(self.wildcard ?? "N.D")")
        NSLog("PrinterName: \(self.printerName ?? "N.D")")
        NSLog("CancelText: \(self.cancelText)")
        NSLog("How long scanning: \(howLongScanning)")
    
        initializeBluetooth(timeout: howLongScanning) { bool in
            NSLog("Bluetooth enabled: \(bool)")
            
            self.findConnectedPrinter { [weak self] result in
                if let strongSelf = self {
                    strongSelf.isConnected = result
                }
            }
        }
     }
    
    @objc func print(_ command: CDVInvokedUrlCommand) {
        initializeBluetooth(timeout: howLongScanning) { result in
            if result {
                DispatchQueue.global(qos: .userInitiated).async {
                    self.printPreparations(object: command)
                }
            } else {
                self.showBTErrorMessage()
            }
        }
    }
    
    @objc func printPreparations(object: CDVInvokedUrlCommand) {
        var pluginResult : CDVPluginResult?
        
        // Log the start of the print function
        NSLog("BT_PRINT_DEBUG: print function called")
        
        switch(currentBTState) {
        case .poweredOff, .resetting, .unknown, .unsupported:
            DispatchQueue.main.async {
                self.showBTErrorMessage()
            }
            return
        case .unauthorized:
            DispatchQueue.main.async {
                self.showAlert("Bluetooth is unauthorized.")
            }
            return
        case .poweredOn:
            NSLog("Bluetooth is ON, printing...")
        @unknown default:
            NSLog("unsupported bluetooth state: \(currentBTState)")
            return
        }
        
        guard let printerName = object.arguments[0] as? String else {
            DispatchQueue.main.async {
                self.showAlert("invalid printer name")
            }
            return
        }
        NSLog("selected printer name: \(printerName)")
        
        guard let data = object.arguments[1] as? String else {
            DispatchQueue.main.async {
                self.showAlert("invalid printer data")
            }
            return
        }
        savedData = data
        
        NSLog("printer is connected: \(isConnected)")
        
        var msg = "Printer \(printerName) is not connected"
        
        if !isConnected {
            self.printerName = printerName
            
            findConnectedPrinter { [weak self] bool in
                if let strongSelf = self {
                    strongSelf.isConnected = bool
                    NSLog("Second attempt of checking if printer is connected: \(strongSelf.isConnected)")
                    
                    if !strongSelf.isConnected {
                        
                        DispatchQueue.main.async {
                            strongSelf.initializeBluetooth(timeout: strongSelf.howLongScanning) { result in
                                NSLog("Bluetooth enabled: \(result)")

                                if result {
                                    strongSelf.startScanning()
                                }
                            }
                        }
                    } else {
                        NSLog("invoke from findConnectedPrinter")
                        pluginResult = strongSelf.justPrint(data)
                        DispatchQueue.main.async {
                            strongSelf.commandDelegate!.send(pluginResult, callbackId: object.callbackId)
                        }
                    }
                    return
                }
            }
        } else {
            if self.printerName == printerName {
                pluginResult = justPrint(data)
                DispatchQueue.main.async {
                    self.commandDelegate!.send(pluginResult, callbackId: object.callbackId)
                }
            } else {
                DispatchQueue.main.async {
                    msg += "\nPrinter connected: \(self.printerName ?? "")"
                    self.showAlert(msg)
                    pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: msg)
                    self.commandDelegate!.send(pluginResult, callbackId: object.callbackId)
                }
            }
        }
    }
    
    func justPrint(_ data: String) -> CDVPluginResult? {
        
        var pluginResult : CDVPluginResult?
        var printError: Error?
        
        NSLog("data to print: \(data)")
        
        do {
            let printer = try ZebraPrinterFactory.getInstance(printerConnection)
            let lang = printer.getControlLanguage()
            
            NSLog("printer language: \(lang)")
            
            if lang != PRINTER_LANGUAGE_CPCL {
                let tool = printer.getToolsUtil()
                try tool?.sendCommand(data)
            }
        } catch {
            printError = error
        }
        
        if let error = printError {
            NSLog("error: \(error.localizedDescription)")
            pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: error.localizedDescription)
        } else {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        }
        
        return pluginResult
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
        
        NSLog("current bluetooth connection status: \(currentBTState)")
        
        self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }
}


extension ZebraPluginBtPrint: CBCentralManagerDelegate, CBPeripheralDelegate{

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
        showAlert("Bluetooth is turned off. To connect to Bluetooth devices, turn on Bluetooth in the system settings.")
    }
    
    /// ----------------------- BLUETOOTH MANAGEMENT -----------------------

    func startScanning() {
        if let manager = centralManager, manager.state == .poweredOn {
            manager.scanForPeripherals(withServices: nil, options: nil)
        } else {
            showAlert("Cannot scan, Bluetooth is not powered on.")
        }
    }
    
    // bluetooth status listener
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
        switch central.state {
        case .poweredOn:
            NSLog("Bluetooth on")
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

        // Autoconnect if printerName are available
        if let name = peripheral.name?.lowercased(), self.printerName != nil, name == self.printerName?.lowercased() {
            connectToPeripheral(peripheral)
            return
        }
        
        if let name = peripheral.name?.lowercased(), self.wildcard == nil || name.contains(self.wildcard!.lowercased())
        {
            updateAlertWithPeripheral(peripheral)
        }
        NSLog("BT device found: \(peripheral.identifier.uuidString ) \(peripheral.name ?? "")")
    }
    
    // Disconnect from peripheral
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        
        guard let pname = peripheral.name else {
            NSLog("invalid disconnection")
            return
        }

        NSLog("Disconnected from printer: \(pname)")
        setPluginAsDisconnected()
    }
    
    func setPluginAsDisconnected() {
        connectedPeripheral = nil
        isConnected = false
    }
    
    
    /// ----------------------- DIALOG MANAGEMENT -----------------------
    
    func showDeviceSelectionModal() {
        
        alertController = UIAlertController(title: "Select a device", message: "Select a ZQ610 Zebra printer", preferredStyle: .actionSheet)
        
        let cancelAction = UIAlertAction(title: self.cancelText, style: .cancel) { _ in
            self.alertController = nil // Resetta il riferimento quando l'alert viene chiuso
        }
        alertController?.addAction(cancelAction)
        
        self.viewController.present(alertController!, animated: true, completion: nil)
    }
    
    func initializeBluetooth(timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        let startTime = Date()
        
        func checkBluetoothPeriodically() {
            if currentBTState == .poweredOn {
                
                NSLog("BT is enabled, returning success")
                completion(true)
                return
            }
            
            if Date().timeIntervalSince(startTime) >= timeout {
                NSLog("Timeout reached, bt is still not ready.")
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                checkBluetoothPeriodically()
            }
        }
        
        checkBluetoothPeriodically()
    }

    func updateAlertWithPeripheral(_ peripheral: CBPeripheral) {
        
        guard let name = peripheral.name?.lowercased(), self.wildcard == nil || name.contains(self.wildcard!.lowercased())
                , let alert = alertController else {
            return
        }

        if !alert.actions.contains(where: { $0.title == name }) {
            let action = UIAlertAction(title: name, style: .default, handler: { _ in
                NSLog("Connecting to \(peripheral.name ?? "")")
                self.connectToPeripheral(peripheral)
                // return selected device via callback, deviceSelected is the callbackId in the cordova plugin.

                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: peripheral.name)
                self.commandDelegate!.send(pluginResult, callbackId: "deviceSelected")
        
            })
            alert.addAction(action)
        }
    }

// deviceSelected :
// 1. Get the device name
// 2. Connect to the device
// 3. Send the device name to the cordova plugin
// 4. Close the alert
// 5. Print the data
// 6. Return the result to the cordova plugin

    
    func connectToPeripheral(_ peripheral:CBPeripheral){
        NSLog("Connessione per Nome: \(peripheral)")
        connectedPeripheral = peripheral
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    // Connected to peripheral
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {

        guard let deviceName = peripheral.name else {
            NSLog("cannot get device name from connection")
            return
        }
        
        NSLog("connected with device \(deviceName)")
        
        if deviceName == printerName {
            connectedPeripheral = peripheral

            peripheral.delegate = self
            peripheral.discoverServices(nil)
        } else {
            NSLog("connected device \(deviceName) is not \(printerName ?? "(no name provided)")")
        }
        
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            NSLog("Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            NSLog("No services on device \(peripheral.name ?? "unknown")")
            return
        }
        
        NSLog("Found \(services.count) services for peripheral: \(peripheral.name ?? "Unknown")")
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            NSLog("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            NSLog("No characteristics for service: \(service.uuid)")
            return
        }
        
        NSLog("Found \(characteristics.count) characteristics for service: \(service.uuid)")

        for characteristic in characteristics {
            if characteristic.properties.contains(.write) {
                if let data = self.savedData {
                    let dataToPrint = Data(data.utf8)
                    peripheral.writeValue(dataToPrint, for: characteristic, type: .withResponse)
                    NSLog("Data written to characteristic: \(characteristic.uuid)")
                }
            }
        }
    }
 
}
