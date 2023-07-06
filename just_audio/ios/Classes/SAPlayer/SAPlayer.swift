//
//  SAPlayer.swift
//  SwiftAudioPlayer
//
//  Created by Tanha Kabir on 2019-01-29.
//  Copyright © 2019 Tanha Kabir, Jon Mercer
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import AVFoundation
import Foundation

public class SAPlayer {
    public var DEBUG_MODE: Bool = false {
        didSet {
            if DEBUG_MODE {
                logLevel = LogLevel.EXTERNAL_DEBUG
            } else {
                logLevel = LogLevel.MONITOR
            }
        }
    }

    private var presenter: SAPlayerPresenter!
    private var player: AudioEngine?
    public let audioDataManager: AudioDataManager = .init()
    public let audioClockDirector: AudioClockDirector = .init()
    public let audioQueueDirector: AudioQueueDirector = .init()
    public let streamingDownloadDirector: StreamingDownloadDirector = .init()

    public private(set) lazy var downloader: Downloader = .init(player: self)
    public private(set) lazy var updates: Updates = .init(player: self)
    public private(set) lazy var downloadProgressDirector = DownloadProgressDirector(audioDataManager: audioDataManager)

    /**
     Access the engine of the player. Engine is nil if player has not been initialized with audio.

      - Important: Changes to the engine are not safe guarded, thus unknown behaviour can arise from changing the engine. Just be wary and read [documentation of AVAudioEngine](https://developer.apple.com/documentation/avfoundation/avaudioengine) well when modifying,
     */
    public private(set) var engine: AVAudioEngine!

    /**
     Any necessary header fields for streaming and downloading requests can be set here.
     */
    public var HTTPHeaderFields: [String: String]? {
        didSet {
            audioDataManager.setHTTPHeaderFields(HTTPHeaderFields)
        }
    }

    public var allowUsingCellularData: Bool = true {
        didSet {
            downloader.allowUsingCellularData = allowUsingCellularData
        }
    }

    /**
     Unique ID for the current engine. This will be nil if no audio has been initialized which means no engine exists.
     */
    public var engineUID: String? {
        return player?.key
    }

    /**
     Access the player node of the engine. Node is nil if player has not been initialized with audio.

      - Important: Changes to the engine and this node are not safe guarded, thus unknown behaviour can arise from changing the engine or this node. Just be wary and read [documentation of AVAudioEngine](https://developer.apple.com/documentation/avfoundation/avaudioengine) well when modifying,
     */
    public var playerNode: AVAudioPlayerNode? {
        return player?.playerNode
    }

    /**
     Corresponding to the overall volume of the player. Volume's default value is 1.0 and the range of valid values is 0.0 to 1.0. Volume is nil if no audio has been initialized yet.
     */
    public var volume: Float? {
        get {
            return player?.playerNode.volume
        }

        set {
            guard let value = newValue else { return }
            guard value >= 0.0, value <= 1.0 else { return }

            player?.playerNode.volume = value
        }
    }

    /**
     Corresponding to the rate of audio playback. This rate assumes use of the default rate modifier at the first index of `audioModifiers`; if you removed that modifier than this will be nil. If no audio has been initialized then this will also be nil.

      - Note: By default this engine has added a pitch modifier node to change the pitch so that on playback rate changes of spoken word the pitch isn't shifted.

      The component description of this node is:
      ````
      var componentDescription: AudioComponentDescription {
         get {
             var ret = AudioComponentDescription()
             ret.componentType = kAudioUnitType_FormatConverter
             ret.componentSubType = kAudioUnitSubType_AUiPodTimeOther
             return ret
         }
      }
      ````
      Please look at [forums.developer.apple.com/thread/5874](https://forums.developer.apple.com/thread/5874) and [forums.developer.apple.com/thread/6050](https://forums.developer.apple.com/thread/6050) for more details.

      For more details on pitch modifiers for playback rate changes please look at [developer.apple.com/forums/thread/6050](https://developer.apple.com/forums/thread/6050).
     */
    public var rate: Float? {
        get {
            return (audioModifiers.first as? AVAudioUnitTimePitch)?.rate
        }

        set {
            guard let value = newValue else { return }
            guard let node = audioModifiers.first as? AVAudioUnitTimePitch else { return }

            node.rate = value
            playbackRateOfAudioChanged(rate: value)
        }
    }

