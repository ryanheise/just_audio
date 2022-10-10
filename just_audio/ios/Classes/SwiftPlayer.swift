import AVFoundation
import Combine
import Flutter
import kMusicSwift

@available(iOS 13.0, *)
internal class SwiftPlayer: NSObject {
    let errorsChannel: BetterEventChannel

    let playerId: String
    @Published var globalAudioEffects: [String: AudioEffect]
    @Published var audioSourcesAudioEffects: [String: AudioEffect] = [:]

    let methodChannel: FlutterMethodChannel
    let eventChannel: BetterEventChannel
    let dataChannel: BetterEventChannel

    var player: JustAudioPlayer!
    private var engine: AVAudioEngine!
    private var equalizer: Equalizer?
    private var shouldWriteOutputToFile: Bool = false

    var cancellables: [AnyCancellable] = []

    class Builder {
        private var messenger: FlutterBinaryMessenger!
        private var errorsChannel: BetterEventChannel!
        private var playerId: String!
        private var audioEffects: [AudioEffect]!
        private var engine: AVAudioEngine!
        private var equalizer: Equalizer?
        private var shouldWriteOutputToFile: Bool = false

        func withMessenger(messenger: FlutterBinaryMessenger) -> Builder {
            self.messenger = messenger
            return self
        }

        func withErrorsChannel(_ errorsChannel: BetterEventChannel) -> Builder {
            self.errorsChannel = errorsChannel
            return self
        }

