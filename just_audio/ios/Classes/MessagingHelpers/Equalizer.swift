//
//  DarwinEqualizerMessage.swift
//  just_audio
//
//  Created by Mac on 24/09/22.
//
import kMusicSwift

extension Equalizer {
    /// returns an equalizer with an activated preset
    static func parse(from map: [String: Any?]) throws -> Equalizer? {
        if map["type"] as? String != "DarwinEqualizer" {
            return nil
        }

        let parameters = map["parameters"] as! [String: Any]

        let rawBands = parameters["bands"] as! [[String: Any]]
        let frequenciesAndBands = rawBands.map { map in
            let frequency = map["centerFrequency"] as! Double
            let gain = map["gain"] as! Double
            return (Int(frequency), Util.gainFrom(Float(gain)))
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

    func toMap() -> [String: Any?] {
        return [
            "minDecibels": Double(frequencies.first!),
            "maxDecibels": Double(frequencies.last!),
            "bands": activePreset?.mapWithIndex { index, band in
                [
                    "index": index,
                    "gain": Double(band),
                    "centerFrequency": Double(self.frequencies[index]),
                ]
            } ?? [],
            "activePreset": activePreset,
        ]
    }
}
