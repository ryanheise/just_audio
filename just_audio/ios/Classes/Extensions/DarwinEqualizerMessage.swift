//
//  DarwinEqualizerMessage.swift
//  just_audio
//
//  Created by Mac on 24/09/22.
//
import kMusicSwift

extension [String: Any?] {
    /// returns an equalizer with an activated preset
    var equalizer: Equalizer? {
        get throws {
            if self["type"] as? String != "DarwinEqualizer" {
                return nil
            }

            let enabled = self["enabled"] as! Bool
            let parameters = self["parameters"] as! [String: Any]

            let rawBands = parameters["bands"] as! [[String: Any]]
            let frequenciesAndBands = rawBands.map { map in
                let frequency = map["centerFrequency"] as! Double
                let gain = map["gain"] as! Double
                return (Int(frequency), Float(gain * 2.8)) // Magic Simo constant
            }

            let frequencies = frequenciesAndBands.map { frequency, _ in
                frequency
            }

            let bands = frequenciesAndBands.map { _, band in
                band
            }

            let equalizer = try Equalizer(frequencies: frequencies, preSets: [bands])

            try equalizer.activate(preset: 0)

            return equalizer
        }
    }
}
