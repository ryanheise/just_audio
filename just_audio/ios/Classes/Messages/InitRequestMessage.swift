//
//  InitRequest.swift
//  audio_session
//
//  Created by Mac on 22/09/22.
//

/**
 TODO: should be `CreatePlayerMessage`
 Representation of a request to bootstrap a player in `SwiftJustAudioPlugin` from Flutter
 */
class InitRequestMessage: BaseMessage {
    let configuration: LoadControlMessage
    let audioEffects: [AudioEffectMessage]

    init(configuration: LoadControlMessage, audioEffects: [AudioEffectMessage], id: String) {
        self.configuration = configuration
        self.audioEffects = audioEffects
        super.init(id: id)
    }

    static func fromMap(map: [String: Any]) -> InitRequestMessage {
        let configuration = LoadControlMessage.fromMap(map: map["audioLoadConfiguration"] as! [String: Any?])

        let audioEffects = (map["darwinAudioEffects"] as! [[String: Any?]]).map { hash in
            AudioEffectMessage.fromMap(map: hash)
        }

        let baseMessage = BaseMessage.fromMap(map)

        return InitRequestMessage(configuration: configuration, audioEffects: audioEffects, id: baseMessage.id)
    }
}