    /**
     Corresponding to the skipping forward button on the media player on the lockscreen. Default is set to 30 seconds.
     */
    public var skipForwardSeconds: Double = 30 {
        didSet {
            presenter.handleScrubbingIntervalsChanged()
        }
    }

    /**
     Corresponding to the skipping backwards button on the media player on the lockscreen. Default is set to 15 seconds.
     */
    public var skipBackwardSeconds: Double = 15 {
        didSet {
            presenter.handleScrubbingIntervalsChanged()
        }
    }

    /**
     List of [AVAudioUnit](https://developer.apple.com/documentation/avfoundation/audio_track_engineering/audio_engine_building_blocks/audio_enhancements) audio modifiers to pass to the engine on initialization.

     - Important: To have the intended effects, the list of modifiers must be finalized before initializing the audio to be played. The modifers are added to the engine in order of the list.

     - Note: The default list already has an AVAudioUnitTimePitch node first in the list. This node is specifically set to change the rate of audio without changing the pitch of the audio (intended for changing the rate of spoken word).

         The component description of this node is:
         ````
         var componentDescription: AudioComponentDescription {
            get {
                var ret = AudioComponentDescription()
                ret.componentType = kAudioUnitType_FormatConverter
                ret.componentSubType = kAudioUnitSubType_AUiPodTimeOther
                return ret
            }
         }
         ````
         Please look at [forums.developer.apple.com/thread/5874](https://forums.developer.apple.com/thread/5874) and [forums.developer.apple.com/thread/6050](https://forums.developer.apple.com/thread/6050) for more details.

     For more details on pitch modifiers for playback rate changes please look at [developer.apple.com/forums/thread/6050](https://developer.apple.com/forums/thread/6050).

     To remove this default pitch modifier for playback rate changes, remove the node by calling `SAPlayer.shared.clearAudioModifiers()`.
     */
    public var audioModifiers: [AVAudioUnit] = []

    /**
     List of queued audio for playback. You can edit this list as you wish to modify the queue.
     */
    public var audioQueued: [SAAudioQueueItem] {
        get {
            return presenter.audioQueue
        }
        set {
            presenter.audioQueue = newValue
        }
    }

    /**
     Total duration of current audio initialized. Returns nil if no audio is initialized in player.

     - Note: If you are streaming from a source that does not have an expected size at the beginning of a stream, such as live streams, this value will be constantly updating to best known value at the time.
     */
    public var duration: Double? {
        return presenter.duration
    }

    /**
     A textual representation of the duration of the current audio initialized. Returns nil if no audio is initialized in player.
     */
    public var prettyDuration: String? {
        guard let d = duration else { return nil }
        return SAPlayer.prettifyTimestamp(d)
    }

    /**
     Elapsed playback time of the current audio initialized. Returns nil if no audio is initialized in player.
     */
    public var elapsedTime: Double? {
        return presenter.needle
    }

    /**
     A textual representation of the elapsed playback time of the current audio initialized. Returns nil if no audio is initialized in player.
     */
    public var prettyElapsedTime: String? {
        guard let e = elapsedTime else { return nil }
        return SAPlayer.prettifyTimestamp(e)
    }

    /**
     Corresponding to the media info to display on the lockscreen for the current audio.

     - Note: Setting this to nil clears the information displayed on the lockscreen media player.
     */
    public var mediaInfo: SALockScreenInfo?

