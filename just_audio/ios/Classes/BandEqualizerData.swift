//
//  BandEqualizerData.swift
//  just_audio
//
//  Created by kuama on 22/08/22.
//

import Foundation

struct BandEqualizerData: Codable {
    let index: Int
    let centerFrequency: Float
    let gain: Float
}
