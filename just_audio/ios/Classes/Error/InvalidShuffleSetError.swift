//
// InvalidShuffleSetError.swift
// kMusicSwift
// Created by Kuama Dev Team on 05/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

/**
 * Thrown when trying to shuffle a queue with an invalid shuffle array
 */
public class InvalidShuffleSetError: JustAudioPlayerError {
    public let targetedQueueCount: Int

    init(targetedQueueCount: Int) {
        self.targetedQueueCount = targetedQueueCount
        super.init()
    }

    override public var baseDescription: String {
        "The shuffle array provided has incorrect count. The targeted queue has \(targetedQueueCount) elements"
    }
}