    public init(engine: AVAudioEngine) {
        self.engine = engine
        presenter = SAPlayerPresenter(delegate: self, audioClockDirector: audioClockDirector, audioQueueDirector: audioQueueDirector)

        // https://forums.developer.apple.com/thread/5874
        // https://forums.developer.apple.com/thread/6050
        // AVAudioTimePitchAlgorithm.timeDomain (just in case we want it)
        var componentDescription: AudioComponentDescription {
            var ret = AudioComponentDescription()
            ret.componentType = kAudioUnitType_FormatConverter
            ret.componentSubType = kAudioUnitSubType_AUiPodTimeOther
            return ret
        }

        audioModifiers.append(AVAudioUnitTimePitch(audioComponentDescription: componentDescription))
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: nil)
    }

    /**
     Clears all [AVAudioUnit](https://developer.apple.com/documentation/avfoundation/audio_track_engineering/audio_engine_building_blocks/audio_enhancements) modifiers intended to be used for realtime audio manipulation.
     */
    public func clearAudioModifiers() {
        audioModifiers.removeAll()
    }

    /**
     Append an [AVAudioUnit](https://developer.apple.com/documentation/avfoundation/audio_track_engineering/audio_engine_building_blocks/audio_enhancements) modifier to the list of modifiers used for realtime audio manipulation. The modifier will be added to the end of the list.

     - Parameter modifier: The modifier to append.
     */
    public func addAudioModifier(_ modifer: AVAudioUnit) {
        audioModifiers.append(modifer)
    }

    /**
     Formats a textual representation of a given timestamp for display in hh:MM:SS format, that is hours:minutes:seconds.

     - Parameter timestamp: The timestamp to format.
     - Returns: A textual representation of the given timestamp
     */
    public static func prettifyTimestamp(_ timestamp: Double) -> String {
        let hours = Int(timestamp / 60 / 60)
        let minutes = Int((timestamp - Double(hours * 60 * 60)) / 60)
        let secondsLeft = Int(timestamp - Double(hours * 60 * 60) - Double(minutes * 60))

        return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", secondsLeft))"
    }

    func getUrl(forKey key: Key) -> URL? {
        return presenter.getUrl(forKey: key)
    }

    func addUrlToMapping(url: URL) {
        presenter.addUrlToKeyMap(url)
    }

    @objc func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        // Switch over the interruption type.
        switch type {
        case .began:
            // An interruption began. Update the UI as necessary.
            pause()

        case .ended:
            // An interruption ended. Resume playback, if appropriate.

            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // An interruption ended. Resume playback.
                play()
            } else {
                // An interruption ended. Don't resume playback.
            }

        default: ()
        }
    }
}

public enum SAPlayerBitrate {
    /// This bitrate is good for radio streams that are passing ittle amounts of audio data at a time. This will allow the player to process the audio data in a fast enough rate to not pause or get stuck playing. This rate however ends up using more CPU and is worse for your battery-life and performance of your app.
    case low

    /// This bitrate is good for streaming saved audio files like podcasts where most of the audio data will be received from the remote server at the beginning in a short time. This rate is more performant by using much less CPU and being better for your battery-life and app performance.
    case high // go for audio files being streamed. This is uses less CPU and
}

// MARK: - External Player Controls

public extension SAPlayer {
    /**
     Toggles between the play and pause state of the player. If nothing is playable (aka still in buffering state or no audio is initialized) no action will be taken. Please call `startSavedAudio` or `startRemoteAudio` to set up the player with audio before this.

     - Note: If you are streaming, wait till the status from `SAPlayer.Updates.PlayingStatus` is not `.buffering`.
     */
    func togglePlayAndPause() {
        presenter.handleTogglePlayingAndPausing()
    }

    /**
     Attempts to play the player. If nothing is playable (aka still in buffering state or no audio is initialized) no action will be taken. Please call `startSavedAudio` or `startRemoteAudio` to set up the player with audio before this.

     - Note: If you are streaming, wait till the status from `SAPlayer.Updates.PlayingStatus` is not `.buffering`.
     */
    func play() {
        presenter.handlePlay()
    }

