import AVFoundation

class PluginError : Error {
    let code: Int
    let message: String
    
    init(_ code: Int, _ message: String) {
        self.code = code;
        self.message = message
    }
    
    static func notImplemented(_ message: String) -> PluginError {
        return PluginError(500, message)
    }
    
    static func notInitialized(_ message: String) -> PluginError {
        return PluginError(403, message)
    }
    
    static func notSupported(_ value: Any, _ message: Any) -> PluginError {
        return PluginError(400, "Not support \(value)\n\(message)")
    }
}

public class JustAudioPlayer: NSObject {
    let playerId: String
    let audioEffects: [[String: Any]]
    
    let methodChannel: FlutterMethodChannel
    let eventChannel: BetterEventChannel
    let dataChannel: BetterEventChannel
    
    var player: Player!

    init(registrar: FlutterPluginRegistrar, playerId: String, loadConfiguration: [String: Any], audioEffects: [[String: Any]]) {
        self.playerId = playerId
        self.audioEffects = audioEffects
        
        methodChannel = FlutterMethodChannel(name: String(format: "com.ryanheise.just_audio.methods.%@", playerId), binaryMessenger: registrar.messenger())
        eventChannel = BetterEventChannel(name: String(format: "com.ryanheise.just_audio.events.%@", playerId), messenger: registrar.messenger())
        dataChannel = BetterEventChannel(name: String(format: "com.ryanheise.just_audio.data.%@", playerId), messenger: registrar.messenger())

        print("TODO: loadConfiguration", loadConfiguration)

        super.init()
        methodChannel.setMethodCallHandler { call, result in
            self.handleMethodCall(call: call, result: result)
        }
    }
    
    func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            if (player == nil) {
                player = Player(audioEffects: try! audioEffects.map(Mapping.effectFrom), onEvent: onPlaybackEvent);
            }
            
            let request = call.arguments as! [String: Any]
//             print("=========== \(call.method) \(request)")
            
            switch call.method {
            case "load":
                let source = try AudioSource.fromJson(request["audioSource"] as! [String: Any])
                let initialPosition = request["initialPosition"] != nil ? CMTime.invalid : CMTimeMake(value: request["initialPosition"] as! Int64, timescale: 1_000_000)
                let initialIndex = request["initialIndex"] as? Int ?? 0
                
                let duration = player.load(source: source, initialPosition: initialPosition, initialIndex: initialIndex)
                result(["duration": duration.microSeconds])
            case "play":
                player.play()
                result([:])
            case "pause":
                player.pause()
                result([:])
            case "setVolume":
                player.setVolume(Float(request["volume"] as! Double))
                result([:])
//            case "setSkipSilence":
//                print("TODO: setSkipSilence", request)
//                result([:])
            case "setSpeed":
                player.setSpeed(Float(request["speed"] as! Double))
                result([:])
            case "setLoopMode":
                player.setLoopMode(mode: Mapping.loopModeFrom(request["loopMode"] as! Int))
                result([:])
            case "setShuffleMode":
                player.setShuffleMode(isEnalbed: Mapping.shuffleModeFrom(request["shuffleMode"] as! Int))
                result([:])
//            case "setShuffleOrder":
//                print("TODO: setShuffleOrder", request)
//                result([:])
//            case "setAutomaticallyWaitsToMinimizeStalling":
//                print("TODO: setAutomaticallyWaitsToMinimizeStalling", request)
//                result([:])
//            case "setCanUseNetworkResourcesForLiveStreamingWhilePaused":
//                print("TODO: setCanUseNetworkResourcesForLiveStreamingWhilePaused", request)
//                result([:])
//            case "setPreferredPeakBitRate":
//                print("TODO: setPreferredPeakBitRate", request)
//                result([:])
            case "seek":
                let position = Mapping.timeFrom(microseconds: request["position"] as! Int64)
                let index = request["index"] as? Int

                player.seek(index: index, position: position)
                result([:])
//            case "concatenatingInsertAll":
//                print("TODO: concatenatingInsertAll", request)
//                result([:])
//            case "concatenatingRemoveRange":
//                print("TODO: concatenatingRemoveRange", request)
//                result([:])
//            case "concatenatingMove":
//                print("TODO: concatenatingMove", request)
//                result([:])
            case "audioEffectSetEnabled":
                try player.enableEffect(type: request["type"] as! String, enabled: request["enabled"] as! Bool)
                result([:])
            case "darwinEqualizerBandSetGain":
                player.setEqualizerBandGain(bandIndex: request["bandIndex"] as! Int, gain: Float(request["gain"] as! Double))
                result([:])
            default:
                result(FlutterMethodNotImplemented)
            }
        } catch let error as PluginError {
            result(FlutterError(code: "\(error.code)", message: error.message, details: nil))
        } catch let error {
            print(error)
            result(FlutterError(code: "500", message: error.localizedDescription, details: nil))
        }
    }
    
    func onPlaybackEvent(event: PlaybackEvent) {
        eventChannel.sendEvent([
            "processingState": event.processingState.rawValue,
            "updatePosition": event.updatePosition.microSeconds,
            "updateTime": event.updateTime,
            "bufferedPosition": 0,
            "icyMetadata": [:],
            "duration": event.duration.microSeconds,
            "currentIndex": event.currentIndex,
        ])
    }
    
    func dispose() {
        player?.dispose()
        player = nil
        
        eventChannel.dispose()
        dataChannel.dispose()
        methodChannel.setMethodCallHandler(nil)
    }
}

