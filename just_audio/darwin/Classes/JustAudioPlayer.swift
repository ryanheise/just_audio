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

    let audioEffects: [[String: Any]]

    var engine: AVAudioEngine!
    var playerNode: AVAudioPlayerNode!
    var speedControl: AVAudioUnitVarispeed!
    var audioUnitEQ: AVAudioUnitEQ?

    var playing = false
    var processingState: ProcessingState = .none
    var shuffleModeEnabled = false
    var loopMode: LoopMode = .loopOff
    var loadResult: FlutterResult?
    var index: Int = 0
    var audioSource: AudioSource!
    var indexedAudioSources: [IndexedAudioSource] = []

    var currentSource: IndexedAudioSource?

    var offeset: Double = 0
    var currentPosition: CMTime = .zero
    var updateTime: Int64 = 0
    var savedCurrentTime: AVAudioTime?
    var order: [Int] = []
    var orderInv: [Int] = []

    var volume: Float = 1
    var rate: Float = 1

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
            let request = call.arguments as! [String: Any]
            switch call.method {
            case "load":
                print("========== load:", request)
                let initialPosition = request["initialPosition"] != nil ? CMTime.invalid : CMTimeMake(value: request["initialPosition"] as! Int64, timescale: 1_000_000)
                try load(source: request["audioSource"] as! [String: Any], initialPosition: initialPosition, initialIndex: request["initialIndex"] as? Int ?? 0, result: result)
            case "play":
                playerNode.play()
                updatePosition()
                broadcastPlaybackEvent()
                result([:])
            case "pause":
                updatePosition()
                playerNode.pause()
                broadcastPlaybackEvent()
                result([:])
            case "setVolume":
                volume = Float(request["volume"] as? Double ?? 1)
                if playerNode != nil {
                    playerNode.volume = volume
                }
                broadcastPlaybackEvent()
                result([:])
            case "setSkipSilence":
                print("TODO: setSkipSilence", request)
                result([:])
            case "setSpeed":
                rate = Float(request["speed"] as? Double ?? 1)
                if speedControl != nil {
                    speedControl.rate = rate
                }
                updatePosition()
                result([:])
            case "setLoopMode":
                toggleLoopMode()
                result([:])
            case "setShuffleMode":
                toggleShuffleMode(shuffleMode: request["shuffleMode"] as? Int ?? 0)
                updateOrder()
                broadcastPlaybackEvent()
                print("TODO: setShuffleMode", request)
                result([:])
            case "setShuffleOrder":
                print("TODO: setShuffleOrder", request)
                result([:])
            case "setAutomaticallyWaitsToMinimizeStalling":
                print("TODO: setAutomaticallyWaitsToMinimizeStalling", request)
                result([:])
            case "setCanUseNetworkResourcesForLiveStreamingWhilePaused":
                print("TODO: setCanUseNetworkResourcesForLiveStreamingWhilePaused", request)
                result([:])
            case "setPreferredPeakBitRate":
                print("TODO: setPreferredPeakBitRate", request)
                result([:])
            case "seek":
                print("========== seek", request)
                // microseconds
                let position = CMTimeMake(value: request["position"] as? Int64 ?? 0, timescale: 1_000_000)
                let index = request["index"] as? Int ?? 0

                print("\(position.seconds) \(position.milliSeconds) \(position.value) \(position.timescale)")

                seek(position: position, index: index, completionHandler: {
                    result([:])
                })
            case "concatenatingInsertAll":
                print("TODO: concatenatingInsertAll", request)
                result([:])
            case "concatenatingRemoveRange":
                print("TODO: concatenatingRemoveRange", request)
                result([:])
            case "concatenatingMove":
                print("TODO: concatenatingMove", request)
                result([:])
            case "setAndroidAudioAttributes":
                print("TODO: setAndroidAudioAttributes", request)
                result([:])
            case "audioEffectSetEnabled":
                try! enableEffect(type: request["type"] as! String, enabled: request["enabled"] as! Bool)
                result([:])
            case "darwinEqualizerBandSetGain":
                setEqualizerBandGain(bandIndex: request["bandIndex"] as! Int, gain: Float(request["gain"] as! Double))
                result([:])
            default:
                result(FlutterMethodNotImplemented)
            }
        } catch {
            let flutterError = FlutterError(code: "error", message: "Error in handleMethodCall", details: nil)
            result(flutterError)
        }
    }

    private func toggleLoopMode() {
        switch loopMode {
        case .loopOff:
            loopMode = .loopOne
        case .loopOne:
            loopMode = .loopAll
        case .loopAll:
            loopMode = .loopOff
        }
    }

    private func toggleShuffleMode(shuffleMode: Int) {
        switch shuffleMode {
        case 1:
            shuffleModeEnabled = true
        default:
            shuffleModeEnabled = false
        }
    }

    func load(source: [String: Any], initialPosition _: CMTime, initialIndex: Int, result: @escaping FlutterResult) throws {
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

            for i in 1 ..< nodes.count {
                engine.connect(nodes[i - 1]!, to: nodes[i]!, format: nil)
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

    func seek(position: CMTime, index: Int, completionHandler: () -> Void) {
        try! enqueueFrom(index)

        playerNode.stop()

        currentPosition = position
        updateTime = Int64(Date().timeIntervalSince1970 * 1000)

        processingState = .ready

        let sampleRate = currentSource?.getSampleRate() ?? 0
        let newsampletime = AVAudioFramePosition(sampleRate * position.seconds)

        let length = Float(currentSource?.getDuration() ?? 0) - Float(position.seconds)
        let framestoplay = AVAudioFrameCount(Float(sampleRate) * length)

        if framestoplay > 1000 {
            let uri = (currentSource as! UriAudioSource).uri
            let url = uri.starts(with: "ipod-library://") ? URL(string: uri)! : URL(fileURLWithPath: uri)

            let audioFile = try! AVAudioFile(forReading: url)

            playerNode.scheduleSegment(audioFile, startingFrame: newsampletime, frameCount: framestoplay, at: nil, completionHandler: nil)
        }

        playerNode.play()

        broadcastPlaybackEvent()
        completionHandler()
    }

    func playNext() {
        DispatchQueue.main.async {
            let newIndex = self.index + 1
            if newIndex >= self.indexedAudioSources.count {
                self.complete()
            } else {
                self.playerNode.stop()
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
            order = indexedAudioSources.enumerated().map { index, _ in
                index
            }
        }
        for i in 0 ..< indexedAudioSources.count {
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
            "updatePosition": currentPosition.microSeconds,
            "updateTime": updateTime,
            "bufferedPosition": 0,
            "icyMetadata": [:],
            "duration": getDurationMicroseconds(),
            "currentIndex": index,
        ])
    }

    func complete() {
        updatePosition()
        processingState = .completed
        if playerNode != nil {
            playerNode.stop()
        }
        broadcastPlaybackEvent()
    }

    func getCurrentPosition() -> CMTime {
        if indexedAudioSources.count > 0 {
            guard let lastRenderTime = playerNode.lastRenderTime else { return CMTime.zero }
            guard let playerTime = playerNode.playerTime(forNodeTime: lastRenderTime) else { return CMTime.zero }
            let sampleRate = playerTime.sampleRate
            let sampleTime = playerTime.sampleTime
            let currentTime = Double(sampleTime) / sampleRate
            let milliSeconds = Int64(currentTime * 1000)
            return milliSeconds < 0 ? CMTime.zero : CMTime(value: milliSeconds, timescale: 1000)
        } else {
            return CMTime.zero
        }
    }

    func getDuration() -> Int {
        if processingState == .none || processingState == .loading {
            return -1
        } else if indexedAudioSources.count > 0 {
            return Int(1000 * currentSource!.getDuration())
        } else {
            return 0
        }
    }

    func getDurationMicroseconds() -> Int64 {
        let duration = getDuration()
        return duration < 0 ? -1 : Int64(1000 * duration)
    }

    func enqueueFrom(_ index: Int) throws {
        self.index = index
        guard !indexedAudioSources.isEmpty else {
            preconditionFailure("no songs on library")
        }
        currentSource = indexedAudioSources[index]
        print("Index:\(index) \(indexedAudioSources.description)")
        try! currentSource!.load(engine: engine, playerNode: playerNode, speedControl: speedControl, completionHandler: { type in
//            self.playNext()
            print("CompletionHandler \(type.rawValue)")
        })
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
            return ConcatenatingAudioSource(sid: data["id"] as! String, audioSources: decodeAudioSources(data: data["children"] as! [[String: Any]]))
        default:
            throw PluginError.runtimeError("data source not supported")
        }
    }

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

    func dispose() {
        if playerNode == nil {
            return
        }
        if processingState != .none {
            playerNode.pause()
            processingState = .none
        }
        audioSource = nil
        indexedAudioSources = []
        if playerNode != nil {
            playerNode.stop()
            playerNode = nil
        }
        if engine != nil {
            engine.stop()
            engine = nil
        }
        eventChannel.dispose()
        dataChannel.dispose()
        methodChannel.setMethodCallHandler(nil)
    }
}

extension CMTime {
    var milliSeconds: Int64 {
        return Int64(value * 1000 / Int64(timescale))
    }

    var microSeconds: Int64 {
        return Int64(value * 1_000_000 / Int64(timescale))
    }
}

extension AVAudioPlayerNode {
    var currentTime: Double {
        if let nodeTime: AVAudioTime = lastRenderTime, let playerTime: AVAudioTime = playerTime(forNodeTime: nodeTime) {
            return Double(playerTime.sampleTime) / playerTime.sampleRate
        }
        return 0.0
    }
}