    /**
     Attempts to pause the player. If nothing is playable (aka still in buffering state or no audio is initialized) no action will be taken. Please call `startSavedAudio` or `startRemoteAudio` to set up the player with audio before this.

     - Note:If you are streaming, wait till the status from `SAPlayer.Updates.PlayingStatus` is not `.buffering`.
     */
    func pause() {
        presenter.handlePause()
    }

    /**
     Attempts to skip forward in audio even if nothing playable is loaded (aka still in buffering state or no audio is initialized). The interval to which to skip forward is defined by `SAPlayer.shared.skipForwardSeconds`.

     - Note: The skipping is limited to the duration of the audio, if the intended skip is past the duration of the current audio, the skip will just go to the end.
     */
    func skipForward() {
        presenter.handleSkipForward()
    }

    /**
     Attempts to skip backwards in audio even if nothing playable is loaded (aka still in buffering state or no audio is initialized). The interval to which to skip backwards is defined by `SAPlayer.shared.skipBackwardSeconds`.

     - Note: The skipping is limited to the playable timestamps, if the intended skip is below 0 seconds, the skip will just go to 0 seconds.
     */
    func skipBackwards() {
        presenter.handleSkipBackward()
    }

    /**
     Attempts to seek/scrub through the audio even if nothing playable is loaded (aka still in buffering state or no audio is initialized).

     - Parameter seconds: The intended seconds within the audio to seek to.

     - Note: The seeking is limited to the playable timestamps, if the intended seek is below 0 seconds, the skip will just go to 0 seconds. If the intended seek is past the curation of the current audio, the seek will just go to the end.
     */
    func seekTo(seconds: Double) {
        presenter.handleSeek(toNeedle: seconds)
    }

    /**
     If using an AVAudioUnitTimePitch, it's important to notify the player that the rate at which the audio playing has changed to keep the media player in the lockscreen up to date. This is only important for playback rate changes.

     - Note: By default this engine has added a pitch modifier node to change the pitch so that on playback rate changes of spoken word the pitch isn't shifted.

     The component description of this node is:
     ````
     var componentDescription: AudioComponentDescription {
        get {
            var ret = AudioComponentDescription()
            ret.componentType = kAudioUnitType_FormatConverter
            ret.componentSubType = kAudioUnitSubType_AUiPodTimeOther
            return ret
        }
     }
     ````
     Please look at [forums.developer.apple.com/thread/5874](https://forums.developer.apple.com/thread/5874) and [forums.developer.apple.com/thread/6050](https://forums.developer.apple.com/thread/6050) for more details.

     For more details on pitch modifiers for playback rate changes please look at [developer.apple.com/forums/thread/6050](https://developer.apple.com/forums/thread/6050).

     - Parameter rate: The current rate at which the audio is playing.
     */
    func playbackRateOfAudioChanged(rate: Float) {
        presenter.handleAudioRateChanged(rate: rate)
    }

