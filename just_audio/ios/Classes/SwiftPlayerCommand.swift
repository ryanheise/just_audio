//
//  SwiftPlayerCommand.swift
//  just_audio
//
//  Created by Mac on 22/09/22.
//

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

    static func parse(_ value: String) throws -> SwiftPlayerCommand {
        return SwiftPlayerCommand(rawValue: value)!
    }
}
