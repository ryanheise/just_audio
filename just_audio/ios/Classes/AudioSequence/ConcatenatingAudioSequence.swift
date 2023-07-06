//
// ConcatenatingAudioSequence.swift
// kMusicSwift
// Created by Kuama Dev Team on 01/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

/**
 An `AudioSequence` that holds a list of `IndexedAudioSequence`, may represents a playlist of songs
 */
public class ConcatenatingAudioSequence: AudioSequence {
    public var sequence: [AudioSource] = []

    public var currentSequenceIndex: Int?

    public var playbackOrder: [Int] = []

    func concatenatingInsertAll(at _: Int, sources _: [AudioSequence], shuffleIndexes _: [Int]) {}
    func concatenatingRemoveRange(from _: Int, to _: Int, shuffleIndexes _: [Int]) {}

    public init(with audioSources: [AudioSource]) {
        sequence = audioSources
        playbackOrder = audioSources.indices.map { $0 }
    }
}
