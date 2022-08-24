//
//  CMTime.swift
//  just_audio
//
//  Created by kuama on 22/08/22.
//

import Foundation
extension CMTime {
    var milliseconds: Int64 {
        return self == CMTime.invalid ? -1 : Int64(value * 1000 / Int64(timescale))
    }

    var microseconds: Int64 {
        return self == CMTime.invalid ? -1 : Int64(value * 1_000_000 / Int64(timescale))
    }
}
