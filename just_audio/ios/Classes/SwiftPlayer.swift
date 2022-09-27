import AVFoundation
import Combine
import Flutter
import kMusicSwift

/**
 TODOS
 - expose missing feature from kmusicswift
 - handle effects on audiosource
 - map effects & equalizer to flutter plugin
 */
@available(iOS 13.0, *)
internal class SwiftPlayer: NSObject {
    let playerId: String
    var globalAudioEffects: [String: AudioEffect]
    var audioSourcesAudioEffects: [String: AudioEffect] = [:]

    let methodChannel: FlutterMethodChannel
    let eventChannel: BetterEventChannel
    let dataChannel: BetterEventChannel

    var player: JustAudioPlayer!
    private var engine: AVAudioEngine!
    private var equalizer: Equalizer?
    private var shouldWriteOutputToFile: Bool = false

    var cancellables: [AnyCancellable] = []

    class Builder {
        private var playerId: String!
        private var audioEffects: [AudioEffect]!
        private var engine: AVAudioEngine!
        private var equalizer: Equalizer?
        private var messenger: FlutterBinaryMessenger!
        private var shouldWriteOutputToFile: Bool = false

        func withPlayerId(_ playerId: String) -> Builder {
            self.playerId = playerId
            return self
        }

        func withMessenger(messenger: FlutterBinaryMessenger) -> Builder {
            self.messenger = messenger
            return self
        }

        func withAudioEffects(_ audioEffects: [AudioEffect]) -> Builder {
            self.audioEffects = audioEffects
            return self
        }

        func withAudioEngine(_ engine: AVAudioEngine) -> Builder {
            self.engine = engine
            return self
        }

        func withShouldWriteOutputToFile(_ shouldWriteOutputToFile: Bool) -> Builder {
            self.shouldWriteOutputToFile = shouldWriteOutputToFile
            return self
        }

        func withEqualizer(_ equalizer: Equalizer?) -> Builder {
            self.equalizer = equalizer
            return self
        }

        func build() -> SwiftPlayer {
            return SwiftPlayer(
                messenger: messenger,
                playerId: playerId,
                shouldWriteOutputToFile: shouldWriteOutputToFile,
                audioEffects: audioEffects,
                engine: engine,
                equalizer: equalizer
            )
        }
    }

    private init(
        messenger: FlutterBinaryMessenger,
        playerId: String,
        shouldWriteOutputToFile: Bool,
        audioEffects: [AudioEffect],
        engine: AVAudioEngine,
        equalizer: Equalizer?
    ) {
        self.playerId = playerId
        var effects: [String: AudioEffect] = [:]

        self.globalAudioEffects = audioEffects.reduce(into: effects) { partialResult, audioEffect in
            partialResult[UUID().uuidString] = audioEffect
        }
       
        self.engine = engine

        methodChannel = FlutterMethodChannel(name: playerId.methodsChannel, binaryMessenger: messenger)
        eventChannel = BetterEventChannel(name: playerId.eventsChannel, messenger: messenger)
        dataChannel = BetterEventChannel(name: playerId.dataChannel, messenger: messenger)

        self.equalizer = equalizer
        self.shouldWriteOutputToFile = shouldWriteOutputToFile

        super.init()

        methodChannel.setMethodCallHandler { call, result in
            self.handleMethodCall(call: call, result: result)
        }
    }

    func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            let command = try SwiftPlayerCommand.parse(call.method)

            let request = call.arguments as! [String: Any]

            print("\ncommand: \(String(describing: call.method))")
            print("\nrequest: \(String(describing: call.arguments))")

            // ensure inner instance
            if player == nil {
                try initPlayer()
            }

