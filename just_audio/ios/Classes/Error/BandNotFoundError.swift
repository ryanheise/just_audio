//
// BandNotFoundError.swift
// kMusicSwift
// Created by Kuama Dev Team on 08/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

/**
 * Thrown when trying to update the value of a non-existent equalizer band
 */
public class BandNotFoundError: JustAudioPlayerError {
    public let bandIndex: Int
    public let bandsCount: Int

    init(bandIndex: Int, bandsCount: Int) {
        self.bandIndex = bandIndex
        self.bandsCount = bandsCount
        super.init()
    }

    override public var baseDescription: String {
        "Trying to update a non existent band \(bandIndex). Current bands count \(bandsCount)"
    }
}
