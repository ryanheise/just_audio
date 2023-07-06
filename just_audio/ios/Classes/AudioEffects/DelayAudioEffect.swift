//
// DelayAudioEffect.swift
// kMusicSwift
// Created by Kuama Dev Team on 14/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

import AVFAudio

/**
 * Represents an `AVAudioUnitDelay`, an object that implements a delay effect.
 */
public class DelayAudioEffect: AudioEffect {
    public private(set) var effect: AVAudioUnit

    private var _effect: AVAudioUnitDelay {
        return effect as! AVAudioUnitDelay
    }

    // The time for the input signal to reach the output.
    public var delayTime: TimeInterval {
        _effect.delayTime
    }

    /// The amount of the output signal that feeds back into the delay line.
    public var feedback: Float {
        _effect.feedback
    }

    /// The cutoff frequency above which high frequency content rolls off, in hertz.
    public var lowPassCutoff: Float {
        _effect.lowPassCutoff
    }

    /// The blend of the distorted and dry signals.
    public var wetDryMix: Float {
        _effect.wetDryMix
    }

    /// The bypass state of the audio unit.
    public var bypass: Bool {
        _effect.bypass
    }

    public init() {
        effect = AVAudioUnitDelay()
    }

    /// Updates the time for the input signal to reach the output.
    public func setDelayTime(_ delayTime: TimeInterval) {
        _effect.delayTime = delayTime
    }

    /// Updates the amount of the output signal that feeds back into the delay line.
    public func setFeedback(_ feedback: Float) {
        _effect.feedback = feedback
    }

    /// Updates the cutoff frequency above which high frequency content rolls off, in hertz.
    public func setLowPassCutoff(_ lowPassCutoff: Float) {
        _effect.lowPassCutoff = lowPassCutoff
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
