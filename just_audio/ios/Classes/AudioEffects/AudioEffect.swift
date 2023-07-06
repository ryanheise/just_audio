//
// Effects.swift
// kMusicSwift
// Created by Kuama Dev Team on 11/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

import AVFAudio

/**
 * Represents an Audio Effect to be applied to an `AudioSource`
 */
public protocol AudioEffect {
    var effect: AVAudioUnit { get }

    var bypass: Bool { get }

    func setBypass(_ bypass: Bool)
}
