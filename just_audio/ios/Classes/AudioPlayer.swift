import AudioKit

enum ProcessingState: Int {
    case none, loading, buffering, ready, completed
}

enum LoopMode: Int {
    case loopOff, loopOne, loopAll
}

public class AudioPlayer: NSObject {
    let playerId: String
    let methodChannel: FlutterMethodChannel
    let eventChannel: BetterEventChannel
    let dataChannel: BetterEventChannel
    
    var engine: AudioEngine? = nil
    var playing = false
    var processingState: ProcessingState = .none
    var loopMode: LoopMode = .loopOff
    var loadResult: FlutterResult? = nil
    var index: Int = 0
    
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
                load(source: request["audioSource"] as! Dictionary<String, Any>, initialPosition: initialPosition, initialIndex: request["initialIndex"] as? Int ?? 0, result: result)
                break
            case "play":
                result([:])
                break
            case "pause":
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
    
    func load(source: Dictionary<String, Any>, initialPosition: CMTime, initialIndex: Int, result: @escaping FlutterResult) {
        if playing {
            // TODO: pause player
        }
        if processingState == .loading {
            // TODO: abort existing connection
        }
        loadResult = result
        index = initialIndex
        processingState = .loading
        // TODO: update position
        // TODO: decode audio source
        // TODO: update order
        if engine != nil {
            engine = AudioEngine()
        }
    }
    
    func dispose() {
        print("dispose player")
    }
}
