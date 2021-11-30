import AVFoundation

enum PluginError: Error {
    case runtimeError(String)
}

enum ProcessingState: Int {
    case none, loading, buffering, ready, completed
}

enum LoopMode: Int {
    case loopOff, loopOne, loopAll
}

public class JustAudioPlayer: NSObject {
    let playerId: String
    let methodChannel: FlutterMethodChannel
    let eventChannel: BetterEventChannel
    let dataChannel: BetterEventChannel
    
    let audioEffects: [Dictionary<String, Any>]
    
    var engine: AVAudioEngine!
    var playerNode: AVAudioPlayerNode!
    var speedControl: AVAudioUnitVarispeed!
    var audioUnitEQ: AVAudioUnitEQ?

    var playing = false
    var processingState: ProcessingState = .none
    var shuffleModeEnabled = false
    var loopMode: LoopMode = .loopOff
    var loadResult: FlutterResult? = nil
    var index: Int = 0
    var audioSource: AudioSource!
    var indexedAudioSources: [IndexedAudioSource] = []
    
    var currentSource: IndexedAudioSource? = nil
    
    var offeset: Double = 0
    var currentPosition: Int = 0
    var updateTime: Int64 = 0
    var savedCurrentTime: AVAudioTime? = nil
    var order: [Int] = []
    var orderInv: [Int] = []
    
    var volume: Float = 1
    var rate: Float = 1
    
    init(registrar: FlutterPluginRegistrar, playerId: String, loadConfiguration: Dictionary<String, Any>, audioEffects: [Dictionary<String, Any>]) {
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
    
    func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult){
        do {
            let request = call.arguments as! Dictionary<String, Any>
            switch call.method {
            case "load":
                print("load:", request)
                let initialPosition = request["initialPosition"] != nil ? CMTime.invalid : CMTimeMake(value: request["initialPosition"] as! Int64, timescale: 1000000)
                try load(source: request["audioSource"] as! Dictionary<String, Any>, initialPosition: initialPosition, initialIndex: request["initialIndex"] as? Int ?? 0, result: result)
                break
            case "play":
                playerNode.play()
                updatePosition()
                broadcastPlaybackEvent()
                result([:])
                break
            case "pause":
                updatePosition()
                playerNode.pause()
                broadcastPlaybackEvent()
                result([:])
                break
            case "setVolume":
                volume = Float(request["volume"] as? Double ?? 1)
                if playerNode != nil {
                    playerNode.volume = volume
                }
                broadcastPlaybackEvent()
                result([:])
                break
            case "setSkipSilence":
                print("TODO: setSkipSilence", request)
                result([:])
                break
            case "setSpeed":
                rate = Float(request["speed"] as? Double ?? 1)
                if speedControl != nil {
                    speedControl.rate = rate
                }
                updatePosition()
                result([:])
                break
            case "setLoopMode":
                print("TODO: setLoopMode", request)
                result([:])
                break
            case "setShuffleMode":
                print("TODO: setShuffleMode", request)
                result([:])
                break
            case "setShuffleOrder":
                print("TODO: setShuffleOrder", request)
                result([:])
                break
            case "setAutomaticallyWaitsToMinimizeStalling":
                print("TODO: setAutomaticallyWaitsToMinimizeStalling", request)
                result([:])
                break
            case "setCanUseNetworkResourcesForLiveStreamingWhilePaused":
                print("TODO: setCanUseNetworkResourcesForLiveStreamingWhilePaused", request)
                result([:])
                break
            case "setPreferredPeakBitRate":
                print("TODO: setPreferredPeakBitRate", request)
                result([:])
                break
            case "seek":
                let position = request["position"] == nil ? CMTime.invalid : CMTimeMake(value: request["position"] as! Int64, timescale: 1000000)
                seek(position: position, index: request["index"] as? Int ?? 0) {
                    result([:])
                }
                break
            case "concatenatingInsertAll":
                print("TODO: concatenatingInsertAll", request)
                result([:])
                break
            case "concatenatingRemoveRange":
                print("TODO: concatenatingRemoveRange", request)
                result([:])
                break
            case "concatenatingMove":
                print("TODO: concatenatingMove", request)
                result([:])
                break
            case "setAndroidAudioAttributes":
                print("TODO: setAndroidAudioAttributes", request)
                result([:])
                break
            case "audioEffectSetEnabled":
                try! enableEffect(type: request["type"] as! String, enabled: request["enabled"] as! Bool)
                result([:])
                break
            case "darwinEqualizerBandSetGain":
                setEqualizerBandGain(bandIndex: request["bandIndex"] as! Int, gain: Float(request["gain"] as! Double))
                result([:])
                break
            default:
                result(FlutterMethodNotImplemented)
                break
            }
        } catch {
            let flutterError = FlutterError(code: "error", message: "Error in handleMethodCall", details: nil)
            result(flutterError)
        }
    }
    
