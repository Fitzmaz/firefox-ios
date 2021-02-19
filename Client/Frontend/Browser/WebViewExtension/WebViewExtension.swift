//
//  WebViewExtension.swift
//  Client
//
//  Created by zcr on 2021/2/19.
//  Copyright © 2021 Mozilla. All rights reserved.
//

import Foundation
import WebKit

// MARK: network

protocol RequestLoader {
    func send(request: URLRequest, handler: @escaping (Data) -> Void) -> URLSessionTask
}

class SessionManager: NSObject {
    static let shared = SessionManager()
    lazy var session: URLSession = {
        return URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }()
    var datas = [URLSessionTask: Data]()
    var handlers = [URLSessionTask: (Data) -> Void]()
}

extension SessionManager: RequestLoader {
    func send(request: URLRequest, handler: @escaping (Data) -> Void) -> URLSessionTask {
        let task = session.dataTask(with: request)
        handlers[task] = handler
        task.resume()
        return task
    }
}

extension SessionManager: URLSessionTaskDelegate, URLSessionDataDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        //TODO: handle error
        if let handler = handlers[task],
           let data = datas[task] {
            handler(data)
            handlers[task] = nil
            datas[task] = nil
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        datas[dataTask] = Data()
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        datas[dataTask]?.append(data)
    }
}

// MARK: JSAPIManager

typealias APIHandler = (_ data: Any, _ context: Any, _ callback: @escaping (Any) -> Void) -> Void

final class JSAPIManager {
    static let shared = JSAPIManager()
    lazy var apis = [String: [String: Any]]()

    func registerAPI(_ name: String, handler: @escaping APIHandler, keepAlive: Bool) {
        let api: [String: Any] = [
            "name": name,
            "handler": handler,
            "keepAlive": keepAlive
        ]
        apis[name] = api
    }

    func invokeAPI(_ name: String, data: Any, context: Any, bridgeHandler: @escaping (Any, Bool) -> Void) {
        if let api = apis[name],
           let handler = api["handler"] as? APIHandler,
           let keepAlive = api["keepAlive"] as? Bool {
            handler(data, context) { (response: Any) -> Void in
                bridgeHandler(response, keepAlive)
            }
        }
    }
}

// MARK: WebViewExtension

@available(iOS 14.0, *)
protocol WebViewExtension {
    var userScripts: [WKUserScript] { get }
    var handlers: [String: WKScriptMessageHandler] { get }
    var world: WKContentWorld { get }
}

@available(iOS 14.0, *)
extension WKUserContentController {
    func addExtension(_ ext: WebViewExtension) {
        for script in ext.userScripts {
            self.addUserScript(script)
        }
        for (name, handler) in ext.handlers {
            self.add(handler, contentWorld: ext.world, name: name)
        }
    }
}

// MARK: TMWebViewExtension

let JSBridgeJS = """
;(function() {

    if (window.JSBridge) {
        return;
    }

    window.JSBridge = {
        invoke: invoke,
        _handleMessage: _handleMessage,
    };

    var callbacks = {};
    var uniqueId = 1;

    function invoke(name, data, callback) {
        data = data || {};
        data = JSON.parse(JSON.stringify(data));
        var callbackId = 'cb_'+(uniqueId++)+'_'+new Date().getTime();
        if (callback) {
            callbacks[callbackId] = callback;
        }
        var message = {
            name: name,
            data: data,
            callbackId: callbackId
        };
        window.webkit.messageHandlers.jsbridge.postMessage(message);
    }

    function _handleMessage(message) {
        if (message.callbackId) {
            var callback = callbacks[message.callbackId];
            if (!callback) {
                return;
            }
            callback(message.responseData);
            if (!message.keepAlive) {
                delete callbacks[message.callbackId];
            }
        }
    }

})();
"""

let TMInterfaceJS = """
;(function() {

    window.GM_xmlhttpRequest = xmlhttpRequest;

    function xmlhttpRequest(details) {
        let { method, url, headers, data, responseType, onload } = details;
        JSBridge.invoke('xhr', { url, method, headers, body: data }, function (res) {
            let { responseText } = res.data;
            onload({ responseText });
        });
    }

})();
"""

var XHRHandler: APIHandler = { (data, context, callback) in
    guard let params = data as? [String: Any],
          let method = params["method"] as? String,
          let urlString = params["url"] as? String,
          let url = URL(string: urlString) else {
        return
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    if let headers = params["headers"] as? [String: String] {
        for header in headers {
            let field = header.key
            let value = header.value
            request.addValue(value, forHTTPHeaderField: field)
        }
    }
    if let body = params["body"] as? String {
        request.httpBody = body.data(using: .utf8)
    }
    SessionManager.shared.send(request: request) { (result) in
        let text = String(data: result, encoding: .utf8)
        let response = [
            "data": [
                "responseText": text
            ]
        ]
        callback(response)
    }
}

@available(iOS 14.0, *)
class TMWebViewExtension: NSObject {
    weak var webView: WKWebView?

    override init() {
        JSAPIManager.shared.registerAPI("xhr", handler: XHRHandler, keepAlive: true)
    }
}

@available(iOS 14.0, *)
extension TMWebViewExtension: WebViewExtension {
    var userScripts: [WKUserScript] {
        return [JSBridgeJS, TMInterfaceJS].map { (script: String) -> WKUserScript in
            WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: self.world)
        }
    }
    var handlers: [String: WKScriptMessageHandler] {
        return ["jsbridge": self]
    }
    var world: WKContentWorld {
//        WKContentWorld.world(name: "TM")
//        .defaultClient
        .page
    }
}

@available(iOS 14.0, *)
extension TMWebViewExtension: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
           let name = body["name"] as? String,
           let data = body["data"],
           let callbackId = body["callbackId"] as? String else {
            return
        }
        JSAPIManager.shared.invokeAPI(name, data: data, context: self) { (response, keepAlive) in
            let dict = [
                "responseData": response,
                "keepAlive": keepAlive,
                "callbackId": callbackId
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
                print("data serialization failed")
                return
            }
            guard let message = String(data: data, encoding: .utf8) else { return }
            let script = "JSBridge._handleMessage(\(message))"
            self.webView?.evaluateJavaScript(script, in: nil, in: self.world, completionHandler: nil)
        }
    }
}
