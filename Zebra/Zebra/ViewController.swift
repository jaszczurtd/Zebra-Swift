//
//  ViewController.swift
//  Zebra
//
//  Created by Guillermo Garcia on 30/04/17.
//  Copyright © 2017 Guillermo Garcia. All rights reserved.
//

import UIKit
import ExternalAccessory

class ViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Dodatkowa konfiguracja po załadowaniu widoku.
        let thread = Thread(target: self, selector: #selector(start), object: nil)
        thread.start()
    }
    
    @objc func start() {
        EAAccessoryManager.shared().registerForLocalNotifications()
        
        let bluetoothPrinters = EAAccessoryManager.shared().connectedAccessories
        guard let printer = bluetoothPrinters.first else {
            print("No printers connected")
            return
        }
        
        autoreleasepool {
            guard let connection = MfiBtPrinterConnection(serialNumber: printer.serialNumber) else {
                    print("Failed to create printer connection")
                    return
                }
            
            let open = connection.open()
            if open {
                do {
                    let printer = try ZebraPrinterFactory.getInstance(connection)
                    let lang = printer.getControlLanguage()
                    
                    if lang != PRINTER_LANGUAGE_CPCL {
                        let tool = printer.getToolsUtil()
                        try tool?.sendCommand("^XA^FO17,16^GB379,371,8^FS^FT65,255^A0N,135,134^FDMEMO^FS^XZ")
                    }
                } catch {
                    print("Error: \(error)")
                }
                connection.close()
            }
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Usuń zasoby, które mogą być odtworzone.
    }
}
