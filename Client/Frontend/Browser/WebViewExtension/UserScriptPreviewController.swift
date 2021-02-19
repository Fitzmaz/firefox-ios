//
//  UserScriptPreviewController.swift
//  Client
//
//  Created by zcr on 2021/2/19.
//  Copyright © 2021 Mozilla. All rights reserved.
//

import Foundation
import WebKit

class UserScriptPreviewController: UIViewController {
    fileprivate let url: URL
    fileprivate var webView: WKWebView
    
    public init(url: URL) {
        self.url = url
        
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = webView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        reloadData()
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "import",
            style: .plain,
            target: self,
            action: #selector(importScript)
        )
        
        if let navigationController = navigationController as? ThemedNavigationController {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: .AppSettingsDone,
                style: .done,
                target: navigationController, action: #selector(navigationController.done)
            )
        }
        
    }
    
    private func reloadData() {
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    
    @objc func importScript() {
        print(url.absoluteString)
//        let fileName = url.lastPathComponent
//        let destinationSearchPath = FileManager.SearchPathDirectory.cachesDirectory
//        guard let cachesURL = try? FileManager.default.url(for: destinationSearchPath, in: .userDomainMask, appropriateFor: nil, create: true) else {
//            print("Unable to get destination path \(destinationSearchPath) to import script \(fileName)")
//            return
//        }
//        let userScriptsRoot = cachesURL.appendingPathComponent("UserScripts")
//        let destURL = userScriptsRoot.appendingPathComponent(fileName)
//        try? FileManager.default.copyItem(at: url, to: destURL)
    }
    
    public func presentPreview(_ presentor: UIViewController, animated: Bool) {
        let navigationController = ThemedNavigationController(rootViewController: self)
        presentor.present(navigationController, animated: animated, completion: nil)
    }
}
