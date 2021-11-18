import AudioKit

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
    
    let player = AudioPlayer()
    var engine = AudioEngine()
    var playing = false
    var processingState: ProcessingState = .none
    var shuffleModeEnabled = false
    var loopMode: LoopMode = .loopOff
    var loadResult: FlutterResult? = nil
    var index: Int = 0
    var audioSource: AudioSource!
    var indexedAudioSources: [IndexedAudioSource] = []
    var currentPosition: TimeInterval = 0
    
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
                player.play(from: currentPosition)
                result([:])
                break
            case "pause":
                currentPosition = player.getCurrentTime()
                player.pause()
                result([:])
                break
            case "setVolume":
                result([:])
                break
            case "setSkipSilence":
                result([:])
                break
            case "setSpeed":
                result([:])
                break
            case "setLoopMode":
                result([:])
                break
            case "setShuffleMode":
                result([:])
                break
            case "setShuffleOrder":
                result([:])
                break
            case "setAutomaticallyWaitsToMinimizeStalling":
                result([:])
                break
            case "setCanUseNetworkResourcesForLiveStreamingWhilePaused":
                result([:])
                break
            case "setPreferredPeakBitRate":
                result([:])
                break
            case "seek":
                result([:])
                break
            case "concatenatingInsertAll":
                result([:])
                break
            case "concatenatingRemoveRange":
                result([:])
                break
            case "concatenatingMove":
                result([:])
                break
            case "setAndroidAudioAttributes":
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
        if playing {
            player.pause()
        }
        if processingState == .loading {
            // TODO: abort existing connection
        }
        loadResult = result
        index = initialIndex
        processingState = .loading
        // TODO: update position
        // Decode audio source
        audioSource = try! decodeAudioSource(data: source)
        
        indexedAudioSources = []
        _ = audioSource.buildSequence(sequence: &indexedAudioSources, treeIndex: 0)
                
        for source in indexedAudioSources {
            if !source.isAttached {
                // TODO: audioSource.playerItem.audioSource = audioSource;
                // TODO: [self addItemObservers:audioSource.playerItem];
            }
        }
        
        updateOrder()
//      TODO:  if (_player.currentItem) {
//            _index = [self indexForItem:(IndexedPlayerItem *)_player.currentItem];
//        } else:
        index = 0

        
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
    
    func broadcastPlaybackEvent() {
        eventChannel.sendEvent([
            "processingState": processingState.rawValue,
            "updatePosition": 0,
            "updateTime": 0,
            "bufferedPosition": 0,
            "icyMetadata": [:],
            "duration":Int64(1000000 * player.duration),
            "currentIndex": 0
        ])
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
