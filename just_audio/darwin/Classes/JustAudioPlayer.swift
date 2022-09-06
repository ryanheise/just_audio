import AVFoundation

public class JustAudioPlayer: NSObject {
    let playerId: String
    let audioEffects: [[String: Any]]

    let methodChannel: FlutterMethodChannel
    let eventChannel: BetterEventChannel
    let dataChannel: BetterEventChannel

    var player: Player!

    init(registrar _: FlutterPluginRegistrar,
         playerId: String,
         loadConfiguration _: [String: Any],
         audioEffects: [[String: Any]],
         methodChannel: FlutterMethodChannel,
         eventChannel: BetterEventChannel,
         dataChannel: BetterEventChannel)
    {
        self.playerId = playerId
        self.audioEffects = audioEffects

        self.methodChannel = methodChannel
        self.eventChannel = eventChannel
        self.dataChannel = dataChannel

        super.init()
        methodChannel.setMethodCallHandler { call, result in
            self.handleMethodCall(call: call, result: result)
        }
    }

    func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            if player == nil {
                player = Player(audioEffects: try! audioEffects.map(Util.effectFrom), onEvent: onPlaybackEvent)
            }

            let request = call.arguments as! [String: Any]
            print("=========== \(call.method) \(request)")

            switch call.method {
            case "load":
                let source = try AudioSource.fromJson(request["audioSource"] as! [String: Any])
                let initialPosition = request["initialPosition"] != nil ? CMTime.invalid : CMTimeMake(value: request["initialPosition"] as! Int64, timescale: 1_000_000)
                let initialIndex = request["initialIndex"] as? Int ?? 0

                let duration = player.load(source: source, initialPosition: initialPosition, initialIndex: initialIndex)
                result(["duration": duration.microseconds])
            case "play":
                player.play()
                result([:])
            case "pause":
                player.pause()
                result([:])
            case "stop":
                player.stop()
                result([:])
            case "setVolume":
                player.setVolume(Float(request["volume"] as! Double))
                result([:])
            case "setPitch":
                player.setPitch(Float(request["pitch"] as! Double))
                result([:])
            case "setSkipSilence":
                // TODO: player.setSkipSilence(request["enabled"] as! Bool)
                result(NotImplementedError(call.method))
            case "setSpeed":
                player.setSpeed(Float(request["speed"] as! Double))
                result([:])
            case "setLoopMode":
                player.setLoopMode(mode: Util.loopModeFrom(request["loopMode"] as! Int))
                result([:])
            case "setShuffleMode":
                // it can be random or normal
                player.setShuffleMode(isEnalbed: Util.shuffleModeFrom(request["shuffleMode"] as! Int))
                result([:])
            case "setShuffleOrder":
                // TODO: TEST
                player.setShuffleOrder(data: request["audioSource"] as! [String: Any])
                result([:])
            case "setAutomaticallyWaitsToMinimizeStalling":
                // android is still to be implemented too
                result(NotImplementedError(call.method))
            case "setCanUseNetworkResourcesForLiveStreamingWhilePaused":
                // even android is still to be implemented too
                result(NotImplementedError(call.method))
            case "setPreferredPeakBitRate":
                // even android is still to be implemented too
                result(NotImplementedError(call.method))
            case "setClip":
                // even android is still to be implemented too
                result(NotImplementedError(call.method))
            case "seek":
                let position = Util.timeFrom(microseconds: request["position"] as! Int64)
                let index = request["index"] as? Int

                player.seek(index: index, position: position)
                result([:])
            case "concatenatingInsertAll":
                result(NotImplementedError(call.method))
            case "concatenatingRemoveRange":
                result(NotImplementedError(call.method))
            case "concatenatingMove":
                result(NotImplementedError(call.method))
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
        } catch {
            print(error)
            result(FlutterError(code: "500", message: error.localizedDescription, details: nil))
        }
    }

    func onPlaybackEvent(event: PlaybackEvent) {
        eventChannel.sendEvent([
            "processingState": event.processingState.rawValue,
            "updatePosition": event.updatePosition.microseconds,
            "updateTime": event.updateTime,
            "bufferedPosition": 0,
            "icyMetadata": [:],
            "duration": event.duration.microseconds,
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
