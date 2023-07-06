//
//  SpeedValueNotValidError.swift
//  kMusicSwift
//
//  Created by kuama on 12/09/22.
//

import Foundation

/**
 * Thrown when the given value for volume is not valid
 */
public class SpeedValueNotValidError: JustAudioPlayerError {
    public let value: Float

    init(value: Float) {
        self.value = value
        super.init()
    }

    override public var baseDescription: String {
        "Volume not valid: \(value.description), possible range between 0.0 and 32.0"
    }
}
