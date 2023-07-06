//
// AudioSourcePlayingStatus.swift
// kMusicSwift
// Created by Kuama Dev Team on 01/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

public enum AudioSourcePlayingStatus {
    case playing
    case paused
    case buffering
    case ended
    case idle

    static func fromSAPlayingStatus(_ playingStatus: SAPlayingStatus) -> AudioSourcePlayingStatus {
        switch playingStatus {
        case .playing:
            return .playing
        case .paused:
            return .paused
        case .buffering:
            return .buffering
        case .ended:
            return .ended
        }
    }
}
