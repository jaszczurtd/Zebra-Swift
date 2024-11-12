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

    var cancelText: String = "Cancel"
    
    @objc private func connectToPrinter( completion: (Bool) -> Void) {
        printerConnection = MfiBtPrinterConnection(serialNumber: serialNumber)
        printerConnection?.open()
        completion(true)
    }

    @objc func findConnectedPrinter(completion: (Bool) -> Void) {
        let manager = EAAccessoryManager.shared()
        let connectedDevices = manager.connectedAccessories
        var deviceConnected = false
        
        if connectedDevices.isEmpty {
            deviceConnected = false
            completion(false)
            return
        }
        
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
            initializeBluetooth()
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
        
        //
        // Load parameters
        // parameters : Wildcard | Pattern for name search
        let wildcardParam: String? = command.arguments.count > 1 ? (command.arguments[1] as? String ) : nil
        self.wildcard = wildcardParam != "" ? wildcardParam : nil

        // parameters : Printer name | Name of the printer for a direct bluetooth connection
        let printerNameParam: String? = command.arguments.count > 2 ?  (command.arguments[2] as! String) : nil
        self.printerName = printerNameParam != "" ? printerNameParam : nil

        // parameters : Cancel button name | Name of the button for close the bluetooth modals
        let cancelButtonParam: String = command.arguments.count > 3 ? (command.arguments[3] as! String ) : "Cancel"
        self.cancelText = cancelButtonParam

        NSLog("\(command.arguments[1])")
        NSLog("Wildcard: \(self.wildcard ?? "N.D")")
        NSLog("PrinterName: \(self.printerName ?? "N.D")")
        NSLog("CancelText: \(self.cancelText)")
    
        findConnectedPrinter { [weak self] bool in
            if let strongSelf = self {
                strongSelf.isConnected = bool
            }
        }
     }
    
    @objc func print(_ command: CDVInvokedUrlCommand) {
        let thread = Thread(target: self, selector: #selector(printPreparations(object:)), object: command)
        thread.start()
    }
    
    @objc func printPreparations(object: CDVInvokedUrlCommand) {
        var pluginResult : CDVPluginResult?
        
        // Log the start of the print function
        NSLog("BT_PRINT_DEBUG: print function called")
        
        guard let printerName = object.arguments[0] as? String else {
            DispatchQueue.main.async {
                self.showAlert("invalid printer name")
            }
            return
        }

        NSLog("selected printer name: \(printerName)")
        
        if !self.isConnected {
            self.printerName = printerName
            
            findConnectedPrinter { [weak self] bool in
                if let strongSelf = self {
                    strongSelf.isConnected = bool
                    if !strongSelf.isConnected {
                        let msg = "Printer \(printerName) is not connected"
                        pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: msg)
                        DispatchQueue.main.async {
                            strongSelf.showAlert(msg)
                            strongSelf.commandDelegate!.send(pluginResult, callbackId: object.callbackId)
                        }
                    } else {
                        NSLog("invoke from findConnectedPrinter")
                        strongSelf.justPrint(object)
                    }
                    return
                }
            }
        } else {
            justPrint(object)
        }
    }
    
    func justPrint(_ object: CDVInvokedUrlCommand) {
        
        var pluginResult : CDVPluginResult?
        var printError: Error?
        
        guard let data = object.arguments[1] as? String else {
            DispatchQueue.main.async {
                self.showAlert("invalid printer data")
            }
            return
        }
        
        NSLog("data to print: \(data)")
        
        printerConnection?.close()
        printerConnection?.open()
        
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
        
        DispatchQueue.main.async {
            self.commandDelegate!.send(pluginResult, callbackId: object.callbackId)
        }
    }
    
    /**
     Generar bluetooth connection status callback function
     */
    @objc func status(_ command: CDVInvokedUrlCommand) {
        var pluginResult : CDVPluginResult?
        
        if self.isConnected {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        } else {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR)
        }
        
        NSLog("current bluetooth connection status: \(self.isConnected)")
        
        self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }
}


extension ZebraPluginBtPrint: CBCentralManagerDelegate, CBPeripheralDelegate{

    func showAlert(_ title: String) {
        let alert = UIAlertController(title: "Info", message: title, preferredStyle: .alert)
        
        let okAction = UIAlertAction(title: cancelText, style: .default, handler: nil)
        alert.addAction(okAction)
        
        self.viewController.present(alert, animated: true, completion: nil)
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
            startScanning()
        case .poweredOff:
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
    // Autoconnect if macaddress are available
    //if let macAddress = printerMACAddress, peripheral.identifier.uuidString == macAddress {
    //  connectedPeripheral = peripheral
    //  centralManager.stopScan()
    //  centralManager.connect(peripheral, options: nil)
    //}
    }
    
    // Connected to peripheral
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        guard let pname = peripheral.name, let pservices = peripheral.services else {
            NSLog("invalid connection")
            return
        }
        
        NSLog("Connected to printer: \(pname) \(pservices)")
        peripheral.delegate = self
        self.connectedPeripheral = peripheral
        // Check with service uuid
        //peripheral.discoverServices([serviceUUID])
    }

    // Disconnect from peripheral
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        
        guard let pname = peripheral.name else {
            NSLog("invalid disconnection")
            return
        }

        NSLog("Disconnected from printer: \(pname)")
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
    
    func initializeBluetooth(){
        centralManager = CBCentralManager(delegate: self, queue: nil)
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        if(self.printerName == nil){ // Autoconnect if printerName is available
            self.showDeviceSelectionModal()
        }
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
        NSLog("Connessione per Nome")
        connectedPeripheral = peripheral
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
        printToConnectedPeripheral(data: "pippobaudo", peripheral: self.connectedPeripheral!)
    }
    
    // print data
    
    // Funzione per stampare una volta connessa alla periferica
    // private func printToConnectedPeripheral(data: String, peripheral: CBPeripheral) {
    //   NSLog("Start Print....")
    //     guard let services = peripheral.services else {return }
    //     let characteristic = services[0].characteristics?[0]
    //     if(characteristic != nil) {
    //         let dataToPrint = Data(data.utf8)
    //         peripheral.writeValue(dataToPrint, for: characteristic!, type: .withoutResponse)
    //     }
    // }
    private func printToConnectedPeripheral(data: String, peripheral: CBPeripheral) {
    NSLog("Start Print....")
    
    guard let services = peripheral.services else {
        NSLog("No services found for peripheral: \(peripheral)")
        return
    }
    NSLog("Found \(services.count) services for peripheral: \(peripheral)")
    
    let characteristic = services[0].characteristics?[0]
    if characteristic != nil {
        NSLog("Using characteristic: \(String(describing: characteristic))")
        
        let dataToPrint = Data(data.utf8)
        NSLog("Data to print: \(dataToPrint)")
        
        peripheral.writeValue(dataToPrint, for: characteristic!, type: .withoutResponse)
        NSLog("Data written to peripheral: \(peripheral)")
    } else {
        NSLog("No characteristic found in the first service for peripheral: \(peripheral)")
    }
}
 
}
