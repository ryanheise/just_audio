//
// DistortionAudioEffect.swift
// kMusicSwift
// Created by Kuama Dev Team on 14/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

import AVFAudio

/**
 * Represents an `AVAudioUnitDistortion`, an object that implements a multistage distortion effect.
 */
public class DistortionAudioEffect: AudioEffect {
    public private(set) var effect: AVAudioUnit

    private var _effect: AVAudioUnitDistortion {
        return effect as! AVAudioUnitDistortion
    }

    /// The gain that the audio unit applies to the signal before distortion, in decibels.
    public var preGain: Float {
        _effect.preGain
    }

    /// The blend of the distorted and dry signals.
    public var wetDryMix: Float {
        _effect.wetDryMix
    }

    /// As per doc, this is the default value
    public private(set) var preset: AVAudioUnitDistortionPreset = .drumsBitBrush

    /// The bypass state of the audio unit.
    public var bypass: Bool {
        _effect.bypass
    }

    public init(_ preset: AVAudioUnitDistortionPreset? = nil) {
        effect = AVAudioUnitDistortion()
        if let preset = preset {
            setPreset(preset)
        }
    }

    /// Configures the audio distortion unit by loading a distortion preset.
    public func setPreset(_ preset: AVAudioUnitDistortionPreset) {
        _effect.loadFactoryPreset(preset)
        self.preset = preset
    }

    /// Updates the gain that the audio unit applies to the signal before distortion, in decibels.
    public func setPreGain(_ preGain: Float) {
        _effect.preGain = preGain
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
