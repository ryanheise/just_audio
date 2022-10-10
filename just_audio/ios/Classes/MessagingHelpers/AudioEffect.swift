//
//  AudioEffect.swift
//  just_audio
//
//  Created by Mac on 27/09/22.
//
import kMusicSwift

enum DarwinAudioEffect: String {
    case DarwinReverb
    case DarwinDelay
    case DarwinDistortion

    static func parseEffectFrom(map: [String: Any?]) -> (String, AudioEffect) {
        let type = DarwinAudioEffect(rawValue: map["type"] as! String)!
        let enabled = map["enabled"] as? Bool ?? true

        switch type {
        case .DarwinReverb:
            let effect = ReverbAudioEffect()
            if let wetDrMix = map["wetDryMix"] as? Double {
                effect.setWetDryMix(Float(wetDrMix))
            }

            if let preset = map["preset"] as? Int {
                effect.setPreset(AVAudioUnitReverbPreset(rawValue: preset)!)
            }

            effect.setBypass(false) // Don't know why, but bypassing the reverb causes no final output
            if enabled == false {
                effect.setWetDryMix(0)
            }

            return (map["id"] as! String, effect)
        case .DarwinDelay:
            let effect = DelayAudioEffect()

            if let wetDrMix = map["wetDryMix"] as? Double {
                effect.setWetDryMix(Float(wetDrMix))
            }

            if let delayTime = map["delayTime"] as? Double {
                effect.setDelayTime(delayTime)
            }

            if let feedback = map["feedback"] as? Double {
                effect.setFeedback(Float(feedback))
            }

            if let lowPassCutoff = map["lowPassCutoff"] as? Double {
                effect.setLowPassCutoff(Float(lowPassCutoff))
            }

            effect.setBypass(!enabled)

            return (map["id"] as! String, effect)

        case .DarwinDistortion:
            let effect = DistortionAudioEffect()
            if let preGain = map["preGain"] as? Double {
                effect.setPreGain(Float(preGain))
            }

            if let wetDrMix = map["wetDryMix"] as? Double {
                effect.setWetDryMix(Float(wetDrMix))
            }

            if let preset = map["preset"] as? Int {
                effect.setPreset(AVAudioUnitDistortionPreset(rawValue: preset)!)
            }

            effect.setBypass(!enabled)
            return (map["id"] as! String, effect)
        }
    }
}

extension AudioEffect {
    var type: DarwinAudioEffect {
        get throws {
            if self is ReverbAudioEffect {
                return .DarwinReverb
            }

            if self is DistortionAudioEffect {
                return .DarwinDistortion
            }

            if self is DelayAudioEffect {
                return .DarwinDelay
            }

            throw SwiftJustAudioPluginError.notSupportedError(value: self, message: "Could not find type for \(self)")
        }
    }

    func toMap(_ id: String) throws -> [String: Any?] {
        var result: [String: Any?] = [
            "id": id,
            "enable": !bypass,
            "type": try type.rawValue,
        ]

        switch self {
        case let effect as ReverbAudioEffect:
            result["wetDryMix"] = effect.wetDryMix
            result["preset"] = effect.preset.rawValue
        case let effect as DelayAudioEffect:
            result["delayTime"] = effect.delayTime
            result["feedback"] = effect.feedback
            result["lowPassCutoff"] = effect.lowPassCutoff
            result["wetDryMix"] = effect.wetDryMix
        case let effect as DistortionAudioEffect:
            result["wetDryMix"] = effect.wetDryMix
            result["preset"] = effect.preset.rawValue
            result["preGain"] = effect.preGain
        default:
            throw SwiftJustAudioPluginError.notSupportedError(value: self, message: "Could not find type for \(self)")
        }

        return result
    }
}
