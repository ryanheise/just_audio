//
// CannotRemoveAudioSourceFromSequenceError.swift
// kMusicSwift
// Created by Kuama Dev Team on 02/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

/**
 * Thrown when trying to remove an `AudioSource` that is playing or buffering
 */
public class CannotRemoveAudioSourceFromSequenceError: JustAudioPlayerError {
    public let currentStatus: AudioSourcePlayingStatus

    init(currentStatus: AudioSourcePlayingStatus) {
        self.currentStatus = currentStatus
        super.init()
    }

    override public var baseDescription: String {
        "AudioSources with playing status \(currentStatus) cannot be removed"
    }
}
