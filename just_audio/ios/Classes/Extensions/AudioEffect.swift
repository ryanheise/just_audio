//
//  AudioEffect.swift
//  just_audio
//
//  Created by Mac on 27/09/22.
//
import kMusicSwift

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
}

