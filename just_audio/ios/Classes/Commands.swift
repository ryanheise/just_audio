//
//  SwiftPlayerCommand.swift
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

/**
  Commands used to orchestrate requests to a single player between Flutter/Dart and iOS layers
 */
enum SwiftPlayerCommand: String {
    case load
    case play
    case pause
    case seek
    case setVolume
    case setSpeed
    case setPitch
    case setSkipSilence
    case setLoopMode
    case setShuffleMode
    case setShuffleOrder
    case setAutomaticallyWaitsToMinimizeStalling
    case setCanUseNetworkResourcesForLiveStreamingWhilePaused
    case setPreferredPeakBitRate
    case dispose
    case concatenatingInsertAll
    case concatenatingRemoveRange
    case concatenatingMove
    case audioEffectSetEnabled
    case darwinEqualizerBandSetGain
    case darwinWriteOutputToFile
    case darwinStopWriteOutputToFile
    case darwinDelaySetTargetDelayTime
    case darwinDelaySetTargetFeedback
    case darwinDelaySetLowPassCutoff
    case darwinDelaySetWetDryMix
    case darwinDistortionSetWetDryMix
    case darwinDistortionSetPreGain
    case darwinDistortionSetPreset
    case darwinReverbSetPreset
    case darwinReverbSetWetDryMix

    static func parse(_ value: String) throws -> SwiftPlayerCommand {
        return SwiftPlayerCommand(rawValue: value)!
    }
}