            switch command {
            case .load:
                try onLoad(request: request)
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
                try onSetShuffleOrder(request: request)
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

                let children = request["children"] as! [[String: Any?]]

                // TODO: Check, not sure this is the correct behaviour
                try children.forEach {
                    player.addAudioSource(try $0.audioSequence)
                }

                try onSetShuffleOrder(request: request)
            case .concatenatingRemoveRange:

                let startIndex = request["startIndex"] as! Int
                let endIndex = request["endIndex"] as! Int

                let range = startIndex ... endIndex
                for index in range {
                    try player.removeAudioSource(at: index)
                }

                try onSetShuffleOrder(request: request)
            case .concatenatingMove:
                // TODO:
                throw SwiftJustAudioPluginError.notImplementedError(message: call.method)
            case .audioEffectSetEnabled:
                try onAudioEffectSetEnabled(request)
            case .darwinEqualizerBandSetGain:
                try onEqualizerBandSetGain(request)
            case .darwinWriteOutputToFile:
                try player.writeOutputToFile()
            case .darwinStopWriteOutputToFile:
                player.stopWritingOutputFile()
            case .darwinDelaySetTargetDelayTime:
                guard let effectId = request["id"] as? String else{
                    return
                }
                
                guard let effect = getEffectById(effectId) else {
                    return
                }
                
                guard let effect = effect as? DelayAudioEffect else {
                    return
                }
                
                let targetDelayTime = request["targetDelayTime"] as! Double
                effect.setDelayTime(targetDelayTime)
                
            case .darwinDelaySetTargetFeedback:
                guard let effectId = request["id"] as? String else{
                    return
                }
                
                guard let effect = getEffectById(effectId) else {
                    return
                }
            case .darwinDelaySetLowPassCutoff:
                guard let effectId = request["id"] as? String else{
                    return
                }
                
                guard let effect = getEffectById(effectId) else {
                    return
                }
            case .darwinDelaySetWetDryMix:
                guard let effectId = request["id"] as? String else{
                    return
                }
                
                guard let effect = getEffectById(effectId) else {
                    return
                }
            case .darwinDistortionSetWetDryMix:
                guard let effectId = request["id"] as? String else{
                    return
                }
                
                guard let effect = getEffectById(effectId) else {
                    return
                }
            case .darwinDistortionSetPreGain:
                guard let effectId = request["id"] as? String else{
                    return
                }
                
                guard let effect = getEffectById(effectId) else {
                    return
                }
            case .darwinDistortionSetPreset:
                guard let effectId = request["id"] as? String else{
                    return
                }
                
                guard let effect = getEffectById(effectId) else {
                    return
                }
            case .darwinReverbSetPreset:
                guard let effectId = request["id"] as? String else{
                    return
                }
                
                guard let effect = getEffectById(effectId) else {
                    return
                }
            case .darwinReverbSetWetDryMix:
                guard let effectId = request["id"] as? String else{
                    return
                }
                
                guard let effect = getEffectById(effectId) else {
                    return
                }
            }

            result([:])

        } catch let error as SwiftJustAudioPluginError {
            result(error.flutterError)
        } catch {
            // TODO: remove once stable
            print("\ncommand: \(String(describing: call.method))")
            print("\nrequest: \(String(describing: call.arguments))")
            print(error)
            result(FlutterError(code: "510", message: "\(error)", details: nil))
        }
    }

    func dispose() {
        player.stop()
        eventChannel.dispose()
        dataChannel.dispose()
        methodChannel.setMethodCallHandler(nil)

        cancellables.forEach { cancellable in
            cancellable.cancel()
        }
    }
    
    private func getEffectByRequest() {
        guard let effectId = request["id"] as? String else{
            return
        }
        
        guard let effect = getEffectById(effectId) else {
            return
        }
        
        guard let effect = effect as? DelayAudioEffect else {
            return
        }
    }
    
    private func getEffectById(_ id:String) -> AudioEffect? {
        guard let effect = globalAudioEffects[id] else {
            return audioSourcesAudioEffects[id]
        }
        
        return effect
    }
}

// MARK: - SwiftPlayer init player extension
@available(iOS 13.0, *)
extension SwiftPlayer {
    func initPlayer() throws {
        player = JustAudioPlayer(engine: engine)

        if let safeEqualizer = equalizer {
            try player.setEqualizer(safeEqualizer)
        }

        globalAudioEffects.forEach { _, audioEffect in
            player.addAudioEffect(audioEffect)
        }

        if shouldWriteOutputToFile {
            try player.writeOutputToFile()
        }

        subscribeToPlayerEvents()
    }
}