    /**
     Sets up player to play audio that has been saved on the device.

     - Important: If intending to use [AVAudioUnit](https://developer.apple.com/documentation/avfoundation/audio_track_engineering/audio_engine_building_blocks/audio_enhancements) audio modifiers during playback, the list of audio modifiers under `SAPlayer.shared.audioModifiers` must be finalized before calling this function. After all realtime audio manipulations within the this will be effective.

     - Note: The default list already has an AVAudioUnitTimePitch node first in the list. This node is specifically set to change the rate of audio without changing the pitch of the audio (intended for changing the rate of spoken word).

         The component description of this node is:
         ````
         var componentDescription: AudioComponentDescription {
            get {
                var ret = AudioComponentDescription()
                ret.componentType = kAudioUnitType_FormatConverter
                ret.componentSubType = kAudioUnitSubType_AUiPodTimeOther
                return ret
            }
         }
         ````
         Please look at [forums.developer.apple.com/thread/5874](https://forums.developer.apple.com/thread/5874) and [forums.developer.apple.com/thread/6050](https://forums.developer.apple.com/thread/6050) for more details.

     To remove this default pitch modifier for playback rate changes, remove the node by calling `SAPlayer.shared.clearAudioModifiers()`.

     - Parameter withSavedUrl: The URL of the audio saved on the device.
     - Parameter mediaInfo: The media information of the audio to show on the lockscreen media player (optional).
     */
    func startSavedAudio(withSavedUrl url: URL, mediaInfo: SALockScreenInfo? = nil) {
        // Because we support queueing, we want to clear off any existing players.
        // Therefore, instantiate new player every time, destroy any existing ones.
        // This prevents a crash where an owning engine already exists.
        presenter.handleClear()

        // order here matters, need to set media info before trying to play audio
        self.mediaInfo = mediaInfo
        presenter.handlePlaySavedAudio(withSavedUrl: url)
    }

    /**
     Sets up player to play audio that will be streamed from a remote location. After this is called, it will connect to the server and start to receive and process data. The player is not playable the SAAudioAvailabilityRange notifies that player is ready for playing (you can subscribe to these updates through `SAPlayer.Updates.StreamingBuffer`). You can alternatively see when the player is available to play by subscribing to `SAPlayer.Updates.PlayingStatus` and waiting for a status that isn't `.buffering`.

     - Important: If intending to use [AVAudioUnit](https://developer.apple.com/documentation/avfoundation/audio_track_engineering/audio_engine_building_blocks/audio_enhancements) audio modifiers during playback, the list of audio modifiers under `SAPlayer.shared.audioModifiers` must be finalized before calling this function. After all realtime audio manipulations within the this will be effective.

     - Note: The default list already has an AVAudioUnitTimePitch node first in the list. This node is specifically set to change the rate of audio without changing the pitch of the audio (intended for changing the rate of spoken word).

         The component description of this node is:
         ````
         var componentDescription: AudioComponentDescription {
            get {
                var ret = AudioComponentDescription()
                ret.componentType = kAudioUnitType_FormatConverter
                ret.componentSubType = kAudioUnitSubType_AUiPodTimeOther
                return ret
            }
         }
         ````
         Please look at [forums.developer.apple.com/thread/5874](https://forums.developer.apple.com/thread/5874) and [forums.developer.apple.com/thread/6050](https://forums.developer.apple.com/thread/6050) for more details.

     To remove this default pitch modifier for playback rate changes, remove the node by calling `SAPlayer.shared.clearAudioModifiers()`.

     - Note: Subscribe to `SAPlayer.Updates.StreamingBuffer` to see updates in streaming progress.

     - Parameter withRemoteUrl: The URL of the remote audio.
     - Parameter bitrate: The bitrate of the streamed audio. By default the bitrate is set to high for streaming saved audio files. If you want to stream radios then you should use the `low` bitrate option.
     - Parameter mediaInfo: The media information of the audio to show on the lockscreen media player (optional).
     */
    func startRemoteAudio(withRemoteUrl url: URL, bitrate: SAPlayerBitrate = .high, mediaInfo: SALockScreenInfo? = nil) {
        // Because we support queueing, we want to clear off any existing players.
        // Therefore, instantiate new player every time, destroy any existing ones.
        // This prevents a crash where an owning engine already exists.
        presenter.handleClear()

        // order here matters, need to set media info before trying to play audio
        self.mediaInfo = mediaInfo
        presenter.handlePlayStreamedAudio(withRemoteUrl: url, bitrate: bitrate)
    }

    /**
     Stops any streaming in progress.
     */
    func stopStreamingRemoteAudio() {
        presenter.handleStopStreamingAudio()
    }

