//
// ClippingAudioSource.swift
// kMusicSwift
// Created by Kuama Dev Team on 01/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

/**
 An `AudioSource` that plays just part of itself
 */
public class ClippingAudioSource: AudioSource {
    public private(set) var realAudioSource: AudioSource

    public var effects: [AudioEffect]

    public var isLocal: Bool {
        return realAudioSource.isLocal
    }

    let start: Double
    let end: Double

    var duration: Double { end - start }

    public var playingStatus: AudioSourcePlayingStatus {
        realAudioSource.playingStatus
    }

    public var audioUrl: URL? {
        realAudioSource.audioUrl
    }

    public init(with singleAudioSource: AudioSource, from: Double, to: Double, effects: [AudioEffect] = []) throws {
        start = from
        end = to

        guard start < end else {
            throw ClippingAudioStartEndError()
        }
        realAudioSource = singleAudioSource
        self.effects = effects
    }

    public func setPlayingStatus(_ nextStatus: AudioSourcePlayingStatus) throws {
        try realAudioSource.setPlayingStatus(nextStatus)
    }
}