        func withPlayerId(_ playerId: String) -> Builder {
            self.playerId = playerId
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
                errorsChannel: errorsChannel,
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
        errorsChannel: BetterEventChannel,
        playerId: String,
        shouldWriteOutputToFile: Bool,
        audioEffects: [AudioEffect],
        engine: AVAudioEngine,
        equalizer: Equalizer?
    ) {
        self.errorsChannel = errorsChannel

        self.playerId = playerId
        let effects: [String: AudioEffect] = [:]

        globalAudioEffects = audioEffects.reduce(into: effects) { partialResult, audioEffect in
            partialResult[UUID().uuidString] = audioEffect
        }

        self.engine = engine

        methodChannel = FlutterMethodChannel(name: Util.methodsChannel(forPlayer: playerId), binaryMessenger: messenger)
        eventChannel = BetterEventChannel(name: Util.eventsChannel(forPlayer: playerId), messenger: messenger)
        dataChannel = BetterEventChannel(name: Util.dataChannel(forPlayer: playerId), messenger: messenger)

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

            let request = call.arguments as? [String: Any] ?? [:]

            // Uncomment for debug
            // print("\ncommand: \(String(describing: call.method))")
            // print("request: \(String(describing: call.arguments))")

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

                try children.forEach {
                    let (_, audioSequence) = try FlutterAudioSourceType.parseAudioSequenceFrom(map: $0)
                    player.addAudioSource(audioSequence)
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
                guard let effect: DelayAudioEffect = getEffectByRequest(request) else {
                    return
                }

                let targetDelayTime = request["targetDelayTime"] as! Double
                effect.setDelayTime(targetDelayTime)

            case .darwinDelaySetTargetFeedback:
                guard let effect: DelayAudioEffect = getEffectByRequest(request) else {
                    return
                }

                let feedback = request["feedback"] as! Double

                effect.setFeedback(Float(feedback))
            case .darwinDelaySetLowPassCutoff:
                guard let effect: DelayAudioEffect = getEffectByRequest(request) else {
                    return
                }

                let lowPassCutoff = request["lowPassCutoff"] as! Double
                effect.setLowPassCutoff(Float(lowPassCutoff))
            case .darwinDelaySetWetDryMix:
                guard let effect: DelayAudioEffect = getEffectByRequest(request) else {
                    return
                }

                let wetDryMix = request["wetDryMix"] as! Double
                effect.setWetDryMix(Float(wetDryMix))
            case .darwinDistortionSetWetDryMix:
                guard let effect: DistortionAudioEffect = getEffectByRequest(request) else {
                    return
                }
                let wetDryMix = request["wetDryMix"] as! Double
                effect.setWetDryMix(Float(wetDryMix))
            case .darwinDistortionSetPreGain:
                guard let effect: DistortionAudioEffect = getEffectByRequest(request) else {
                    return
                }

                let preGain = request["preGain"] as! Double
                effect.setPreGain(Float(preGain))
            case .darwinDistortionSetPreset:
                guard let effect: DistortionAudioEffect = getEffectByRequest(request) else {
                    return
                }
                guard let preset = AVAudioUnitDistortionPreset(rawValue: request["preset"] as! Int) else {
                    return
                }

                effect.setPreset(preset)
            case .darwinReverbSetPreset:
                guard let effect: ReverbAudioEffect = getEffectByRequest(request) else {
                    return
                }
                guard let preset = AVAudioUnitReverbPreset(rawValue: request["preset"] as! Int) else {
                    return
                }

                effect.setPreset(preset)
            case .darwinReverbSetWetDryMix:
                guard let effect: ReverbAudioEffect = getEffectByRequest(request) else {
                    return
                }
                let wetDryMix = request["wetDryMix"] as! Double
                effect.setWetDryMix(Float(wetDryMix))
            }

            result([:])

        } catch let error as SwiftJustAudioPluginError {
            result(error.flutterError)
        } catch {
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

    private func getEffectByRequest<T: AudioEffect>(_ request: [String: Any?]) -> T? {
        guard let effectId = request["id"] as? String else {
            return nil
        }

        guard let effect = getEffectById(effectId) else {
            return nil
        }

        guard let effect = effect as? T else {
            return nil
        }

        return effect
    }

    private func getEffectById(_ id: String) -> AudioEffect? {
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
        let (effects, audioSequence) = try FlutterAudioSourceType.parseAudioSequenceFrom(map: request)
        player.addAudioSource(audioSequence)

        audioSourcesAudioEffects = effects.reduce(into: audioSourcesAudioEffects) { partialResult, audioEffectWithId in
            let (id, effect) = audioEffectWithId
            partialResult[id] = effect
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

        guard let effect = getEffectById(request["id"] as! String) else {
            return
        }

        if let reverb = effect as? ReverbAudioEffect {
            reverb.setBypass(false) // Don't know why, but bypassing the reverb causes no final output
            if enabled == false {
                reverb.setWetDryMix(0)
            }
        } else {
            effect.setBypass(!enabled)
        }
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
        .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
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

        let playerDataSource = Publishers.CombineLatest(
            trackInfos,
            mainInfos
        )

        let effectsDataSource = Publishers.CombineLatest3(
            safePlayer.$equalizer,
            $globalAudioEffects,
            $audioSourcesAudioEffects
        )

        Publishers.CombineLatest(
            playerDataSource,
            effectsDataSource
        ).map { playerData, effectsData -> EventChannelMessage in
            let trackInfos = playerData.0
            let mainInfos = playerData.1

            let equalizerData = effectsData.0
            let globalEffects = effectsData.1
            let audioSourceEffects = effectsData.2
            return EventChannelMessage(
                processingState: mainInfos.0,
                elapsedTime: safePlayer.elapsedTime,
                bufferedPosition: trackInfos.0,
                duration: trackInfos.1,
                currentIndex: mainInfos.1,
                equalizerData: equalizerData,
                globalEffects: globalEffects,
                audioSourceEffects: audioSourceEffects
            )
        }
        .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
        .receive(on: DispatchQueue.main)
        .sink(receiveValue: { [weak self] event in
            do {
                self?.eventChannel.sendEvent(try event.toMap())
            } catch {
                self?.errorsChannel.sendEvent(error.toFlutterError("When the player emt a new event and fails to serialize it").toMap())
            }

        })
        .store(in: &cancellables)
    }
}
