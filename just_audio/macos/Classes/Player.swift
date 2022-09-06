//
//  Player.swift
//  just_audio
//
//  Created by kuama on 22/08/22.
//

import Foundation

class Player {
    let onEvent: (PlaybackEvent) -> Void
    let audioEffects: [EffectData]

    var engine: AVAudioEngine!
    var playerNode: AVAudioPlayerNode!
    var speedControl: AVAudioUnitVarispeed!
    var pitchControl: AVAudioUnitTimePitch!
    var audioUnitEQ: AVAudioUnitEQ?

    // State properties
    var processingState: ProcessingState = .none
    var shuffleModeEnabled = false
    var loopMode: LoopMode = .loopOff

    // Queue properties
    var indexedAudioSources: [IndexedAudioSource] = []
    var currentSource: IndexedAudioSource?
    var order: [Int] = []
    var reverseOrder: [Int] = []

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
    var pitch: Float = 1
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

        if indexedAudioSources.isEmpty {
            processingState = .none
            broadcastPlaybackEvent()

            return CMTime.zero
        }

        if engine == nil {
            engine = AVAudioEngine()
            playerNode = AVAudioPlayerNode()
            speedControl = AVAudioUnitVarispeed()
            pitchControl = AVAudioUnitTimePitch()

            try! createAudioEffects()

            playerNode.volume = volume
            speedControl.rate = rate
            pitchControl.pitch = pitch

            var nodes = [playerNode, speedControl, pitchControl]

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
                                                   object: nil)
        }

        try! setQueueFrom(index)

        loadCurrentSource()

        if !engine.isRunning {
            try! engine.start()
        }

        processingState = .ready
        broadcastPlaybackEvent()

        return duration
    }

    @objc func _handleInterruption(notification _: Notification) {
        resume()
    }

    func play() {
        playPlayerNode()
        updatePosition(nil)
        broadcastPlaybackEvent()
    }

    func pause() {
        updatePosition(nil)
        playerNode.pause()
        broadcastPlaybackEvent()
    }

    func stop() {
        stopPlayerNode()
        updatePosition(nil)
        broadcastPlaybackEvent()
    }

    func resume() {
        let wasPlaying = playerNode.isPlaying

        playerNode.pause()
        if !engine.isRunning {
            try! engine.start()
        }

        if wasPlaying {
            playerNode.play()
        }
    }

    func seek(index: Int?, position: CMTime) {
        let wasPlaying = playerNode.isPlaying

        if let index = index {
            try! setQueueFrom(index)
        }

        stopPlayerNode()

        updatePosition(position)

        processingState = .ready

        loadCurrentSource()

        // Restart play if player was playing
        if wasPlaying {
            playPlayerNode()
        }

        broadcastPlaybackEvent()
    }

    func updatePosition(_ positionUpdate: CMTime?) {
        positionUpdatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        if let positionUpdate = positionUpdate { self.positionUpdate = positionUpdate }
        positionOffset = indexedAudioSources.count > 0 && positionUpdate == nil ? playerNode.currentTime : CMTime.zero
    }

    private var isStopping = false
    // Permit to check if [load(completionHandler)] is called when you force a stop
    private func stopPlayerNode() {
        isStopping = true
        playerNode.stop()
        isStopping = false
    }

    private func playPlayerNode() {
        if !engine.isRunning {
            try! engine.start()
        }
        playerNode.play()
    }

    private func loadCurrentSource() {
        try! currentSource!.load(engine: engine, playerNode: playerNode, speedControl: speedControl, position: positionUpdate, completionHandler: {
            if self.isStopping { return }
            DispatchQueue.main.async {
                self.playNext()
            }
        })
    }

    private func getRelativeIndex(_ offset: Int) -> Int {
        switch loopMode {
        case .loopOne:
            return index
        case .loopAll:
            return offset >= indexedAudioSources.count ? 0 : reverseOrder[offset]
        case .loopOff:
            return reverseOrder[offset]
        }
    }

    private func playNext() {
        let newIndex = index + 1
        if newIndex >= indexedAudioSources.count {
            complete()
        } else {
            seek(index: getRelativeIndex(newIndex), position: CMTime.zero)
            play()
        }
    }

    private func complete() {
        updatePosition(nil)
        processingState = .completed
        if playerNode != nil {
            playerNode.stop()
        }
        broadcastPlaybackEvent()
    }

    // MARK: QUEUE

    fileprivate func setQueueFrom(_ index: Int) throws {
        guard !indexedAudioSources.isEmpty else {
            preconditionFailure("no songs on library")
        }
        self.index = index
        currentSource = indexedAudioSources[index]
    }

    // MARK: MODES

    func setShuffleMode(isEnalbed: Bool) {
        shuffleModeEnabled = isEnalbed
        updateOrder()
        broadcastPlaybackEvent()
    }

    func setShuffleOrder(data: [String: Any]) {
        audioSource = try! .fromJson(data)
        switch data["type"] as! String {
        case "concatenating":
            let children = (data["children"] as! [[String: Any]])
            for child in children {
                setShuffleOrder(data: child)
            }
        case "looping":
            setShuffleOrder(data: data["child"] as! [String: Any])
        default:
            break
        }
    }

    func setLoopMode(mode: LoopMode) {
        loopMode = mode
        broadcastPlaybackEvent()
    }

    fileprivate func updateOrder() {
        reverseOrder = Array(repeating: 0, count: indexedAudioSources.count)
        if shuffleModeEnabled {
            order = audioSource.getShuffleIndices()
        } else {
            order = indexedAudioSources.enumerated().map { index, _ in
                index
            }
        }
        for i in 0 ..< indexedAudioSources.count {
            reverseOrder[order[i]] = i
        }
    }

    // MARK: EFFECTS

    fileprivate func createAudioEffects() throws {
        for effect in audioEffects {
            if let effect = effect as? EqualizerEffectData {
                audioUnitEQ = AVAudioUnitEQ(numberOfBands: effect.parameters.bands.count)

                for (i, band) in effect.parameters.bands.enumerated() {
                    audioUnitEQ!.bands[i].filterType = .parametric
                    audioUnitEQ!.bands[i].frequency = band.centerFrequency
                    audioUnitEQ!.bands[i].bandwidth = 1 // half an octave
                    audioUnitEQ!.bands[i].gain = Util.gainFrom(band.gain)
                    audioUnitEQ!.bands[i].bypass = false
                }

                audioUnitEQ!.bypass = !effect.enabled
            } else {
                throw NotSupportedError(value: effect.type, "When initialize effect")
            }
        }
    }

    func enableEffect(type: String, enabled: Bool) throws {
        switch type {
        case "DarwinEqualizer":
            audioUnitEQ!.bypass = !enabled
        default:
            throw NotInitializedError("Not initialized effect \(type)")
        }
    }

    func setEqualizerBandGain(bandIndex: Int, gain: Float) {
        audioUnitEQ?.bands[bandIndex].gain = gain
    }

    // MARK: EXTRA

    func setVolume(_ value: Float) {
        volume = value
        if playerNode != nil {
            playerNode.volume = volume
        }
        broadcastPlaybackEvent()
    }

    func setPitch(_ value: Float) {
        pitch = value
        if pitchControl != nil {
            pitchControl.pitch = pitch
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

    fileprivate func broadcastPlaybackEvent() {
        onEvent(PlaybackEvent(
            processingState: processingState,
            updatePosition: currentPosition,
            updateTime: positionUpdatedAt,
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
