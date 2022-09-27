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

    init(processingState: ProcessingState?, elapsedTime: Double?, bufferedPosition: Double?, duration: Double?, currentIndex: Int?) {
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
    }

    func toMap() -> [String: Any?] {
        return [
            "processingState": processingState,
            "updatePosition": updatePosition,
            "updateTime": Int(Date().timeIntervalSince1970 * 1000),
            "bufferedPosition": bufferedPosition,
            "icyMetadata": [:], // Currently not supported
            "duration": duration,
            "currentIndex": currentIndex,
        ]
    }

    static func == (lhs: EventChannelMessage, rhs: EventChannelMessage) -> Bool {
        lhs.processingState == rhs.processingState &&
            lhs.updatePosition == rhs.updatePosition &&
            lhs.bufferedPosition == rhs.bufferedPosition &&
            lhs.duration == rhs.duration &&
            lhs.currentIndex == rhs.currentIndex
    }
}
