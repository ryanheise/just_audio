//
//  VolumeValueNotValidError.swift
//  kMusicSwift
//
//  Created by kuama on 29/08/22.
//

/**
 * Thrown when the given value for volume is not valid
 */
public class VolumeValueNotValidError: JustAudioPlayerError {
    public let value: Float

    init(value: Float) {
        self.value = value
        super.init()
    }

    override public var baseDescription: String {
        "Volume not valid: \(value.description), possible range between 0.0 and 1.0"
    }
}
