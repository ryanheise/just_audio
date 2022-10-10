//
//  Util.swift
//  just_audio
//
//  Created by kuama on 22/08/22.
//

import Foundation
import kMusicSwift

struct Util {
    static func timeFrom(microseconds: Int64) -> CMTime {
        return CMTimeMake(value: microseconds, timescale: 1_000_000)
    }

    static func loopModeFrom(_ value: Int) -> LoopMode {
        switch value {
        case 1:
            return LoopMode.one
        case 2:
            return LoopMode.all
        default:
            return LoopMode.off
        }
    }

    static func parseShuffleModeEnabled(_ value: Int) -> Bool {
        return value == 1
    }

    static func gainFrom(_ value: Float) -> Float {
        // Equalize the level between iOS and android
        return value * 2.8
    }

    static func methodsChannel(forPlayer playerId: String) -> String {
        return String(format: "com.ryanheise.just_audio.methods.%@", playerId)
    }

    static func eventsChannel(forPlayer playerId: String) -> String {
        return String(format: "com.ryanheise.just_audio.events.%@", playerId)
    }

    static func dataChannel(forPlayer playerId: String) -> String {
        return String(format: "com.ryanheise.just_audio.data.%@", playerId)
    }
}
