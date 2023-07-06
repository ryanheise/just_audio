//
// RemoteAudioSource.swift
// kMusicSwift
// Created by Kuama Dev Team on 01/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

/**
 An `AudioSource` the holds a single audio stream
 */
public class RemoteAudioSource: AudioSource {
    public var effects: [AudioEffect]

    public var playingStatus: AudioSourcePlayingStatus = .idle

    public var isLocal: Bool {
        return false
    }

    public private(set) var audioUrl: URL?

    public init(at uri: String, effects: [AudioEffect] = []) {
        audioUrl = URL(string: uri)
        self.effects = effects
    }

    /// Enforces the correct flow of the status of a track
    public func setPlayingStatus(_ nextStatus: AudioSourcePlayingStatus) throws {
        switch playingStatus {
        case .playing:
            if nextStatus != .playing, nextStatus != .idle {
                playingStatus = nextStatus
            }
        case .paused:
            if nextStatus != .paused {
                playingStatus = nextStatus
            }
        case .buffering:
            if nextStatus != .ended {
                playingStatus = nextStatus
            }
        case .ended:
            if nextStatus != .idle {
                playingStatus = nextStatus
            }
        case .idle:
            if nextStatus != .ended, nextStatus != .paused {
                playingStatus = nextStatus
            }
        }
    }
}
