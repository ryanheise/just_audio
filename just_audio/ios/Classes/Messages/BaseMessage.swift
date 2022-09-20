//
//  BaseMessage.swift
//  just_audio
//
//  Created by Mac on 22/09/22.
//

/**
  Representation of the base message to communicate with `SwiftJustAudioPlugin` from Flutter
 */
class BaseMessage {
    let id: String

    init(id: String) {
        self.id = id
    }

    static func fromMap(_ map: [String: Any]) -> BaseMessage {
        BaseMessage(id: map["id"] as! String)
    }
}
