import AVFoundation
import Combine
import Flutter
import kMusicSwift

/**
 TODOS
 - expose missing feature from kmusicswift
 - handle effects on load
 - add effects on audiosource on dart layer
 - handle effects on audiosource
 */
@available(iOS 13.0, *)
internal class SwiftPlayer: NSObject {
    let playerId: String
    //let audioEffects: [AudioEffectMessage]

    let methodChannel: FlutterMethodChannel
    let eventChannel: BetterEventChannel
    let dataChannel: BetterEventChannel

    var player: JustAudioPlayer!
    private var engine: AVAudioEngine!
    private var equalizer: Equalizer?

    var cancellables: [AnyCancellable] = []

    class Builder {
        private var registrar: FlutterPluginRegistrar!
        private var playerId: String!
        private var loadConfiguration: LoadControlMessage!
        private var audioEffects: [AudioEffectMessage]!
        private var methodChannel: FlutterMethodChannel!
        private var eventChannel: BetterEventChannel!
        private var dataChannel: BetterEventChannel!
        private var engine: AVAudioEngine!
        private var equalizer: Equalizer?

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

        func withEqualizer(_ equalizer: Equalizer?) -> Builder {
            self.equalizer = equalizer
            return self
        }

        func build() -> SwiftPlayer {
            return SwiftPlayer(
                registrar: registrar,
                playerId: playerId,
                //loadConfiguration: loadConfiguration,
                //audioEffects: audioEffects,
                engine: engine,
                methodChannel: methodChannel,
                eventChannel: eventChannel,
                dataChannel: dataChannel,
                equalizer: equalizer
            )
        }
    }

    private init(
        registrar _: FlutterPluginRegistrar,
        playerId: String,
        //loadConfiguration _: LoadControlMessage,
        //audioEffects: [AudioEffectMessage],
        engine: AVAudioEngine,
        methodChannel: FlutterMethodChannel,
        eventChannel: BetterEventChannel,
        dataChannel: BetterEventChannel,
        equalizer: Equalizer?
    ) {
        self.playerId = playerId
        //self.audioEffects = audioEffects
        self.engine = engine

        self.methodChannel = methodChannel
        self.eventChannel = eventChannel
        self.dataChannel = dataChannel

        self.equalizer = equalizer

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
                player = JustAudioPlayer(engine: engine)

                if let safeEqualizer = equalizer {
                    try player.setEqualizer(safeEqualizer)
                }

                subscribeToPlayerEvents()
            }

            switch command {
            case .load:
                try onLoad(request: request)
                
                // TODO trigger change state in ready in player
                /*let event = EventChannelMessage(
                    processingState: .ready,
                    elapsedTime: 0,
                    bufferedPosition: 0,
                    duration: 0,
                    currentIndex: 0
                )
                
                eventChannel.sendEvent(event.toMap())
                */
                
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
}

// MARK: - SwiftPlayer handle extensions

@available(iOS 13.0, *)
extension SwiftPlayer {
    func onLoad(request: [String: Any?]) throws {
        player.addAudioSource(try request.audioSequence)

        try onSetShuffleOrder(request: request)

        // TODO: (? not sure is needed ?): result(["duration": duration.microseconds])
    }

    func onSetShuffleOrder(request: [String: Any]) throws {
        guard let shuffleOrder = request["shuffleOrder"] as? [Int] else {
            return
        }

        try player.shuffle(at: 0, inOrder: shuffleOrder)
    }

    func onAudioEffectSetEnabled(_ request: [String: Any]) throws {
        let type = request["type"] as! String

        if type == "DarwinEqualizer" {
            let enabled = request["enabled"] as! Bool
            if enabled {
                try player.activateEqualizerPreset(at: 0)
            } else {
                try player.resetGains()
            }
        }

        // TODO: handle other effects
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
            return prev.1.0 == curr.1.0
        }
        .map { trackInfos, mainInfos, _ in

            EventChannelMessage(processingState: mainInfos.0, elapsedTime: trackInfos.2, bufferedPosition: trackInfos.0, duration: trackInfos.1, currentIndex: mainInfos.1)
        }.removeDuplicates()
            .throttle(for: 10.0, scheduler: RunLoop.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] event in
               // print("===== Sending on event channel")
               // print(event.toMap())
                self?.eventChannel.sendEvent(event.toMap())
            })
            .store(in: &cancellables)
    }
}

