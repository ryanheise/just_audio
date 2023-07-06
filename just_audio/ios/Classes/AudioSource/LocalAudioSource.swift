//
// LocalAudioSource.swift
// kMusicSwift
// Created by Kuama Dev Team on 01/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

/**
 An `AudioSource` that holds an audio file stored inside the local filesystem
 It can be built with a string representing a full path to the audio file inside the local filesystem.
 */
public class LocalAudioSource: AudioSource {
    public var playingStatus: AudioSourcePlayingStatus = .idle

    public var effects: [AudioEffect]

    public var isLocal: Bool {
        return true
    }

    public var audioUrl: URL? {
        return _audioUrl
    }

    private var _audioUrl: URL?

    public init(at uri: String, effects: [AudioEffect] = []) {
        _audioUrl = Bundle.main.url(forResource: uri, withExtension: "")
        if _audioUrl == nil {
            if uri.hasPrefix("ipod-library://") || uri.hasPrefix("file://") {
                _audioUrl = URL(string: uri)
            } else {
                _audioUrl = URL(fileURLWithPath: uri)
            }
        }
        self.effects = effects
    }

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
        case .ended:
            if nextStatus != .idle {
                playingStatus = nextStatus
            }
        case .idle:
            if nextStatus != .ended, nextStatus != .paused {
                playingStatus = nextStatus
            }
        case .buffering:
            playingStatus = .buffering
        }
    }
}
