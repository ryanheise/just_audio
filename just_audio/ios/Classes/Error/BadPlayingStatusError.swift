//
// BadPlayingStatusError.swift
// kMusicSwift
// Created by Kuama Dev Team on 01/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

/**
 * The given playing status for `AudioSource` is not valid
 */
public class BadPlayingStatusError: JustAudioPlayerError {
    public let value: AudioSourcePlayingStatus

    init(value: AudioSourcePlayingStatus) {
        self.value = value
        super.init()
    }

    override public var baseDescription: String {
        "Playing status \(value) not valid for audio source"
    }
}
