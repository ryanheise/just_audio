//
// JustAudioPlayer.swift
// kMusicSwift
// Created by Kuama Dev Team on 01/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

import AVFoundation
import Combine
import Darwin
import Foundation

public enum LoopMode {
    case off
    case one
    case all
}

/// Enumerates the different processing states of a player.
public enum ProcessingState {
    case none
    case loading
    case buffering
    case ready
    case completed
}

@available(iOS 13.0, *)
public class JustAudioPlayer {
    /**
     * Represents the time that must elapse before choose to restart a song or seek to the previous one.
     * Expressed in seconds
     */
    private static let ELAPSED_TIME_TO_RESTART_A_SONG = 5.0

    // MARK: - Event Streams

    /// whether we're currently playing a song
    @Published public private(set) var isPlaying: Bool = false

    /// the current loop mode
    @Published public private(set) var loopMode: LoopMode = .off

    /// player node volume value
    @Published public private(set) var volume: Float?

    /// player node speed
    @Published public private(set) var speed: Float?

    /// buffer duration
    @Published public private(set) var bufferPosition: Double?

    /// track duration
    @Published public private(set) var duration: Double?

    /// processing state
    @Published public private(set) var processingState: ProcessingState = .none

    /// elapsed time
    @Published public private(set) var elapsedTime: Double?

    /// tracks which track is being reproduced (currentIndexStream)
    @Published public private(set) var queueIndex: Int?

    /// equalizer node, allows to provide presets
    @Published public private(set) var equalizer: Equalizer?

    /// any errors occurred while writing the output file will be published here
    @Published public private(set) var outputWriteError: Error?

    /// the full path to the output file
    @Published public private(set) var outputAbsolutePath: String?

    @Published public private(set) var globalEffects: [AudioEffect] = []

    /// Whether the tracks in the queue are played in shuffled order
    public var isShuffling: Published<Bool>.Publisher {
        queueManager.$shouldShuffle
    }

    private var engine: AVAudioEngine!

    private var mainPlayer: SAPlayer!

    // MARK: - Http headers

    /**
     * Allows to set the http headers of the request that the player internally does to retrieve a stream or a single audio.
     * These headers are unique for player, and will be shared for all of the queued `AudioSource`
     */
    var httpHeaders: [String: String] = [:] {
        didSet {
            mainPlayer.HTTPHeaderFields = httpHeaders
        }
    }

    // MARK: - Internal state

    private var queueManager = AudioSequenceQueueManager()

    // MARK: - Notification subscriptions

    private var playingStatusSubscription: UInt?
    private var elapsedTimeSubscription: UInt?
    private var durationSubscription: UInt?
    private var streamingBufferSubscription: UInt?

    // MARK: - Constructor

