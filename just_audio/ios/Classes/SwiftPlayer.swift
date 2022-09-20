import AVFoundation
import Flutter
import kMusicSwift

/**
 TODOS
 - hook effects on load
 - check for equalizer on load
 - add effects on audiosource mapping
 - add effects on audiosource on dart layer
 - handle equalizer commands
 - map equalizer commands
 - expose streams
 */
@available(iOS 13.0, *)
internal class SwiftPlayer: NSObject {
    let playerId: String
    let audioEffects: [AudioEffectMessage]

    let methodChannel: FlutterMethodChannel
    let eventChannel: BetterEventChannel
    let dataChannel: BetterEventChannel

    var player: JustAudioPlayer!
    private var engine: AVAudioEngine!

    class Builder {
        private var registrar: FlutterPluginRegistrar!
        private var playerId: String!
        private var loadConfiguration: LoadControlMessage!
        private var audioEffects: [AudioEffectMessage]!
        private var methodChannel: FlutterMethodChannel!
        private var eventChannel: BetterEventChannel!
        private var dataChannel: BetterEventChannel!
        private var engine: AVAudioEngine!

        func withRegistrar(_ registrar: FlutterPluginRegistrar) -> Builder {
            self.registrar = registrar
            return self
        }

        func withPlayerId(_ playerId: String) -> Builder {
            self.playerId = playerId
            return self
        }

        func withLoadConfiguration(_ loadConfiguration: LoadControlMessage) -> Builder {
            self.loadConfiguration = loadConfiguration
            return self
        }

        func withAudioEffects(_ audioEffects: [AudioEffectMessage]) -> Builder {
            self.audioEffects = audioEffects
            return self
        }

        func withMethodChannel(_ methodChannel: FlutterMethodChannel) -> Builder {
            self.methodChannel = methodChannel
            return self
        }

        func withEventChannel(_ eventChannel: BetterEventChannel) -> Builder {
            self.eventChannel = eventChannel
            return self
        }

        func withDataChannel(_ dataChannel: BetterEventChannel) -> Builder {
            self.dataChannel = dataChannel
            return self
        }

        func withAudioEngine(_ engine: AVAudioEngine) -> Builder {
            self.engine = engine
            return self
        }

        func build() -> SwiftPlayer {
            return SwiftPlayer(
                registrar: registrar,
                playerId: playerId,
                loadConfiguration: loadConfiguration,
                audioEffects: audioEffects,
                engine: engine,
                methodChannel: methodChannel,
                eventChannel: eventChannel,
                dataChannel: dataChannel
            )
        }
    }

    private init(
        registrar _: FlutterPluginRegistrar,
        playerId: String,
        loadConfiguration _: LoadControlMessage,
        audioEffects: [AudioEffectMessage],
        engine: AVAudioEngine,
        methodChannel: FlutterMethodChannel,
        eventChannel: BetterEventChannel,
        dataChannel: BetterEventChannel
    ) {
        self.playerId = playerId
        self.audioEffects = audioEffects
        self.engine = engine

        self.methodChannel = methodChannel
        self.eventChannel = eventChannel
        self.dataChannel = dataChannel

        methodChannel.setMethodCallHandler { call, result in
            self.handleMethodCall(call: call, result: result)
        }

        super.init()
    }

    func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            let command = try SwiftPlayerCommand.parse(call.method)

            let request = call.arguments as! [String: Any]

            // ensure inner instance
            if player == nil {
                player = JustAudioPlayer(engine: engine)
            }

