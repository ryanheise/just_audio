//
//  AudioEffectMessage.swift
//  just_audio
//
//  Created by Mac on 22/09/22.
//

/**
 Representation of an audio effect configuration to be added to a player in `SwiftJustAudioPlugin` from Flutter
 */
class AudioEffectMessage {
    let enabled: Bool

    private init(enabled: Bool) {
        self.enabled = enabled
    }

    static func fromMap(map: [String: Any?]) -> AudioEffectMessage {
        return AudioEffectMessage(enabled: map["enabled"] as! Bool)
    }
}
