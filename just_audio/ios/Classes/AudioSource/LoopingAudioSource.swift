//
// LoopingAudioSource.swift
// kMusicSwift
// Created by Kuama Dev Team on 01/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

/**
 An `AudioSource` that loops for N times before being considered "finished"
 */
public class LoopingAudioSource: AudioSource {
    public var effects: [AudioEffect]

    /// The number of times this audio source should loop
    let count: Int

    /// The times that this track has been played.
    public var playedTimes: Int = 0

    public private(set) var realAudioSource: AudioSource

    public var isLocal: Bool {
        return realAudioSource.isLocal
    }

    public var playingStatus: AudioSourcePlayingStatus {
        realAudioSource.playingStatus
    }

    public var audioUrl: URL? {
        realAudioSource.audioUrl
    }

    public init(with singleAudioSource: AudioSource, count: Int, effects: [AudioEffect] = []) {
        self.count = count
        realAudioSource = singleAudioSource
        self.effects = effects
    }

    public func setPlayingStatus(_ nextStatus: AudioSourcePlayingStatus) throws {
        try realAudioSource.setPlayingStatus(nextStatus)
    }
}