    /// pass the same engine to different instance of `JustAudioPlayer` to play more track all together and handle actions and streams of the single track
    public init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
        mainPlayer = SAPlayer(engine: engine)
        subscribeToAllSubscriptions()
    }

    // MARK: - Public API

    public func addAudioSource(_ sequence: AudioSequence) {
        queueManager.addAll(sources: [sequence])
        processingState = .ready
    }

    public func removeAudioSource(at index: Int) throws {
        try queueManager.remove(at: index)
        processingState = .ready
    }

    public func addAudioEffect(_ audioEffect: AudioEffect) {
        globalEffects.append(audioEffect)
    }

    public func removeAudioEffect(_ audioEffect: AudioEffect) {
        globalEffects.removeAll { toBeChecked in
            toBeChecked.effect == audioEffect.effect
        }
    }

    public func clearAudioEffects() {
        globalEffects.removeAll()
    }

    /**
     * Starts to play the current queue of the player
     * If the player is already playing, calling this method will result in a no-op
     */
    public func play() throws {
        guard let node = mainPlayer.playerNode else {
            try scheduleAudioSource()
            return
        }

        if node.isPlaying {
            return
        } else if processingState == .completed {
            try scheduleAudioSource()
        } else {
            // player node is in pause
            processingState = .loading
            isPlaying = false
            mainPlayer.play()
        }
    }

    /**
     * Pause the player, but keeps it ready to play (`queue` will not be dropped, `queueIndex` will not change)
     */
    public func pause() {
        mainPlayer.pause()
        processingState = .ready
        isPlaying = false
    }

    /**
     * Stops the player, looses the queue and the current index
     */
    public func stop() {
        processingState = .none
        mainPlayer.stopStreamingRemoteAudio()
        mainPlayer.playerNode?.stop()
        engine.stop()
        queueManager.clear()
        queueIndex = 0
        unsubscribeUpdates()
        equalizer = nil
        isPlaying = false
    }

    /// seek to a determinate value, default is 10 second forward
    public func seek(second: Double = 10.0, index: Int? = nil) {
        if let nextTrackIndex = index, queueIndex != index {
            do {
                if let track = try tryMoveToTrack(index: nextTrackIndex) {
                    processingState = .loading
                    play(track: track)
                }
            } catch {
                print("Ignoring seek to \(nextTrackIndex) since no such index exists inside the queue")
            }

            return
        }
        mainPlayer.seekTo(seconds: second)
        processingState = .ready
    }

    /// Skip to the next item
    public func seekToNext() throws {
        if let track = try tryMoveToNextTrack(isForced: true) {
            processingState = .loading
            play(track: track)
        }
    }

    /// Skip to the previous item
    public func seekToPrevious() throws {
        processingState = .loading
        play(track: try tryMoveToPreviousTrack())
    }

    /// Toggles shuffle mode
    public func setShuffleModeEnabled(_ shouldShuffle: Bool) {
        queueManager.shouldShuffle = shouldShuffle
    }

    /// Sets a shuffle playback order for a specific `AudioSequence` in the queue
    public func shuffle(at index: Int, inOrder newOrder: [Int]) throws {
        try queueManager.shuffle(at: index, inOrder: newOrder)
    }

    /**
     * Sets the node speed
     */
    public func setSpeed(_ speed: Float) throws {
        guard let node = mainPlayer.audioModifiers[0] as? AVAudioUnitTimePitch else {
            throw CannotFindAudioModifier()
        }
        guard speed > 0.0, speed <= 32.0 else {
            throw SpeedValueNotValidError(value: speed)
        }
        self.speed = speed
        node.rate = speed
        mainPlayer.playbackRateOfAudioChanged(rate: speed)
    }

    /**
     * Sets the node volume
     * N.B. it is the player node volume value, not the device's one
     */
    public func setVolume(_ volume: Float) throws {
        guard volume >= 0.0 || volume <= 1.0 else {
            throw VolumeValueNotValidError(value: volume)
        }
        self.volume = volume
        mainPlayer.playerNode?.volume = volume
    }

    /**
     * Sets the player loop mode.
     * Warning: if one of the `AudioSources` in queue is a `LoopingAudioSource`, its "loop" will override the * * player loop
     */
    public func setLoopMode(_ loopMode: LoopMode) {
        self.loopMode = loopMode
    }

    /**
     * Sets the next loop mode. Allow the user to keep touching the same button to toggle between the different `LoopMode`s
     */
    public func setNextLoopMode() {
        switch loopMode {
        case .off:
            loopMode = .one
        case .one:
            loopMode = .all
        case .all:
            loopMode = .off
        }
    }

    // TODO:
    public func setClip(start _: TimeInterval? = nil, end _: TimeInterval? = nil) {}

    /**
     * Allows to provide an equalizer to the player
     */
    public func setEqualizer(_ equalizer: Equalizer) throws {
        guard self.equalizer == nil else {
            throw AlreadyHasEqualizerError()
        }

        self.equalizer = equalizer
        mainPlayer.audioModifiers.append(self.equalizer!.node)
    }

    /**
     * Allows to update the presets for the current `Equalizer` instance
     */
    public func updateEqualizerPresets(_ preset: [PreSet]) throws {
        guard let equalizer = equalizer else {
            throw MissingEqualizerError()
        }

        try equalizer.setPreSets(preset)

        self.equalizer = equalizer
    }

    /**
     * Activates the preset at the given index for the current equalizer
     */
    public func activateEqualizerPreset(at index: Int) throws {
        guard let equalizer = equalizer else {
            throw MissingEqualizerError()
        }

        try equalizer.activate(preset: index)

        self.equalizer = equalizer
    }

    /**
     * Allows to tweak the gain of a specific band of the current equalizer
     */
    public func tweakEqualizerBandGain(band: Int, gain: Float) throws {
        guard let equalizer = equalizer else {
            throw MissingEqualizerError()
        }

        try equalizer.tweakBandGain(band: band, gain: gain)

        self.equalizer = equalizer
    }

    /**
     * Clears the current preset gains
     */
    public func resetGains() throws {
        guard let equalizer = equalizer else {
            throw MissingEqualizerError()
        }

        equalizer.resetGains()

        self.equalizer = equalizer
    }

    /**
     * Writes the final output of the engine to a file inside the documents directory
     */
    public func writeOutputToFile() throws {
        guard let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CouldNotCreateOutputFileError()
        }

        let outputFileUrl = documentsDirectoryURL.appendingPathComponent(Date().description)

        outputAbsolutePath = outputFileUrl.absoluteString

        // We need some settings for the output audio file. The quickiest way to test this is to grab the same settings of the output node of the engine.
        // Sadly it defaults to WAV format for the output file, and since we're planning to upload this file to the server, is the less performant format
        // Some work should be done to extrapolate a good settings configuration
        let settings = engine.outputNode.outputFormat(forBus: 0).settings

        let outputFile = try AVAudioFile(forWriting: outputFileUrl, settings: settings)

        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            do {
                try outputFile.write(from: buffer)
            } catch {
                self?.outputWriteError = error
            }
        }
    }

    /**
     * Stops writing the final output of the engine to a file (see `writeOutputToFile`)
     */
    public func stopWritingOutputFile() {
        guard outputAbsolutePath != nil else { // we never registered a tap via `writeOutputToFile`
            return
        }

        engine.mainMixerNode.removeTap(onBus: 0)
    }

    // MARK: - Private API

    /**
     * Either plays the only track in queue (without trying to move to next) or moves to the next track (if available)
     * Updates accordingly the `processingState` and `queueIndex` of the player
     */
    private func scheduleAudioSource() throws {
        isPlaying = false
        if queueManager.count == 1 {
            processingState = .loading
            play(track: try queueManager.element(at: 0))
            queueIndex = 0
        } else if let track = try tryMoveToNextTrack() { // first time to play a song
            processingState = .loading
            play(track: track)
        } else {
            processingState = .completed
        }
    }

    /**
     * Tries to move the queue index to the next track.
     * If we're on the last track of the queue or the queue is empty, the queueIndex will not change.
     * `LoopMode.one` works only when a track finishes by itself.
     * - Parameter isForced: whether the next song must be played (ex. seek to next)
     * - Note: if the current `AudioSource` is a `LoopingAudioSource`, it has priority on looping itself
     */
    func tryMoveToNextTrack(isForced: Bool = false) throws -> AudioSource? {
        let currentIndex = queueIndex ?? 0

        if let looping = try queueManager.element(at: currentIndex) as? LoopingAudioSource {
            if looping.playedTimes < looping.count {
                looping.playedTimes += 1
                queueIndex = currentIndex
                return looping.realAudioSource
            }
        }

        if !isForced {
            // do not change the index, and return the current track
            if loopMode == LoopMode.one {
                queueIndex = currentIndex
                return try queueManager.element(at: currentIndex)
            }
        }
        let nextIndex = queueIndex != nil ? currentIndex + 1 : currentIndex

        // simply, the next track available
        if queueManager.contains(nextIndex) {
            queueIndex = nextIndex
            return try queueManager.element(at: nextIndex)
        }

        // stop the player when we're at the end of the queue and is not forced the seek
        if loopMode == .off && !isForced {
            queueIndex = nil
            return nil
        }

        // we're at the end of the queue, automatically go back to the first element
        if loopMode == .all || isForced {
            queueIndex = 0
            return queueManager.first
        }

        // undetermined case, should never happens
        return nil
    }

    func tryMoveToTrack(index: Int, isForced: Bool = false) throws -> AudioSource? {
        let currentIndex = queueIndex ?? 0

        if let looping = try queueManager.element(at: currentIndex) as? LoopingAudioSource {
            if looping.playedTimes < looping.count {
                looping.playedTimes += 1
                queueIndex = currentIndex
                return looping.realAudioSource
            }
        }

        if queueManager.contains(index) {
            queueIndex = index
            return try queueManager.element(at: index)
        }

        // stop the player when we're at the end of the queue and is not forced the seek
        if loopMode == .off && !isForced {
            queueIndex = nil
            return nil
        }

        // we're at the end of the queue, automatically go back to the first element
        if loopMode == .all || isForced {
            queueIndex = 0
            return queueManager.first
        }

        // undetermined case, should never happen
        return nil
    }

    /**
     * Always try to push back the player*
     */
    func tryMoveToPreviousTrack() throws -> AudioSource {
        guard queueManager.count > 0 else {
            preconditionFailure("no track has been set")
        }
        let currentIndex = queueIndex ?? 0
        // if track is playing for more than 5 second, restart the current track
        if mainPlayer.elapsedTime ?? 0 >= JustAudioPlayer.ELAPSED_TIME_TO_RESTART_A_SONG {
            queueIndex = currentIndex
            return try queueManager.element(at: currentIndex)
        }

        let previousIndex = currentIndex - 1

        if previousIndex == -1 {
            // first song and want to go back to end of the queue
            queueIndex = queueManager.count - 1
            return try queueManager.element(at: queueIndex!)
        }

        if queueManager.contains(previousIndex) {
            queueIndex = previousIndex
            return try queueManager.element(at: previousIndex)
        }

        queueIndex = previousIndex
        return try queueManager.element(at: previousIndex)
    }

    func play(track audioSource: AudioSource) {
        if let url = audioSource.audioUrl {
            // Audio modifiers must be finalized before loading the audio into the player, or they will not be applied
            activateEffects(for: audioSource)

            switch audioSource {
            case let audioSource as ClippingAudioSource:
                if audioSource.isLocal {
                    mainPlayer.startSavedAudio(withSavedUrl: url)
                } else {
                    mainPlayer.startRemoteAudio(withRemoteUrl: url)
                }
            case let audioSource as LoopingAudioSource:
                if audioSource.isLocal {
                    mainPlayer.startSavedAudio(withSavedUrl: url)
                } else {
                    mainPlayer.startRemoteAudio(withRemoteUrl: url)
                }
            case is LocalAudioSource:
                mainPlayer.startSavedAudio(withSavedUrl: url)
            case is RemoteAudioSource:
                mainPlayer.startRemoteAudio(withRemoteUrl: url)

            default:
                // TODO: should we throw?
                preconditionFailure("Don't know how to play \(audioSource.self)")
            }

            seek(second: audioSource.startingTime)

            let actWhenAudioSourceIsReady = {
                self.subscribeToAllSubscriptions()

                self.mainPlayer.play()
            }

            // start to play when we have loaded at least a `audioSource.startingTime` amount of reproducible audio.
            // When seeking a remote audio before playing it, we receive a set of playingStatus updates that we doo not care for:
            unsubscribeUpdates()

            // buffer updates are not triggered for local audio sources (not seeked)
            if audioSource.isLocal {
                actWhenAudioSourceIsReady()
                return
            }

            // notify we're loading the audio source
            isPlaying = false
            processingState = .loading

            // following code is not so elegant, and fragile. It can probably benefit of a refactor where we enhance
            // the coordination of the statuses of the player and move them to a own class
            var subId: UInt?
            subId = mainPlayer.updates.streamingBuffer.subscribe {
                guard let subscription = subId else {
                    return
                }

                let remoteCanPlay = $0.totalDurationBuffered > audioSource.startingTime && $0.isReadyForPlaying
                let localCanPlay = audioSource.isLocal

                if remoteCanPlay || localCanPlay {
                    self.mainPlayer.updates.streamingBuffer.unsubscribe(subscription)
                    actWhenAudioSourceIsReady()
                }
            }
        }
    }

    /// Cleans the current list of audio effects inside the `SAPlayer`, and updates the list with the effects specified by the received audio source
    private func activateEffects(for audioSource: AudioSource) {
        // We want to keep the first item (needed for the play rate, and the equalizer, if present)

        let rateModifier = mainPlayer.audioModifiers.first! // we always expect this to exist

        let equalizerModifier = mainPlayer.audioModifiers.first { audioUnit in
            audioUnit == equalizer?.node
        }

        mainPlayer.clearAudioModifiers()

        mainPlayer.audioModifiers = [rateModifier]

        globalEffects.forEach { mainPlayer.addAudioModifier($0.effect) }

        audioSource.effects.forEach { mainPlayer.addAudioModifier($0.effect) }

        if let equalizer = equalizerModifier {
            mainPlayer.addAudioModifier(equalizer)
        }
    }
}

