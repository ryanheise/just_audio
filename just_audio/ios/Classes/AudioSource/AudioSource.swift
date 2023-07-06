//
// AudioSource.swift
// kMusicSwift
// Created by Kuama Dev Team on 01/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

public protocol AudioSource {
    var audioUrl: URL? { get }

    var playingStatus: AudioSourcePlayingStatus { get }

    var isLocal: Bool { get }

    var effects: [AudioEffect] { get }

    /// Should enforce the correct flow of the status of a track
    func setPlayingStatus(_ nextStatus: AudioSourcePlayingStatus) throws
}

// MARK: - AudioSource extensions

extension AudioSource {
    var startingTime: Double {
        guard let audioSource = self as? ClippingAudioSource else {
            return 0
        }
        return audioSource.start
    }
}
