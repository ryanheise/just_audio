//
//  SwiftJustAudioPluginCommand.swift
//  just_audio
//
//  Created by Mac on 22/09/22.
//

/**
  Commands used to orchestrate requests to
  - instantiate a new player
  - dispose a player
  - dispose all players
  between Flutter/Dart and iOS layers
 */
enum SwiftJustAudioPluginCommand: String {
    case `init` // TODO: should be "create", init comes from dart, and is a keyword in swift
    case disposePlayer
    case disposeAllPlayers

    static func parse(_ value: String) -> SwiftJustAudioPluginCommand {
        return SwiftJustAudioPluginCommand(rawValue: value)!
    }
}