    func load(source: Dictionary<String, Any>, initialPosition: CMTime, initialIndex: Int, result: @escaping FlutterResult) throws {
        if playerNode != nil {
            playerNode.pause()
        }
        
        loadResult = result
        index = initialIndex
        processingState = .loading
        updatePosition()
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
            
            for i in 1..<nodes.count {
                engine.connect(nodes[i-1]!, to:nodes[i]!, format: nil)
            }
        }
        
        try! enqueueFrom(index)
        
        if !engine.isRunning {
            try! engine.start()
        }
        
        processingState = .ready
        
        loadResult?(["duration": getDurationMicroseconds()])
        loadResult = nil
        
        broadcastPlaybackEvent()
    }
    
    func seek(position: CMTime, index: Int, completionHandler: () -> Void){
        try! enqueueFrom(index)
        self.updatePosition()
        self.processingState = .ready
        self.playerNode.play()
        self.broadcastPlaybackEvent()
        completionHandler()
    }
    
    func playNext() {
        DispatchQueue.main.async {
            let newIndex = self.index + 1
            if newIndex >= self.indexedAudioSources.count {
                self.complete()
            } else {
                try! self.enqueueFrom(newIndex)
                self.updatePosition()
                self.playerNode.play()
                self.broadcastPlaybackEvent()
            }
        }
    }
    
    func updateOrder() {
        orderInv = Array(repeating: 0, count: indexedAudioSources.count)
        if shuffleModeEnabled {
            order = audioSource.getShuffleIndices()
        } else {
            order = indexedAudioSources.enumerated().map({ (index, _) in
                return index
            })
        }
        for i in 0..<indexedAudioSources.count {
            orderInv[order[i]] = i
        }
    }
    
    func updatePosition() {
        currentPosition = getCurrentPosition()
        updateTime = Int64(Date().timeIntervalSince1970 * 1000)
    }
    
    func broadcastPlaybackEvent() {
        eventChannel.sendEvent([
            "processingState": processingState.rawValue,
            "updatePosition": Int64(currentPosition * 1000),
            "updateTime": updateTime,
            "bufferedPosition": 0,
            "icyMetadata": [:],
            "duration": getDurationMicroseconds(),
            "currentIndex": index
        ])
    }
    
    func complete() {
        updatePosition()
        processingState = .completed
        self.playerNode.stop()
        broadcastPlaybackEvent()
    }
    
    func getCurrentPosition() -> Int {
        if (indexedAudioSources.count > 0) {
            guard let lastRenderTime = playerNode.lastRenderTime else { return 0 }
            guard let playerTime = playerNode.playerTime(forNodeTime: lastRenderTime) else { return 0 }
            let sampleRate = playerTime.sampleRate
            let sampleTime = playerTime.sampleTime
            let currentTime = Double(sampleTime) / sampleRate
            let ms = Int(currentTime * 1000);
            return ms < 0 ? 0 : ms
        } else {
            return 0
        }
    }
    
    func getDuration() -> Int {
        if processingState == .none || processingState == .loading {
            return -1
        }else if indexedAudioSources.count > 0 {
            return Int(1000 * currentSource!.getDuration())
        }else {
            return 0
        }
    }
    
    func getDurationMicroseconds() -> Int64 {
        let duration = getDuration()
        return duration < 0 ? -1 : Int64(1000 * duration)
    }
    
    func enqueueFrom(_ index: Int) throws {
        self.index = index
        
        currentSource = indexedAudioSources[index]
        try! currentSource!.load(engine: engine, playerNode: playerNode, speedControl: speedControl, completionHandler: { _ in
            self.playNext()
        })
    }
    
    func decodeAudioSources(data: [Dictionary<String, Any>]) -> [AudioSource] {
        return data.map { item in
            return try! decodeAudioSource(data: item)
        }
    }
    
    func decodeAudioSource(data: Dictionary<String, Any>) throws -> AudioSource {
        let type = data["type"] as! String
        switch type {
        case "progressive":
            return UriAudioSource(sid: data["id"] as! String, uri: data["uri"] as! String)
        case "concatenating":
            return ConcatenatingAudioSource(sid: data["id"] as! String, audioSources: decodeAudioSources(data: data["children"] as! [Dictionary<String, Any>]), shuffleOrder: [])
        default:
            throw PluginError.runtimeError("data source not supported")
        }
    }
    
    func createAudioEffects() throws {
        for effect in audioEffects {
            let parameters = effect["parameters"] as! Dictionary<String, Any>
            switch effect["type"] as? String {
            case "DarwinEqualizer":
                let bands = parameters["bands"] as! [Dictionary<String, Any>]
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
                }else {
                    audioUnitEQ!.bypass = true
                }
                break;
            default:
                throw PluginError.runtimeError("effect type not supported")
            }
        }
    }
    
    func enableEffect(type: String, enabled: Bool) throws {
        switch type {
        case "DarwinEqualizer":
            audioUnitEQ!.bypass = !enabled
            break;
        default:
            throw PluginError.runtimeError("effect type not supported")
        }
    }
    
    func setEqualizerBandGain(bandIndex: Int, gain: Float) {
        audioUnitEQ?.bands[bandIndex].gain = gain
    }
    
    func dispose() {
        print("dispose player")
    }
}
