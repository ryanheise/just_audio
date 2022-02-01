import AVFoundation

enum PluginError: Error {
    case runtimeError(String)
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
        if (player == nil) {
            player = Player(audioEffects: audioEffects, onEvent: eventChannel.sendEvent);
        }
        
        do {
            let request = call.arguments as! [String: Any]
            print("=========== \(call.method) \(request)")
            
            switch call.method {
            case "load":
                let source = request["audioSource"] as! [String: Any]
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
            case "setSkipSilence":
                print("TODO: setSkipSilence", request)
                result([:])
            case "setSpeed":
                player.setSpeed(Float(request["speed"] as! Double))
                result([:])
            case "setLoopMode":
                player.setLoopMode(mode: Mapping.loopModeFrom(value: request["loopMode"] as! Int))
                result([:])
            case "setShuffleMode":
                player.setShuffleMode(isEnalbed: Mapping.shuffleModeFrom(value: request["shuffleMode"] as! Int))
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
                let index = request["index"] as? Int ?? 0

                player.seek(position: position, index: index)
                
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
//            case "setAndroidAudioAttributes":
//                print("TODO: setAndroidAudioAttributes", request)
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
        } catch {
            let flutterError = FlutterError(code: "error", message: "Error in handleMethodCall", details: nil)
            result(flutterError)
        }
    }
    
    func dispose() {
        player?.dispose()
        player = nil
        
        eventChannel.dispose()
        dataChannel.dispose()
        methodChannel.setMethodCallHandler(nil)
    }
}

enum ProcessingState: Int {
    case none, loading, buffering, ready, completed
}

enum LoopMode: Int {
    case loopOff, loopOne, loopAll
}

class Player {
    let onEvent: ([String: Any]) -> Void
    let audioEffects: [[String: Any]]
    
    var engine: AVAudioEngine!
    var playerNode: AVAudioPlayerNode!
    var speedControl: AVAudioUnitVarispeed!
    var audioUnitEQ: AVAudioUnitEQ?

    // State properties
    var playing = false
    var processingState: ProcessingState = .loading
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
    
    

    init(audioEffects: [[String: Any]], onEvent: @escaping ([String: Any]) -> Void) {
        self.audioEffects = audioEffects
        self.onEvent = onEvent
    }

    func load(source: [String: Any], initialPosition _: CMTime, initialIndex: Int) -> CMTime {
        if playerNode != nil {
            playerNode.pause()
        }

        index = initialIndex
        processingState = .loading
        updatePosition(CMTime.zero)
        // Decode audio source
        audioSource = try! decodeAudioSource(data: source)

        indexedAudioSources = []
        _ = audioSource.buildSequence(sequence: &indexedAudioSources, treeIndex: 0)

        updateOrder()
        index = 0

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
        }

        try! enqueueFrom(index)

        if !engine.isRunning {
            try! engine.start()
        }

        processingState = .ready

        broadcastPlaybackEvent()
        return duration
    }
    
    func play() {
        playerNode.play()
        updatePosition(nil)
        broadcastPlaybackEvent()
    }
    
    func pause() {
        updatePosition(nil)
        playerNode.pause()
        broadcastPlaybackEvent()
    }
    
    func seek(position: CMTime, index: Int) {
        try! queueFrom(index)

        playerNode.stop()
        
        print("lenght \(indexedAudioSources.count)")
        updatePosition(position);
        

        processingState = .ready

//        let iSource = indexedAudioSources[index]
//        let iUpdateTime = updateTime
//        let iPosition = currentPosition
        try! currentSource!.load(engine: engine, playerNode: playerNode, speedControl: speedControl, position: position, completionHandler: { type in
//            self.playNext()
            print("seek \(self.index == index) \(self.positionOffset == position) \(self.playerNode.isPlaying)")
        })

        playerNode.play()

        broadcastPlaybackEvent()
    }
    
    func updatePosition(_ positionUpdate: CMTime?) {
        self.positionUpdatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        if let positionUpdate = positionUpdate { self.positionUpdate = positionUpdate  }
        self.positionOffset = indexedAudioSources.count > 0 && positionUpdate == nil ? self.playerNode.currentTime : CMTime.zero
    }

