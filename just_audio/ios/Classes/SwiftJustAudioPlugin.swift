import AVFAudio
import Flutter
import UIKit

/**
 TODOS
 - [do we really need mappings???]
 - expose missing feature from kmusicswift
 - hook effects on load
 - check if we need to map responses
 - expose streams
 - add effects on audiosource on dart layer
 - add effects on audiosource mapping
 */

@available(iOS 13.0, *)
public class SwiftJustAudioPlugin: NSObject, FlutterPlugin {
    var players: [String: SwiftPlayer] = [:]
    let registrar: FlutterPluginRegistrar
    let engine: AVAudioEngine!

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        engine = AVAudioEngine()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.ryanheise.just_audio.methods", binaryMessenger: registrar.messenger())
        let instance = SwiftJustAudioPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            let command: SwiftJustAudioPluginCommand = SwiftJustAudioPluginCommand.parse(call.method)

            switch command {
            case .`init`:
                try onInit(request: call.arguments as! [String: Any])
                result(nil)
            case .disposePlayer:
                try onDisposePlayer(request: call.arguments as! [String: Any])
                result([:])
            case .disposeAllPlayers:
                onDisposeAllPlayers()
                result([:])
            }
        } catch let error as SwiftJustAudioPluginError {
            result(error.flutterError)
        } catch {
            // TODO: remove
            print("command: \(String(describing: call.method))")
            print("request: \(String(describing: call.arguments))")
            print(error)

            result(FlutterError(code: "500", message: error.localizedDescription, details: nil))
        }
    }
}

// MARK: - SwiftJustAudioPlugin commands handles

@available(iOS 13.0, *)
extension SwiftJustAudioPlugin {
    private func onInit(request: [String: Any?]) throws {
        guard let id = request["id"] as? String else {
            return
        }

        let playerId = id

        guard !players.keys.contains(playerId) else {
            throw SwiftJustAudioPluginError.platformAlreadyExists
        }

        var effectsRaw: [[String: Any?]] = request.keys.contains("darwinAudioEffects") ? (request["darwinAudioEffects"] as! [[String: Any?]]) : []
        
        var equalizerRaw = effectsRaw.filter({ rawEffect in
            return (rawEffect["type"] as! String) == "DarwinEqualizer"
        }).first
        
        // exclude equalizer
        effectsRaw = effectsRaw.filter({ rawEffect in
            return (rawEffect["type"] as! String) != "DarwinEqualizer"
        })

        var shouldWriteOutputToFile = false
        if let audioLoadConfiguration = request["audioLoadConfiguration"] as? [String: Any] {
            if let darwinLoadControl = audioLoadConfiguration["darwinLoadControl"] as? [String: Any] {
                shouldWriteOutputToFile = (darwinLoadControl["writeFinalOutputToFile"] as? Bool) ?? false
            }
        }

        let player = SwiftPlayer.Builder()
            .withAudioEffects(effectsRaw.map { $0.audioEffect })
            .withPlayerId(id)
            .withMessenger(messenger: registrar.messenger())
            .withAudioEngine(engine)
            .withShouldWriteOutputToFile(shouldWriteOutputToFile)
            .withEqualizer(try equalizerRaw?.equalizer)
            .build()

        players[playerId] = player
    }

    private func onDisposePlayer(request: [String: Any]) throws {
        guard let id = request["id"] as? String else {
            return
        }

        if let player = players[id] {
            player.dispose()
            players.removeValue(forKey: id)?.dispose()
            engine.stop()
        }
    }

    private func onDisposeAllPlayers() {
        players.forEach { _, player in player.dispose() }
        players.removeAll()
        engine.stop()
    }
}