// MARK: - SwiftPlayer handle extensions
@available(iOS 13.0, *)
extension SwiftPlayer {
    func onLoad(request: [String: Any?]) throws {
        let audioSequence = try request.audioSequence
        player.addAudioSource(audioSequence)

        let effects = audioSequence.sequence.map { audioSource in
            audioSource.effects
        }.flatMap { $0 }

        audioSourcesAudioEffects = effects.reduce(into: audioSourcesAudioEffects) { partialResult, audioEffect in
            partialResult[UUID().uuidString] = audioEffect
        }

        try onSetShuffleOrder(request: request)
    }

    func onSetShuffleOrder(request: [String: Any?]) throws {
        guard let shuffleOrder = request["shuffleOrder"] as? [Int] else {
            return
        }

        try player.shuffle(at: 0, inOrder: shuffleOrder)
    }

    func onAudioEffectSetEnabled(_ request: [String: Any]) throws {
        let rawType = request["type"] as! String
        let enabled = request["enabled"] as! Bool
        
        if rawType == "DarwinEqualizer" {
            
            if enabled {
                try player.activateEqualizerPreset(at: 0)
            } else {
                try player.resetGains()
            }
            
            return
        }

        let type = DarwinAudioEffect(rawValue: rawType)!
        
        let effect = try globalAudioEffects.values.first(where: { effect in
            return try effect.type == type
        })
        
        effect?.setBypass(enabled)
    }

    func onEqualizerBandSetGain(_ request: [String: Any]) throws {
        let bandIndex = request["bandIndex"] as! Int
        let gain = request["gain"] as! Double
        try player.tweakEqualizerBandGain(band: bandIndex, gain: Float(gain))
    }
}

// MARK: - SwiftPlayer streams
@available(iOS 13.0, *)
extension SwiftPlayer {
    func subscribeToPlayerEvents() {
        guard let safePlayer = player else {
            return
        }

        // data channel
        let outputPublishers = Publishers.CombineLatest(
            safePlayer.$outputAbsolutePath,
            safePlayer.$outputWriteError
        )

        let playerInfoPublishers = Publishers.CombineLatest3(
            safePlayer.$isPlaying,
            safePlayer.$volume,
            safePlayer.$speed
        )

        let sideInfosPublishers = Publishers.CombineLatest(
            safePlayer.$loopMode,
            safePlayer.isShuffling
        )

        Publishers.CombineLatest3(
            outputPublishers,
            playerInfoPublishers,
            sideInfosPublishers
        )
        .map { outputAbsoluteInfo, playerInfoPublishers, sideInfosPublishers in
            DataChannelMessage(
                outputAbsolutePath: outputAbsoluteInfo.0,
                outputError: outputAbsoluteInfo.1,
                playing: playerInfoPublishers.0,
                volume: playerInfoPublishers.1,
                speed: playerInfoPublishers.2,
                loopMode: sideInfosPublishers.0,
                shuffleMode: sideInfosPublishers.1
            )
        }
        .removeDuplicates()
        .receive(on: DispatchQueue.main)
        .sink(receiveValue: { [weak self] event in
            self?.dataChannel.sendEvent(event.toMap())
        })
        .store(in: &cancellables)

        // event channel
        let trackInfos = Publishers.CombineLatest3(
            safePlayer.$bufferPosition,
            safePlayer.$duration,
            safePlayer.$elapsedTime
        )

        let mainInfos = Publishers.CombineLatest(
            safePlayer.$processingState,
            safePlayer.$queueIndex
        )

        Publishers.CombineLatest3(
            trackInfos,
            mainInfos,
            safePlayer.$equalizer
        )
        .removeDuplicates { prev, curr in
            prev.1.0 == curr.1.0
        }
        .map { trackInfos, mainInfos, _ in

            EventChannelMessage(processingState: mainInfos.0, elapsedTime: trackInfos.2, bufferedPosition: trackInfos.0, duration: trackInfos.1, currentIndex: mainInfos.1)
        }.removeDuplicates()
        .throttle(for: 10.0, scheduler: RunLoop.main, latest: true)
        .receive(on: DispatchQueue.main)
        .sink(receiveValue: { [weak self] event in
            self?.eventChannel.sendEvent(event.toMap())
        })
        .store(in: &cancellables)
    }
}
