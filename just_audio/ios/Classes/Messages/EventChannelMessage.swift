//
//  EventChannelMessage.swift
//  just_audio
//
//  Created by Mac on 27/09/22.
//
import kMusicSwift

// TODO: expose equalizer infos
class EventChannelMessage: Equatable {
    let processingState: Int
    let updatePosition: Int
    let bufferedPosition: Int
    let duration: Int
    let currentIndex: Int
    let equalizerData: Equalizer?
    let globalEffects: [String: AudioEffect]
    let audioSourceEffects: [String: AudioEffect]

    init(
        processingState: ProcessingState?,
        elapsedTime: Double?,
        bufferedPosition: Double?,
        duration: Double?,
        currentIndex: Int?,
        equalizerData: Equalizer?,
        globalEffects: [String: AudioEffect],
        audioSourceEffects: [String: AudioEffect]
    ) {
        switch processingState {
        case .none?:
            self.processingState = 0
        case .loading:
            self.processingState = 1
        case .buffering:
            self.processingState = 2
        case .ready:
            self.processingState = 3
        case .completed:
            self.processingState = 4
        default:
            self.processingState = 0
        }

        updatePosition = elapsedTime != nil ? Int(elapsedTime! * 1_000_000) : 0

        self.bufferedPosition = bufferedPosition != nil ? Int(bufferedPosition! * 1_000_000) : 0

        self.duration = duration != nil ? Int(duration! * 1_000_000) : 0

        self.currentIndex = currentIndex ?? 0

        self.equalizerData = equalizerData
        self.globalEffects = globalEffects
        self.audioSourceEffects = audioSourceEffects
    }

    func toMap() throws -> [String: Any?] {
        return [
            "processingState": processingState,
            "updatePosition": updatePosition,
            "updateTime": Int(Date().timeIntervalSince1970 * 1000),
            "bufferedPosition": bufferedPosition,
            "icyMetadata": [:], // Currently not supported
            "duration": duration,
            "currentIndex": currentIndex,
            "darwinEqualizer": equalizerData?.toMap(),
            "darwinGlobalAudioEffects": try globalEffects.map { key, effect in
                try effect.toMap(key)
            },
            "darwinAudioSourceEffects": try audioSourceEffects.map { key, effect in
                try effect.toMap(key)
            },
        ]
    }

    static func == (lhs: EventChannelMessage, rhs: EventChannelMessage) -> Bool {
        lhs.processingState == rhs.processingState &&
            lhs.updatePosition == rhs.updatePosition &&
            lhs.bufferedPosition == rhs.bufferedPosition &&
            lhs.duration == rhs.duration &&
            lhs.currentIndex == rhs.currentIndex &&
            lhs.equalizerData?.frequencies == rhs.equalizerData?.frequencies &&
            lhs.equalizerData?.activePreset == rhs.equalizerData?.activePreset
    }
}

extension Equalizer {
    func toMap() -> [String: Any?] {
        return [
            "minDecibels": frequencies.first,
            "maxDecibels": frequencies.last,
            "bands": activePreset?.mapWithIndex { index, band in
                [
                    "index": index,
                    "gain": band,
                    "centerFrequency": self.frequencies[index],
                ]
            } ?? [],
            "activePreset": activePreset,
        ]
    }
}

public extension Array {
    func mapWithIndex<T>(f: (Int, Element) -> T) -> [T] {
        return zip(startIndex ..< endIndex, self).map(f)
    }
}

extension AudioEffect {
    func toMap(_ id: String) throws -> [String: Any?] {
        var result: [String: Any?] = [
            "id": id,
            "enable": !bypass,
            "type": try type,
        ]

        switch self {
        case let effect as ReverbAudioEffect:
            result["wetDryMix"] = effect.wetDryMix
            result["preset"] = effect.preset
        case let effect as DelayAudioEffect:
            result["delayTime"] = effect.delayTime
            result["feedback"] = effect.feedback
            result["lowPassCutoff"] = effect.lowPassCutoff
            result["wetDryMix"] = effect.wetDryMix
        case let effect as DistortionAudioEffect:
            result["wetDryMix"] = effect.wetDryMix
            result["preset"] = effect.preset
            result["preGain"] = effect.preGain
        default:
            print("Unknown type of audio effect, \(self)")
        }

        return result
    }
}
