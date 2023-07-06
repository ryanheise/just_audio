//
// PreSetNotFoundError.swift
// kMusicSwift
// Created by Kuama Dev Team on 08/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

/**
 * Thrown when trying to access to a preset with out of bounds index
 */
public class PreSetNotFoundError: JustAudioPlayerError {
    public let presetIndex: Int
    public let currentList: [PreSet]

    init(_ presetIndex: Int, currentList: [PreSet]) {
        self.presetIndex = presetIndex
        self.currentList = currentList
        super.init()
    }

    override public var baseDescription: String {
        "Trying to access a preset with wrong index: \(presetIndex). Current preSet list: \(currentList)"
    }
}
