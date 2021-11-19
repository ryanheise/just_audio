import AVFAudio

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
    
    var engine: AVAudioEngine!
    var player: AVAudioPlayerNode!
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
    
    init(registrar: FlutterPluginRegistrar, playerId: String, loadConfiguration: Dictionary<String, Any>) {
        self.playerId = playerId
        methodChannel = FlutterMethodChannel(name: String(format: "com.ryanheise.just_audio.methods.%@", playerId), binaryMessenger: registrar.messenger())
        eventChannel = BetterEventChannel(name: String(format: "com.ryanheise.just_audio.events.%@", playerId), messenger: registrar.messenger())
        dataChannel = BetterEventChannel(name: String(format: "com.ryanheise.just_audio.data.%@", playerId), messenger: registrar.messenger())
        
        print(loadConfiguration)
        
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
                let initialPosition = request["initialPosition"] != nil ? CMTime.invalid : CMTimeMake(value: request["initialPosition"] as! Int64, timescale: 1000000)
                try load(source: request["audioSource"] as! Dictionary<String, Any>, initialPosition: initialPosition, initialIndex: request["initialIndex"] as? Int ?? 0, result: result)
                break
            case "play":
                player.play()
                updatePosition()
                broadcastPlaybackEvent()
                result([:])
                break
            case "pause":
                updatePosition()
                player.pause()
                broadcastPlaybackEvent()
                result([:])
                break
            case "setVolume":
                print("TODO: setVolume")
                result([:])
                break
            case "setSkipSilence":
                print("TODO: setSkipSilence")
                result([:])
                break
            case "setSpeed":
                print("TODO: setSpeed")
                result([:])
                break
            case "setLoopMode":
                print("TODO: setLoopMode")
                result([:])
                break
            case "setShuffleMode":
                print("TODO: setShuffleMode")
                result([:])
                break
            case "setShuffleOrder":
                print("TODO: setShuffleOrder")
                result([:])
                break
            case "setAutomaticallyWaitsToMinimizeStalling":
                print("TODO: setAutomaticallyWaitsToMinimizeStalling")
                result([:])
                break
            case "setCanUseNetworkResourcesForLiveStreamingWhilePaused":
                print("TODO: setCanUseNetworkResourcesForLiveStreamingWhilePaused")
                result([:])
                break
            case "setPreferredPeakBitRate":
                print("TODO: setPreferredPeakBitRate")
                result([:])
                break
            case "seek":
                print("TODO: seek")
                result([:])
                break
            case "concatenatingInsertAll":
                print("TODO: concatenatingInsertAll")
                result([:])
                break
            case "concatenatingRemoveRange":
                print("TODO: concatenatingRemoveRange")
                result([:])
                break
            case "concatenatingMove":
                print("TODO: concatenatingMove")
                result([:])
                break
            case "setAndroidAudioAttributes":
                print("TODO: setAndroidAudioAttributes")
                result([:])
                break
            default:
                result(FlutterMethodNotImplemented)
            }
        } catch {
            let flutterError = FlutterError(code: "error", message: "Error in handleMethodCall", details: nil)
            result(flutterError)
        }
    }
    
    func load(source: Dictionary<String, Any>, initialPosition: CMTime, initialIndex: Int, result: @escaping FlutterResult) throws {
        if player != nil {
            player.pause()
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
            player = AVAudioPlayerNode()
            
            engine.attach(player)
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
    
    func playNext() {
        DispatchQueue.main.async {
            let newIndex = self.index + 1
            if newIndex >= self.indexedAudioSources.count {
                self.complete()
            } else {
                try! self.enqueueFrom(newIndex)
                self.updatePosition()
                self.player.play()
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
        broadcastPlaybackEvent()
    }
    
    func getCurrentPosition() -> Int {
        if (indexedAudioSources.count > 0) {
            guard let lastRenderTime = player.lastRenderTime else { return 0 }
            guard let playerTime = player.playerTime(forNodeTime: lastRenderTime) else { return 0 }
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
        try! currentSource!.load(engine: engine, player: player, completionHandler: { _ in
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
    
    func dispose() {
        print("dispose player")
    }
}
