//
//  EqualizerEffectData.swift
//  just_audio
//
//  Created by kuama on 22/08/22.
//

import Foundation

struct EqualizerEffectData: EffectData, Codable {
    let type: EffectType
    let enabled: Bool
    let parameters: ParamsEqualizerData

    static func fromJson(_ map: [String: Any]) -> EqualizerEffectData {
        return try! JSONDecoder().decode(EqualizerEffectData.self, from: JSONSerialization.data(withJSONObject: map))
    }
}