enum ProcessingState: Int, Codable {
    case none, loading, buffering, ready, completed
}

enum LoopMode: Int {
    case loopOff, loopOne, loopAll
}

class Player {
    let onEvent: (PlaybackEvent) -> Void
    let audioEffects: [EffectData]
    
    var engine: AVAudioEngine!
    var playerNode: AVAudioPlayerNode!
    var speedControl: AVAudioUnitVarispeed!
    var audioUnitEQ: AVAudioUnitEQ?

    // State properties
    var processingState: ProcessingState = .none
    var shuffleModeEnabled = false
    var loopMode: LoopMode = .loopOff
    
    // Queue properties
    var indexedAudioSources: [IndexedAudioSource] = []
    var currentSource: IndexedAudioSource?
    var order: [Int] = []
    var orderInv: [Int] = []
    
    // Current Source
    var index: Int = 0
    var audioSource: AudioSource!
    var duration: CMTime {
        if processingState == .none || processingState == .loading {
            return CMTime.invalid
        } else if indexedAudioSources.count > 0 {
            return currentSource!.getDuration()
        } else {
            return CMTime.zero
        }
    }
    
    // Positions properties
    var positionUpdatedAt: Int64 = 0
    var positionUpdate: CMTime = .zero
    var positionOffset: CMTime = .zero
    var currentPosition: CMTime { return positionUpdate + positionOffset }

    // Extra properties
    var volume: Float = 1
    var rate: Float = 1

    init(audioEffects: [EffectData], onEvent: @escaping (PlaybackEvent) -> Void) {
        self.audioEffects = audioEffects
        self.onEvent = onEvent
    }

    func load(source: AudioSource, initialPosition _: CMTime, initialIndex: Int) -> CMTime {
        if playerNode != nil {
            playerNode.pause()
        }

        index = initialIndex
        processingState = .loading
        updatePosition(CMTime.zero)
        // Decode audio source
        audioSource = source

        indexedAudioSources = audioSource.buildSequence()

        updateOrder()
        index = 0
        
        if indexedAudioSources.isEmpty {
            
            processingState = .none
            broadcastPlaybackEvent()
            
            return CMTime.zero
        }

        if engine == nil {
            engine = AVAudioEngine()
            playerNode = AVAudioPlayerNode()
            speedControl = AVAudioUnitVarispeed()

            try! createAudioEffects()

            playerNode.volume = volume
            speedControl.rate = rate

            var nodes = [playerNode, speedControl]

            // add equalizer node
            if audioUnitEQ != nil {
                nodes.append(audioUnitEQ!)
            }

            // attach all nodes to engine
            for node in nodes {
                engine.attach(node!)
            }
            
            // add mainMixerNode
            nodes.append(engine.mainMixerNode)

            for i in 1 ..< nodes.count {
                engine.connect(nodes[i - 1]!, to: nodes[i]!, format: nil)
            }
            
            // Observe for changes in the audio engine configuration
            NotificationCenter.default.addObserver(self,
               selector: #selector(_handleInterruption),
               name: NSNotification.Name.AVAudioEngineConfigurationChange,
               object: nil
            )
        }

        try! setQueueFrom(index)
        
        _loadCurrentSource()

        if !engine.isRunning {
            try! engine.start()
        }

        processingState = .ready
        broadcastPlaybackEvent()
        
        return duration
    }
    