//    func playNext() {
//        DispatchQueue.main.async {
//            let newIndex = self.index + 1
//            if newIndex >= self.indexedAudioSources.count {
//                self.complete()
//            } else {
//                self.playerNode.stop()
//                try! self.enqueueFrom(newIndex)
//                self.updatePosition()
//                self.playerNode.play()
//                self.broadcastPlaybackEvent()
//            }
//        }
//    }

//    func complete() {
//        updatePosition(nil)
//        processingState = .completed
//        if playerNode != nil {
//            playerNode.stop()
//        }
//        broadcastPlaybackEvent()
//    }
    
    // ========== QUEUE

    func enqueueFrom(_ index: Int) throws {
        try! queueFrom(index)
        let source = indexedAudioSources[index]
        try! currentSource!.load(engine: engine, playerNode: playerNode, speedControl: speedControl, position: nil, completionHandler: { type in
//            self.playNext()
            print("enqueueFrom \(self.currentSource === source)  \(self.playerNode.isPlaying)")
        })
    }
    
    func queueFrom(_ index: Int) throws {
        self.index = index
        guard !indexedAudioSources.isEmpty else {
            preconditionFailure("no songs on library")
        }
        currentSource = indexedAudioSources[index]
    }

    func decodeAudioSources(data: [[String: Any]]) -> [AudioSource] {
        return data.map { item in
            try! decodeAudioSource(data: item)
        }
    }

    func decodeAudioSource(data: [String: Any]) throws -> AudioSource {
        let type = data["type"] as! String
        switch type {
        case "progressive":
            return UriAudioSource(sid: data["id"] as! String, uri: data["uri"] as! String)
        case "concatenating":
            return ConcatenatingAudioSource(sid: data["id"] as! String, audioSources: decodeAudioSources(data: data["children"] as! [Dictionary<String, Any>]), shuffleOrder: data["shuffleOrder"] as! Array<Int>)
        default:
            throw PluginError.runtimeError("data source not supported")
        }
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
            let parameters = effect["parameters"] as! [String: Any]
            switch effect["type"] as? String {
            case "DarwinEqualizer":
                let bands = parameters["bands"] as! [[String: Any]]
                audioUnitEQ = AVAudioUnitEQ(numberOfBands: bands.count)
                for (i, band) in bands.enumerated() {
                    audioUnitEQ!.bands[i].filterType = .parametric
                    audioUnitEQ!.bands[i].frequency = band["centerFrequency"] as! Float
                    audioUnitEQ!.bands[i].bandwidth = 0.5 // half an octave
                    audioUnitEQ!.bands[i].gain = Float(band["gain"] as? Double ?? 0)
                    audioUnitEQ!.bands[i].bypass = false
                }
                if let enabled = effect["enabled"] as? Bool {
                    audioUnitEQ!.bypass = !enabled
                } else {
                    audioUnitEQ!.bypass = true
                }
            default:
                throw PluginError.runtimeError("effect type not supported")
            }
        }
    }

    func enableEffect(type: String, enabled: Bool) throws {
        switch type {
        case "DarwinEqualizer":
            audioUnitEQ!.bypass = !enabled
        default:
            throw PluginError.runtimeError("effect type not supported")
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
        onEvent([
            "processingState": processingState.rawValue,
            "updatePosition": self.currentPosition.microSeconds,
            "updateTime": self.positionUpdatedAt,
            "bufferedPosition": 0,
            "icyMetadata": [:],
            "duration": duration.microSeconds,
            "currentIndex": index,
        ])
    }

    func dispose() {
        if processingState != .none {
            playerNode.pause()
            processingState = .none
        }
        audioSource = nil
        indexedAudioSources = []
        playerNode.stop()
        engine.stop()
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
    
    static func loopModeFrom(value: Int) -> LoopMode {
        switch (value) {
        case 1:
            return LoopMode.loopOne
        case 2:
            return LoopMode.loopAll
        default:
            return LoopMode.loopOff
        }
    }
    
    static func shuffleModeFrom(value: Int) -> Bool {
        return value == 1
    }
}