// Specify the decimal place to round to using an enum
public enum RoundingPrecision {
    case ones
    case tenths
    case hundredths
    case millis
    case micros
}

enum RoundingHelper {
    // Round to the specific decimal place
    static func preciseRound(_ value: Double,
                             precision: RoundingPrecision = .ones) -> Int
    {
        switch precision {
        case .ones:
            return Int(round(value))
        case .tenths:
            return Int(round(value * 10) / 10.0)
        case .hundredths:
            return Int(round(value * 100) / 100.0)
        case .millis:
            return Int(round(value * 1000) / 1000.0)
        case .micros:
            return Int(round(value * 1_000_000) / 1_000_000)
        }
    }
}

class DataChannelMessage: Equatable {
    static func == (lhs: DataChannelMessage, rhs: DataChannelMessage) -> Bool {
        lhs.outputAbsolutePath == rhs.outputAbsolutePath &&
            "\(String(describing: lhs.outputError))" == "\(String(describing: rhs.outputError))" &&

            lhs.playing == rhs.playing &&
            lhs.volume == rhs.volume &&
            lhs.speed == rhs.speed &&

            lhs.loopMode == rhs.loopMode &&
            lhs.shuffleMode == rhs.shuffleMode
    }

    let outputAbsolutePath: String?
    let outputError: Error?

    let playing: Bool?
    let volume: Float?
    let speed: Float?

    let loopMode: Int?
    let shuffleMode: Int?

    init(outputAbsolutePath: String?, outputError: Error?, playing: Bool, volume: Float?, speed: Float?, loopMode: LoopMode?, shuffleMode: Bool) {
        self.outputAbsolutePath = outputAbsolutePath
        self.outputError = outputError

        self.playing = playing
        self.volume = volume
        self.speed = speed

        self.shuffleMode = shuffleMode ? 1 : 0

        switch loopMode {
        case .off:
            self.loopMode = 0
        case .one:
            self.loopMode = 1
        case .all:
            self.loopMode = 2
        default:
            self.loopMode = nil
        }
    }

    func toMap() -> [String: Any?] {
        return [
            "outputAbsolutePath": outputAbsolutePath,
            "outputError": outputError != nil ? "\(String(describing: outputError))" : nil,

            "playing": playing,
            "volume": volume,
            "speed": speed,

            "loopMode": loopMode,
            "shuffleMode": shuffleMode,
        ]
    }
}

// TODO: expose equalizer infos
class EventChannelMessage: Equatable {
    static func == (lhs: EventChannelMessage, rhs: EventChannelMessage) -> Bool {
        lhs.processingState == rhs.processingState &&
            lhs.updatePosition == rhs.updatePosition &&
            lhs.bufferedPosition == rhs.bufferedPosition &&
            lhs.duration == rhs.duration &&
            lhs.currentIndex == rhs.currentIndex
    }

    let processingState: Int
    let updatePosition: Int
    let bufferedPosition: Int
    let duration: Int
    let currentIndex: Int

    init(processingState: ProcessingState?, elapsedTime: Double?, bufferedPosition: Double?, duration: Double?, currentIndex: Int?) {
        switch processingState {
        case .none?:
            self.processingState = 0
        case .loading:
            self.processingState = 1
        case .buffering:
            self.processingState = 2
        case .ready:
            self.processingState = 3
        case .completed:
            self.processingState = 4
        default:
            self.processingState = 0
        }

        /*updatePosition = elapsedTime != nil
            ? RoundingHelper.preciseRound(elapsedTime!, precision: .micros)
            : 0*/
        updatePosition = elapsedTime != nil ? Int(elapsedTime! * 1_000_000) : 0

        self.bufferedPosition = bufferedPosition != nil ? Int(bufferedPosition! * 1_000_000) : 0

        self.duration = duration != nil ? Int(duration! * 1_000_000) : 0
        
        self.currentIndex = currentIndex ?? 0
        print("iOS: duration: \(self.duration) | position: \(updatePosition)")
    }

    func toMap() -> [String: Any?] {
        
        return [
            "processingState": processingState,
            "updatePosition": updatePosition,
            "updateTime": Int(Date().timeIntervalSince1970 * 1000),
            "bufferedPosition": bufferedPosition,
            "icyMetadata": [:], // Currently not supported
            "duration": duration,
            "currentIndex": currentIndex,
        ]
    }
}