    @objc func _handleInterruption(notification: Notification) {
        _resume()
    }
    
    func play() {
        _play()
        updatePosition(nil)
        broadcastPlaybackEvent()
    }
    
    func pause() {
        updatePosition(nil)
        playerNode.pause()
        broadcastPlaybackEvent()
    }
    
    func _resume() {
        let wasPlaying = playerNode.isPlaying
        
        playerNode.pause()
        if (!engine.isRunning) {
            try! engine.start()
        }
        
        if (wasPlaying) {
            playerNode.play()
        }
    }
    
    func seek(index: Int?, position: CMTime) {
        let wasPlaying = self.playerNode.isPlaying
        
        if let index = index {
            try! setQueueFrom(index)
        }

        _stop()
        
        updatePosition(position)

        processingState = .ready

        _loadCurrentSource()
       
        // Restart play if player was playning
        if (wasPlaying) {
            _play()
        }

        broadcastPlaybackEvent()
    }
    
    func updatePosition(_ positionUpdate: CMTime?) {
        self.positionUpdatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        if let positionUpdate = positionUpdate { self.positionUpdate = positionUpdate  }
        self.positionOffset = indexedAudioSources.count > 0 && positionUpdate == nil ? self.playerNode.currentTime : CMTime.zero
    }
    
    var _isStopping = false
    // Permit to check if [load(completionHandler)] is called when you force a stop
    func _stop() {
        _isStopping = true
        if playerNode.isPlaying { playerNode.stop() }
        _isStopping = false
    }
    
    func _play() {
        if (!self.engine.isRunning) {
            try! self.engine.start()
        }
        playerNode.play()
    }
    
    func _loadCurrentSource() {
        try! currentSource!.load(engine: engine, playerNode: playerNode, speedControl: speedControl, position: positionUpdate, completionHandler: {
            if (self._isStopping) {return}
            self._playNext()
        })
    }

    func _playNext() {
        DispatchQueue.main.async {
            let newIndex = self.index + 1
            if newIndex >= self.indexedAudioSources.count {
                self._complete()
            } else {
                self.seek(index: newIndex, position: CMTime.zero)
                self.play()
            }
        }
    }

    func _complete() {
        updatePosition(nil)
        processingState = .completed
        if playerNode != nil {
            playerNode.stop()
        }
        broadcastPlaybackEvent()
    }
    
    // ========== QUEUE
    
    func setQueueFrom(_ index: Int) throws {
        self.index = index
        guard !indexedAudioSources.isEmpty else {
            preconditionFailure("no songs on library")
        }
        currentSource = indexedAudioSources[index]
    }
    
    // ========== MODES
    
    func setShuffleMode(isEnalbed: Bool) {
        shuffleModeEnabled = isEnalbed
        updateOrder()
        broadcastPlaybackEvent()
    }
    
    func setLoopMode(mode: LoopMode) {
        loopMode = mode
        broadcastPlaybackEvent()
    }
    
    func updateOrder() {
        orderInv = Array(repeating: 0, count: indexedAudioSources.count)
        if shuffleModeEnabled {
            order = audioSource.getShuffleIndices()
        } else {
            order = indexedAudioSources.enumerated().map { index, _ in
                index
            }
        }
        for i in 0 ..< indexedAudioSources.count {
            orderInv[order[i]] = i
        }
    }
    
    // ========== EFFECTS

    func createAudioEffects() throws {
        for effect in audioEffects {
            if let effect = effect as? EqualizerEffectData {
                audioUnitEQ = AVAudioUnitEQ(numberOfBands: effect.parameters.bands.count)
                
                for (i, band) in effect.parameters.bands.enumerated() {
                    audioUnitEQ!.bands[i].filterType = .parametric
                    audioUnitEQ!.bands[i].frequency = band.centerFrequency
                    audioUnitEQ!.bands[i].bandwidth = 1 // half an octave
                    audioUnitEQ!.bands[i].gain = Mapping.gainFrom(band.gain)
                    audioUnitEQ!.bands[i].bypass = false
                }
                
                audioUnitEQ!.bypass = !effect.enabled
            } else {
                throw PluginError.notSupported(effect.type, "When initialize effect")
            }
        }
    }

