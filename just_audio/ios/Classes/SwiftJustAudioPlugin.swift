import Flutter
import UIKit

public class SwiftJustAudioPlugin: NSObject, FlutterPlugin {
    var players: [String: AudioPlayer] = [:]
    let registrar: FlutterPluginRegistrar
    
    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.ryanheise.just_audio.methods", binaryMessenger: registrar.messenger())
        let instance = SwiftJustAudioPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            let request = call.arguments as! Dictionary<String, Any>
            let playerId = request["id"] as! String
            let loadConfiguration = request["audioLoadConfiguration"] as? Dictionary<String, Any> ?? [:]
            if players[playerId] != nil {
                let flutterError = FlutterError(code: "error", message: "Platform player already exists", details: nil)
                result(flutterError)
            } else {
                let player = AudioPlayer(registrar: self.registrar, playerId: playerId, loadConfiguration: loadConfiguration)
                players[playerId] = player
                result(nil)
            }
            break
        case "disposePlayer":
            let request = call.arguments as! Dictionary<String, Any>
            let playerId = request["id"] as! String
            players.removeValue(forKey: playerId)?.dispose()
            result([:])
            break
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
