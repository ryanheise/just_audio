//
// WrongPreSetForFrequencesError.swift
// kMusicSwift
// Created by Kuama Dev Team on 08/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

/**
 * The given preset does not have same elements count of the initial frequencies
 */
public class WrongPreSetForFrequencesError: JustAudioPlayerError {
    public let preSet: PreSet
    public let frequencies: [Int]

    init(preSet: PreSet, frequencies: [Int]) {
        self.preSet = preSet
        self.frequencies = frequencies
        super.init()
    }

    override public var baseDescription: String {
        "Trying to provide an invalid preset \(preSet) for frequencies \(frequencies)"
    }
}