    /**
     Queues remote audio to be played next. The URLs in the queue can be both remote or on disk but once the queued audio starts playing it will start buffering and loading then. This means no guarantee for a 'gapless' playback where there might be several moments in between one audio ending and another starting due to buffering remote audio.

     - Parameter withRemoteUrl: The URL of the remote audio.
     - Parameter bitrate: The bitrate of the streamed audio. By default the bitrate is set to high for streaming saved audio files. If you want to stream radios then you should use the `low` bitrate option.
     - Parameter mediaInfo: The media information of the audio to show on the lockscreen media player (optional).
     */
    func queueRemoteAudio(withRemoteUrl url: URL, bitrate: SAPlayerBitrate = .high, mediaInfo: SALockScreenInfo? = nil) {
        presenter.handleQueueStreamedAudio(withRemoteUrl: url, mediaInfo: mediaInfo, bitrate: bitrate)
    }

    /**
     Queues saved audio to be played next. The URLs in the queue can be both remote or on disk but once the queued audio starts playing it will start buffering and loading then. This means no guarantee for a 'gapless' playback where there might be several moments in between one audio ending and another starting due to buffering remote audio.

     - Parameter withSavedUrl: The URL of the audio saved on the device.
     - Parameter mediaInfo: The media information of the audio to show on the lockscreen media player (optional).
     */
    func queueSavedAudio(withSavedUrl url: URL, mediaInfo: SALockScreenInfo? = nil) {
        presenter.handleQueueSavedAudio(withSavedUrl: url, mediaInfo: mediaInfo)
    }

    /**
     Remove the first queued audio if one exists. Receive the first URL removed back.

     - Returns the URL of the removed audio.
     */
    func removeFirstQueuedAudio() -> URL? {
        guard audioQueued.count != 0 else { return nil }
        return presenter.handleRemoveFirstQueuedItem()
    }

    /**
     Clear the list of queued audio.

     - Returns the list of removed audio URLs
     */
    func clearAllQueuedAudio() -> [URL] {
        return presenter.handleClearQueued()
    }

    /**
     Resets the player to the state before initializing audio and setting media info.
     */
    func clear() {
        presenter.handleClear()
    }
}

// MARK: - Internal implementation of delegate

extension SAPlayer: SAPlayerDelegate {
    internal func startAudioDownloaded(withSavedUrl url: AudioURL) {
        player = AudioDiskEngine(withSavedUrl: url, delegate: presenter, engine: engine, audioClockDirector: audioClockDirector)
    }

    internal func startAudioStreamed(withRemoteUrl url: AudioURL, bitrate: SAPlayerBitrate) {
        player = AudioStreamEngine(
            withRemoteUrl: url,
            delegate: presenter,
            bitrate: bitrate,
            engine: engine,
            withAudioClockDirector: audioClockDirector,
            withStreamingDownloadDirector: streamingDownloadDirector,
            withAudioDataManager: audioDataManager
        )
    }

    internal func clearEngine() {
        player?.pause()
        player?.invalidate()
        player = nil
        Log.info("cleared engine")
    }

    internal func playEngine() {
        becomeDeviceAudioPlayer()
        player?.play()
    }

    // Start taking control as the device's player
    private func becomeDeviceAudioPlayer() {
        do {
            if #available(iOS 11.0, tvOS 11.0, *) {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio, options: [])
            } else {
                try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback, mode: AVAudioSession.Mode(rawValue: convertFromAVAudioSessionMode(AVAudioSession.Mode.default)), options: .allowAirPlay)
            }
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            Log.monitor("Problem setting up AVAudioSession to play in:: \(error.localizedDescription)")
        }
    }

    internal func pauseEngine() {
        player?.pause()
    }

    internal func seekEngine(toNeedle needle: Needle) {
        let seekToNeedle = needle < 0 ? 0 : needle
        player?.seek(toNeedle: seekToNeedle)
    }
}

// Helper function inserted by Swift 4.2 migrator.
private func convertFromAVAudioSessionMode(_ input: AVAudioSession.Mode) -> String {
    return input.rawValue
}