            switch command {
            case .load:
                let message = AudioSourceMessage.buildFrom(map: request["audioSource"] as! [String: Any])

                try onLoad(message: message)
            case .play:
                try player.play()
            case .pause:
                player.pause()
            case .seek:
                let time = Util.timeFrom(microseconds: request["position"] as! Int64)
                player.seek(second: time.seconds)
            case .setVolume:
                try player.setVolume(Float(request["volume"] as! Double))
            case .setSpeed:
                try player.setSpeed(Float(request["speed"] as! Double))
            case .setPitch:
                throw SwiftJustAudioPluginError.notImplementedError(message: call.method)
            case .setSkipSilence:
                // TODO: this is supported in SwiftAudioPlayer but not exposed in JustAudioPlayer
                throw SwiftJustAudioPluginError.notImplementedError(message: call.method)
            case .setLoopMode:
                player.setLoopMode(Util.loopModeFrom(request["loopMode"] as! Int))
            case .setShuffleMode:
                player.setShuffleModeEnabled(Util.parseShuffleModeEnabled(request["shuffleMode"] as! Int))
            case .setShuffleOrder:
                let message = AudioSourceMessage.buildFrom(map: request["audioSource"] as! [String: Any])

                guard let concatenating = message as? ConcatenatingAudioSourceMessage else {
                    return
                }

                try onSetShuffleOrder(index: 0, order: concatenating.shuffleOrder)

            case .setAutomaticallyWaitsToMinimizeStalling:
                // android is still to be implemented too
                throw SwiftJustAudioPluginError.notImplementedError(message: call.method)
            case .setCanUseNetworkResourcesForLiveStreamingWhilePaused:
                // android is still to be implemented too
                throw SwiftJustAudioPluginError.notImplementedError(message: call.method)
            case .setPreferredPeakBitRate:
                // android is still to be implemented too
                throw SwiftJustAudioPluginError.notImplementedError(message: call.method)
            case .dispose:
                player.stop()
            case .concatenatingInsertAll:

                let message = ConcatenatingInsertAllMessage.fromMap(map: request)

                // TODO: Not sure this is the correct behaviour
                try message.children.forEach {
                    player.addAudioSource(try $0.toAudioSequence())
                }

                try onSetShuffleOrder(index: message.index, order: message.shuffleOrder)
            case .concatenatingRemoveRange:

                let message = ConcatenatingRemoveRangeMessage.fromMap(map: request)

                let range = message.startIndex ... message.endIndex
                for index in range {
                    try player.removeAudioSource(at: index)
                }
                try onSetShuffleOrder(index: 0, order: message.shuffleOrder)
            case .concatenatingMove:
                // TODO:
                throw SwiftJustAudioPluginError.notImplementedError(message: call.method)
            case .audioEffectSetEnabled:
                // TODO:
                // try player.enableEffect(type: request["type"] as! String, enabled: request["enabled"] as! Bool)
                throw SwiftJustAudioPluginError.notImplementedError(message: call.method)
            case .darwinEqualizerBandSetGain:
                // TODO: equalizer is passed over as audio effect
                // player.setEqualizerBandGain(bandIndex: request["bandIndex"] as! Int, gain: Float(request["gain"] as! Double))
                throw SwiftJustAudioPluginError.notImplementedError(message: call.method)
            }

            result([:])

        } catch let error as SwiftJustAudioPluginError {
            result(error.flutterError)
        } catch {
            // TODO: remove
            print("command: \(String(describing: call.method))")
            print("request: \(String(describing: call.arguments))")
            print(error)
            result(FlutterError(code: "510", message: "\(error)", details: nil))
        }
    }

    func onPlaybackEvent(event: PlaybackEvent) {
        eventChannel.sendEvent([
            "processingState": event.processingState,
            "updatePosition": event.updatePosition.microseconds,
            "updateTime": event.updateTime,
            "bufferedPosition": 0,
            "icyMetadata": [:],
            "duration": event.duration.microseconds,
            "currentIndex": event.currentIndex,
        ])
    }

    func dispose() {
        player.stop()
        eventChannel.dispose()
        dataChannel.dispose()
        methodChannel.setMethodCallHandler(nil)
    }
}

// MARK: - SwiftPlayer extensions

@available(iOS 13.0, *)
extension SwiftPlayer {
    func onLoad(message: AudioSourceMessage) throws {
        let sequence = try message.toAudioSequence()
        player.addAudioSource(sequence)

        guard let concatenating = message as? ConcatenatingAudioSourceMessage else {
            return
        }

        let shuffleOrder = concatenating.shuffleOrder

        try onSetShuffleOrder(index: 0, order: shuffleOrder)

        // TODO: (? not sure is needed): result(["duration": duration.microseconds])
    }

    func onSetShuffleOrder(index: Int, order: [Int]) throws {
        try player.shuffle(at: index, inOrder: order)
    }
}
