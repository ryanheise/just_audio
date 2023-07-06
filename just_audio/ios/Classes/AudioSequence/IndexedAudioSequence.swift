//
// IndexedAudioSequence.swift
// kMusicSwift
// Created by Kuama Dev Team on 01/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

/**
 An `AudioSequence` that can appear in a sequence. Represents a single audio file (naming is inherited from `just_audio` plugin)
 */
public class IndexedAudioSequence: AudioSequence {
    private var onlySequenceIndex: Int?

    public var currentSequenceIndex: Int? {
        get {
            return onlySequenceIndex
        }

        set(value) {
            if value != nil {
                onlySequenceIndex = 0
            } else {
                onlySequenceIndex = nil
            }
        }
    }

    public var playbackOrder: [Int] {
        set {
            // no op
        }

        get {
            return [0]
        }
    }

    public var sequence: [AudioSource] = []

    public init(with singleAudioSource: AudioSource) {
        sequence = [singleAudioSource]
        playbackOrder = [0]
    }

    public var playingStatus: AudioSourcePlayingStatus {
        return sequence[playbackOrder.first!].playingStatus
    }

    public func setPlayingStatus(_ nextStatus: AudioSourcePlayingStatus) throws {
        guard let sequenceIndex = currentSequenceIndex else {
            throw InconsistentStateError(message: "Please set the current index before setting the playing status")
        }
        return try sequence[sequenceIndex].setPlayingStatus(nextStatus)
    }
}
