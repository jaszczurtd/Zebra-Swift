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
    
    var currentBTState: CBManagerState = .poweredOff
    var savedData: String?

    var cancelText: String = "Cancel"
    var howLongScanning: TimeInterval = 20
    var delayTime: Int = 0
    var howLongKeepPrinterConnection: Double = 10.0
    
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
    
    /**
     Initializes the printer connection process.
     This method is responsible for initiating the process of finding and connecting to a Zebra printer. It calls `findConnectedPrinter`,
     a method that searches for a connected printer that supports the specified protocol string. If a compatible printer is found and successfully connected,
     the `isConnected` property of the class is updated accordingly.
     */
    @objc func initialize(_ command: CDVInvokedUrlCommand) {
        
        deb("initialize function called")
        
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
        
        deb("\(command.arguments[1])")
        deb("Wildcard: \(self.wildcard ?? "N.D")")
        deb("PrinterName: \(self.printerName ?? "N.D")")
        deb("CancelText: \(self.cancelText)")
        deb("How long scanning: \(howLongScanning)")
    
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
        initializeBluetooth(timeout: howLongScanning) { result in
            if result {
                guard let printerName = command.arguments[0] as? String else {
                    DispatchQueue.main.async {
                        self.showAlert("invalid printer name")
                    }
                    return
                }
                self.deb("selected printer name: \(printerName)")
                self.printerName = printerName
                
                guard let data = command.arguments[1] as? String else {
                    DispatchQueue.main.async {
                        self.showAlert("invalid printer data")
                    }
                    return
                }
                self.savedData = data
                self.startScanning()
                
                //DispatchQueue.global(qos: .userInitiated).async {
                //    self.printPreparations(object: data)
                //}
            } else {
                self.showBTErrorMessage()
            }
        }
    }
    
    @objc func printPreparations(object: CDVInvokedUrlCommand) {
        var pluginResult : CDVPluginResult?
        
        // Log the start of the print function
        deb("print function called")
        
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
            deb("Bluetooth is ON, printing...")
        @unknown default:
            deb("unsupported bluetooth state: \(currentBTState)")
            return
        }
        
        deb("printer is connected: \(isConnected)")
        var msg = "Printer is not connected"
        
        if !isConnected {
            
            findConnectedPrinter { [weak self] bool in
                if let strongSelf = self {
                    strongSelf.isConnected = bool
                    strongSelf.deb("Second attempt of checking if printer is connected: \(strongSelf.isConnected)")
                    
                    if !strongSelf.isConnected {
                        
                        DispatchQueue.main.async {
                            strongSelf.initializeBluetooth(timeout: strongSelf.howLongScanning) { result in
                                strongSelf.deb("Bluetooth enabled: \(result)")

                                if result {
                                    strongSelf.startScanning()
                                }
                            }
                        }
                    } else {
                        strongSelf.deb("invoke from findConnectedPrinter")
                        pluginResult = strongSelf.justPrint(strongSelf.savedData)
                        DispatchQueue.main.async {
                            strongSelf.commandDelegate!.send(pluginResult, callbackId: object.callbackId)
                        }
                    }
                    return
                }
            }
        } else {
            if self.printerName == printerName {
                pluginResult = justPrint(savedData)
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
    
    func justPrint(_ data: String?) -> CDVPluginResult? {
        
        var pluginResult : CDVPluginResult?
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
            deb("error: \(error.localizedDescription)")
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
        
        deb("current bluetooth connection status: \(currentBTState)")
        
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
        
        //if centralManager.isScanning {
        //    deb("Bluetooth scanning is already in progress.")
        //    return
        //}
        if let manager = centralManager, manager.state == .poweredOn {
            deb("started scanning for peripherials")
            manager.scanForPeripherals(withServices: nil, options: nil)
        } else {
            showAlert("Cannot scan, Bluetooth is not powered on.")
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

        if let cp = connectedPeripheral {
            reconnectToPeripheral()
            return
        }
        
        deb("BT device found: \(peripheral.identifier.uuidString ) \(peripheral.name ?? "") and looking for: \(self.printerName?.lowercased() ?? "no name")")
        
        // Autoconnect if printerName are available
        if let name = peripheral.name?.lowercased(), self.printerName != nil, name == self.printerName?.lowercased() {
            
            deb("Making connection to: \(peripheral)")
            connectedPeripheral = peripheral
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
            deb("cannot get device name from connection")
            return
        }
        
        deb("connected with device \(deviceName)")
        
        if deviceName == printerName {
            connectedPeripheral = peripheral

            peripheral.delegate = self
            peripheral.discoverServices(nil)
        } else {
            deb("connected device \(deviceName) is not \(printerName ?? "(no name provided)")")
        }
        
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            deb("Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            deb("No services on device \(peripheral.name ?? "unknown")")
            return
        }
        
        deb("Found \(services.count) services for peripheral: \(peripheral.name ?? "Unknown")")
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            deb("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            deb("No characteristics for service: \(service.uuid)")
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
                    
                    break

                } else {
                    deb("no print data!")
                }
            }
        }
    }
 
}
