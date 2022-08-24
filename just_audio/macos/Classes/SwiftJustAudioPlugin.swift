import AppKit
import FlutterMacOS

public class SwiftJustAudioPlugin: NSObject, FlutterPlugin {
    var players: [String: JustAudioPlayer] = [:]
    let registrar: FlutterPluginRegistrar

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.ryanheise.just_audio.methods", binaryMessenger: registrar.messenger)
        let instance = SwiftJustAudioPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            let request = call.arguments as! [String: Any]
            let playerId = request["id"] as! String

            let loadConfiguration = request["audioLoadConfiguration"] as? [String: Any] ?? [:]
            let audioEffects = request["darwinAudioEffects"] as? [[String: Any]] ?? []
            if players[playerId] != nil {
                let flutterError = FlutterError(code: "error", message: "Platform player already exists", details: nil)
                result(flutterError)
            } else {
                let methodChannel = FlutterMethodChannel(name: String(format: "com.ryanheise.just_audio.methods.%@", playerId), binaryMessenger: registrar.messenger())
                let eventChannel = BetterEventChannel(name: String(format: "com.ryanheise.just_audio.events.%@", playerId), messenger: registrar.messenger())
                let dataChannel = BetterEventChannel(name: String(format: "com.ryanheise.just_audio.data.%@", playerId), messenger: registrar.messenger())

                let player = JustAudioPlayer(
                    registrar: registrar,
                    playerId: playerId,
                    loadConfiguration: loadConfiguration,
                    audioEffects: audioEffects,
                    methodChannel: methodChannel,
                    eventChannel: eventChannel,
                    dataChannel: dataChannel
                )
                players[playerId] = player
                result(nil)
            }
        case "disposePlayer":
            let request = call.arguments as! [String: Any]
            let playerId = request["id"] as! String
            players.removeValue(forKey: playerId)?.dispose()
            result([:])
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
