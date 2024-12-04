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

class ViewController: UIViewController, UITextFieldDelegate {
    
    var plugin : ZebraPluginBtPrint?
    
    private let printButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let textField = UITextField()

    // Zamykanie klawiatury po kliknięciu Return
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder() // Zamyka klawiaturę
        return true
    }

    // Zamykanie klawiatury po kliknięciu w tło
    @objc func dismissKeyboard() {
        view.endEditing(true)
    }
    
    func setButtonLoading(isLoading: Bool) {
        if isLoading {
            printButton.setTitle("", for: .normal)
            activityIndicator.startAnimating()
            printButton.isEnabled = false
        } else {
            activityIndicator.stopAnimating()
            printButton.setTitle("Print", for: .normal)
            printButton.isEnabled = true
        }
    }
    
    @objc func printButtonTapped() {
        NSLog("Print button tapped!")
        
        setButtonLoading(isLoading: true)
        let text = "^XA^FO17,16^GB379,371,8^FS^FT65,255^A0N,135,134^FD" + (self.textField.text ?? "ab") + "^FS^XZ"
        
        DispatchQueue.global().async {
            
            self.testPrint(mac: "ZQ610-A", data: text, caseValue: 1)

            DispatchQueue.main.async {
                self.setButtonLoading(isLoading: false)
                NSLog("Print operation completed!")
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        plugin = ZebraPluginBtPrint(viewController: self)
        
        NSLog("starting...")

        //testInitialize(delay: 15000, wildcard: "*", printerName: "ZQ610-A", cancelButtonName: "Poniechaj", howLong: 30)
        
        view.backgroundColor = .gray
        
        textField.placeholder = "Enter text here"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.autocapitalizationType = .none
        textField.text = "aa"
        textField.delegate = self
        
        printButton.setTitle("Print", for: .normal)
        printButton.backgroundColor = .systemBlue
        printButton.setTitleColor(.white, for: .normal)
        printButton.layer.cornerRadius = 8
        printButton.translatesAutoresizingMaskIntoConstraints = false
        
        printButton.addTarget(self, action: #selector(printButtonTapped), for: .touchUpInside)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        
        printButton.addSubview(activityIndicator)

        view.addSubview(textField)
        view.addSubview(printButton)

        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            textField.bottomAnchor.constraint(equalTo: printButton.topAnchor, constant: -20),
            textField.widthAnchor.constraint(equalToConstant: 200),
            textField.heightAnchor.constraint(equalToConstant: 40)
        ])

        NSLayoutConstraint.activate([
            printButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            printButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            printButton.widthAnchor.constraint(equalToConstant: 120),
            printButton.heightAnchor.constraint(equalToConstant: 50)
        ])

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: printButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: printButton.centerYAnchor)
        ])
        
        
        
        
        /*
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.testPrint(mac: "ZQ610-A", data: "^XA^FO17,16^GB379,371,8^FS^FT65,255^A0N,135,134^FDaa^FS^XZ", caseValue: 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    self.testPrint(mac: "ZQ610-A", data: "^XA^FO17,16^GB379,371,8^FS^FT65,255^A0N,135,134^FDaa^FS^XZ", caseValue: 1)
                }
        }
         
         */
        
        //testStatus()
        
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
