//
//  InitMessage.swift
//  just_audio
//
//  Created by Mac on 27/09/22.
//

import kMusicSwift

enum DarwinAudioEffect: String {
    case DarwinReverb
    case DarwinDelay
    case DarwinDistortion
}

extension [String: Any?] {
    var audioEffect: AudioEffect {
        let type = DarwinAudioEffect(rawValue: self["type"] as! String)!
        let enabled = self["enabled"] as? Bool ?? true

        switch type {
        case .DarwinReverb:
            let effect = ReverbAudioEffect()
            if let wetDrMix = self["wetDryMix"] as? Double {
                effect.setWetDryMix(Float(wetDrMix))
            }

            if let preset = self["preset"] as? Int {
                effect.setPreset(AVAudioUnitReverbPreset(rawValue: preset)!)
            }

            effect.setBypass(enabled)

            return effect
        case .DarwinDelay:
            let effect = DelayAudioEffect()

            if let wetDrMix = self["wetDryMix"] as? Double {
                effect.setWetDryMix(Float(wetDrMix))
            }

            if let delayTime = self["delayTime"] as? Double {
                effect.setDelayTime(delayTime)
            }

            if let feedback = self["feedback"] as? Double {
                effect.setFeedback(Float(feedback))
            }

            if let lowPassCutoff = self["lowPassCutoff"] as? Double {
                effect.setLowPassCutoff(Float(lowPassCutoff))
            }

            effect.setBypass(enabled)

            return effect

        case .DarwinDistortion:
            let effect = DistortionAudioEffect()
            if let preGain = self["preGain"] as? Double {
                effect.setPreGain(Float(preGain))
            }

            if let wetDrMix = self["wetDryMix"] as? Double {
                effect.setWetDryMix(Float(wetDrMix))
            }

            if let preset = self["preset"] as? Int {
                effect.setPreset(AVAudioUnitDistortionPreset(rawValue: preset)!)
            }

            effect.setBypass(enabled)
            return effect
        }
    }
}
