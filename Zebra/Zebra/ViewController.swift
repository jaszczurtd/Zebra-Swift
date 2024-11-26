//
//  ViewController.swift
//  Zebra
//
//  Created by Guillermo Garcia on 30/04/17.
//  Copyright © 2017 Guillermo Garcia. All rights reserved.
//

import UIKit
import ExternalAccessory
import Foundation
import CoreBluetooth
import UIKit

class ViewController: UIViewController {
    
    var plugin : ZebraPluginBtPrint?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Additional configuration after loading the view.
        
        plugin = ZebraPluginBtPrint(viewController: self)
        
        NSLog("starting...")
        
        //testInitialize(delay: 15000, wildcard: "*", printerName: "ZQ610-A", cancelButtonName: "Poniechaj", howLong: 30)
        
        testPrint(mac: "ZQ610-A", data: "^XA^FO17,16^GB379,371,8^FS^FT65,255^A0N,135,134^FDaa^FS^XZ", caseValue: 1)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.testPrint(mac: "ZQ610-A", data: "^XA^FO17,16^GB379,371,8^FS^FT65,255^A0N,135,134^FDaa^FS^XZ", caseValue: 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    self.testPrint(mac: "ZQ610-A", data: "^XA^FO17,16^GB379,371,8^FS^FT65,255^A0N,135,134^FDaa^FS^XZ", caseValue: 1)
                }
        }
        
        testStatus()
        
        NSLog("done")
    }
    
    func testInitialize(delay: Int, wildcard: String, printerName: String, cancelButtonName: String, howLong: Int) {
        let command = CDVInvokedUrlCommand(arguments: [delay, wildcard, printerName, cancelButtonName, howLong], methodName: "initialize")
        plugin?.initialize(command)
    }
    
    func testPrint(mac: String, data: String, caseValue: Int) {
        let command = CDVInvokedUrlCommand(arguments: [mac, data, caseValue], methodName: "print")
        plugin?.print(command)
    }
    
    func testStatus() {
        let command = CDVInvokedUrlCommand(arguments: [], methodName: "status")
        plugin?.status(command)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Remove resources that can be recreated.
    }
}
