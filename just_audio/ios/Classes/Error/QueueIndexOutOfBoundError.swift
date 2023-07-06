//
// QueueIndexOutOfBoundError.swift
// kMusicSwift
// Created by Kuama Dev Team on 02/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

/**
 * Thrown when trying to access an `AudioSource` with a wrong index
 */
public class QueueIndexOutOfBoundError: JustAudioPlayerError {
    public let count: Int
    public let index: Int

    init(index: Int, count: Int) {
        self.count = count
        self.index = index
        super.init()
    }

    override public var baseDescription: String {
        "Requested index (\(index)) is missing. Total queue count is \(count)"
    }
}
