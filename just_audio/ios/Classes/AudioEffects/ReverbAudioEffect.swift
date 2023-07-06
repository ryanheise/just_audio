//
// ReverbAudioEffect.swift
// kMusicSwift
// Created by Kuama Dev Team on 14/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

import AVFAudio

/**
 * Represents a `AVAudioUnitReverb`, an object that implements a reverb effect.
 */
public class ReverbAudioEffect: AudioEffect {
    public private(set) var effect: AVAudioUnit

    private var _effect: AVAudioUnitReverb {
        return effect as! AVAudioUnitReverb
    }

    /// The blend of the distorted and dry signals.
    public var wetDryMix: Float {
        _effect.wetDryMix
    }

    /// As per doc, this is the default value
    public private(set) var preset: AVAudioUnitReverbPreset = .mediumHall

    /// The bypass state of the audio unit.
    public var bypass: Bool {
        _effect.bypass
    }

    public init(_ preset: AVAudioUnitReverbPreset? = nil) {
        effect = AVAudioUnitReverb()
        if let preset = preset {
            setPreset(preset)
        }
    }

    /// Configures the audio unit as a reverb preset.
    public func setPreset(_ preset: AVAudioUnitReverbPreset) {
        _effect.loadFactoryPreset(preset)
        self.preset = preset
    }

    /// Updates the blend of the distorted and dry signals.
    public func setWetDryMix(_ wetDryMix: Float) {
        _effect.wetDryMix = wetDryMix
    }

    /// Updates the bypass state of the audio unit.
    public func setBypass(_ bypass: Bool) {
        _effect.bypass = bypass
    }
}
