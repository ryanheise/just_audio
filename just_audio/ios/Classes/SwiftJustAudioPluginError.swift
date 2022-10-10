//
//  PluginErrors.swift
//  just_audio
//
//  Created by kuama on 22/08/22.
//

import Foundation

enum SwiftJustAudioPluginError: Error {
    case notSupportedError(value: Any, message: String)
    case notInitializedError(message: String)
    case notImplementedError(message: String)
    case platformAlreadyExists

    public var flutterError: FlutterError {
        switch self {
        case let .notSupportedError(value: value, message: message):
            return FlutterError(code: "400", message: "Requested \(value) is not supported\n\(message)", details: nil)
        case let .notInitializedError(message: message):
            return FlutterError(code: "403", message: message, details: nil)
        case let .notImplementedError(message: message):
            return FlutterError(code: "500", message: message, details: nil)
        case .platformAlreadyExists:
            return FlutterError(code: "503", message: "Platform player already exists", details: nil)
        }
    }
}

extension Error {
    func toFlutterError(_ details: String?) -> FlutterError {
        return FlutterError(code: "500", message: localizedDescription, details: details)
    }
}

extension FlutterError {
    func toMap() -> [String: Any?] {
        return [
            "code": code,
            "message": message,
            "description": description,
        ]
    }
}
