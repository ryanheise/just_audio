//
//  Util.swift
//  just_audio
//
//  Created by kuama on 22/08/22.
//

import Foundation

struct Util {
    static func timeFrom(microseconds: Int64) -> CMTime {
        return CMTimeMake(value: microseconds, timescale: 1_000_000)
    }

    static func loopModeFrom(_ value: Int) -> LoopMode {
        switch value {
        case 1:
            return LoopMode.loopOne
        case 2:
            return LoopMode.loopAll
        default:
            return LoopMode.loopOff
        }
    }

    static func shuffleModeFrom(_ value: Int) -> Bool {
        return value == 1
    }

    static func gainFrom(_ value: Float) -> Float {
        // Equalize the level between iOS and android
        return value * 2.8
    }

    static func effectFrom(_ map: [String: Any]) throws -> EffectData {
        let type = map["type"] as! String
        switch type {
        case EffectType.darwinEqualizer.rawValue:
            return EqualizerEffectData.fromJson(map)
        default:
            throw NotSupportedError(value: type, "When decoding effect")
        }
    }
}
