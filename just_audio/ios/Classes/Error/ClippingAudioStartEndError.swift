//
//  ClippingAudioStartEndError.swift
//  kMusicSwift
//
//  Created by kuama on 05/09/22.
//

import Foundation

/**
 * Thrown when trying to create a `ClippingAudioSource` with inconsistent start / end values
 */
public class ClippingAudioStartEndError: JustAudioPlayerError {
    override public var baseDescription: String {
        "End must be greater than start"
    }
}