    func enableEffect(type: String, enabled: Bool) throws {
        switch type {
        case "DarwinEqualizer":
            audioUnitEQ!.bypass = !enabled
        default:
            throw PluginError.notInitialized("Not initialized effect \(type)")
        }
    }

    func setEqualizerBandGain(bandIndex: Int, gain: Float) {
        audioUnitEQ?.bands[bandIndex].gain = gain
    }
    
    // ======== EXTRA
    
    func setVolume(_ value: Float) {
        volume = value
        if playerNode != nil {
            playerNode.volume = volume
        }
        broadcastPlaybackEvent()
    }
    
    func setSpeed(_ value: Float) {
        rate = value
        if speedControl != nil {
            speedControl.rate = rate
        }
        updatePosition(nil)
    }
    
    func broadcastPlaybackEvent() {
        onEvent(PlaybackEvent(
            processingState: processingState,
            updatePosition: self.currentPosition,
            updateTime: self.positionUpdatedAt,
            duration: duration,
            currentIndex: index
        ))
    }

    func dispose() {
        if processingState != .none {
            playerNode?.pause()
            processingState = .none
        }
        audioSource = nil
        indexedAudioSources = []
        playerNode?.stop()
        engine?.stop()
    }
}

extension CMTime {
    var milliSeconds: Int64 {
        return self == CMTime.invalid ? -1 : Int64(value * 1000 / Int64(timescale))
    }

    var microSeconds: Int64 {
        return self == CMTime.invalid ? -1 : Int64(value * 1_000_000 / Int64(timescale))
    }
}

extension AVAudioPlayerNode {
    var currentTime: CMTime {
        if let nodeTime: AVAudioTime = lastRenderTime, let playerTime: AVAudioTime = playerTime(forNodeTime: nodeTime) {
            let currentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
            let milliSeconds = Int64(currentTime * 1000)
            return milliSeconds < 0 ? CMTime.zero : CMTime(value: milliSeconds, timescale: 1000)
        }
        return CMTime.zero
    }
}

class Mapping {
    static func timeFrom(microseconds: Int64) -> CMTime {
        return CMTimeMake(value: microseconds, timescale: 1_000_000)
    }
    
    static func loopModeFrom(_ value: Int) -> LoopMode {
        switch (value) {
        case 1:
            return LoopMode.loopOne
        case 2:
            return LoopMode.loopAll
        default:
            return LoopMode.loopOff
        }
    }
    
    static func shuffleModeFrom(_ value: Int) -> Bool {
        return value == 1
    }
    
    static func gainFrom(_ value: Float) -> Float {
        // Equalize the level between ios and android
        return value * 2.8
    }
    
    static func effectFrom(_ map: [String: Any]) throws -> EffectData {
        let type = map["type"] as! String
        switch (type) {
        case EffectType.darwinEqualizer.rawValue:
            return EqualizerEffectData.fromJson(map)
        default:
            throw PluginError.notSupported(type, "When decoding effect")
        }
    }
}

enum EffectType : String, Codable {
    case darwinEqualizer = "DarwinEqualizer"
}

protocol EffectData {
    var type: EffectType { get }
}

struct EqualizerEffectData : EffectData, Codable {
    let type: EffectType
    let enabled: Bool
    let parameters: ParamsEqualizerData
    
    static func fromJson(_ map: [String: Any]) -> EqualizerEffectData {
        return try! JSONDecoder().decode(EqualizerEffectData.self, from: JSONSerialization.data(withJSONObject: map))
    }
}

struct ParamsEqualizerData : Codable {
    let bands: Array<BandEqualizerData>
}

struct BandEqualizerData : Codable {
    let index: Int
    let centerFrequency: Float
    let gain: Float
}

struct PlaybackEvent {
    let processingState: ProcessingState
    let updatePosition: CMTime
    let updateTime: Int64
    let duration: CMTime
    let currentIndex: Int
}