// MARK: - SwiftAudioPlayer private subscriptions

@available(iOS 13.0, *)
private extension JustAudioPlayer {
    func subscribeToAllSubscriptions() {
        subscribeToPlayingStatusUpdates()
        subscribeToBufferPosition()
        subscribeToElapsedTime()
        subscribeToDuration()
    }

    func subscribeToPlayingStatusUpdates() {
        playingStatusSubscription = mainPlayer.updates.playingStatus
            .subscribe { [weak self] playingStatus in

                guard let self = self, let queueIndex = self.queueIndex else {
                    return
                }

                // initial volume
                if self.volume == nil {
                    self.volume = self.mainPlayer.playerNode?.volume
                }

                // initial speed
                if self.speed == nil {
                    self.speed = (self.mainPlayer.audioModifiers[0] as? AVAudioUnitTimePitch)?.rate
                }

                do {
                    let convertedTrackStatus = AudioSourcePlayingStatus.fromSAPlayingStatus(playingStatus)

                    let audioSource = try self.queueManager.element(at: queueIndex)

                    try audioSource.setPlayingStatus(convertedTrackStatus)

                    let currentTrackPlayingStatus = audioSource.playingStatus

                    if currentTrackPlayingStatus == .ended {
                        // TODO: it seems that time updates are keeping coming up even after the track finishes. Probably related to the `pause()` we commented on the `AudioStreamEngine` internal class, this needs some investigation. Meanwhile, keep this pause here
                        self.mainPlayer.pause()

                        if let track = try self.tryMoveToNextTrack() {
                            self.processingState = .loading
                            self.play(track: track)
                        } else {
                            self.processingState = .completed

                            self.isPlaying = false
                        }
                    } else {
                        if currentTrackPlayingStatus == .buffering {
                            self.processingState = .buffering
                        } else {
                            self.processingState = .ready
                        }
                        if currentTrackPlayingStatus == .playing {
                            self.isPlaying = true
                        }
                    }
                } catch {
                    self.processingState = .none
                    preconditionFailure("Unexpected error \(error)")
                }
            }
    }

    func subscribeToBufferPosition() {
        streamingBufferSubscription = mainPlayer.updates.streamingBuffer
            .subscribe { [weak self] buffer in
                self?.bufferPosition = buffer.bufferingProgress
            }
    }

    func subscribeToElapsedTime() {
        streamingBufferSubscription = mainPlayer.updates.elapsedTime
            .subscribe { [weak self] elapsedTime in // let's assume this is expressed in seconds

                guard let self = self else { return }

                guard let currentIndex = self.queueIndex else {
                    self.elapsedTime = elapsedTime
                    return
                }
                do {
                    let audioSource = try self.queueManager.element(at: currentIndex) as AudioSource
                    if let clipped = audioSource as? ClippingAudioSource {
                        self.elapsedTime = elapsedTime - clipped.start

                        if clipped.playingStatus == .ended {
                            // avoid double call to play
                            return
                        }
                        if elapsedTime >= clipped.end { // here go next or pause?
                            try clipped.setPlayingStatus(.ended)
                            if let track = try self.tryMoveToNextTrack() {
                                self.processingState = .loading
                                self.play(track: track)
                            } else {
                                self.processingState = .completed
                                self.pause()
                            }
                        }
                    } else {
                        if audioSource.playingStatus == .ended {
                            // when one track is finished, it could be that the next one starts,
                            // but the elapsed time still refers to the one just finished,
                            // to avoid this we do not update the elapsed time
                            self.elapsedTime = self.duration
                            return
                        }

                        // When player is paused it emit last played time position
                        if audioSource.playingStatus == .paused {
                            return
                        }

                        self.elapsedTime = elapsedTime
                    }
                } catch {
                    preconditionFailure("Unexpected error \(error)")
                }
            }
    }

    func subscribeToDuration() {
        durationSubscription = mainPlayer.updates.duration
            .subscribe { [weak self] duration in

                guard let self = self else { return }

                guard let currentIndex = self.queueIndex else {
                    self.duration = duration
                    return
                }
                if let clipped = (try? self.queueManager.element(at: currentIndex)) as? ClippingAudioSource {
                    self.duration = clipped.duration
                } else {
                    self.duration = duration
                }
            }
    }

    func unsubscribeUpdates() {
        if let subscription = elapsedTimeSubscription {
            mainPlayer.updates.elapsedTime.unsubscribe(subscription)
        }
        if let subscription = durationSubscription {
            mainPlayer.updates.duration.unsubscribe(subscription)
        }
        if let subscription = playingStatusSubscription {
            mainPlayer.updates.playingStatus.unsubscribe(subscription)
        }
        if let subscription = streamingBufferSubscription {
            mainPlayer.updates.streamingBuffer.unsubscribe(subscription)
        }
    }
}
