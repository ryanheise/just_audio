//
//  URL.swift
//  Pods-SwiftAudioPlayer_Example
//
//  Created by Tanha Kabir on 2019-01-29.
//

import Foundation

extension URL {
    var key: String {
        return "audio_\(absoluteString.hashed)"
    }
}

private extension String {
    var hashed: UInt64 {
        var result = UInt64(8742)
        let buf = [UInt8](utf8)
        for b in buf {
            result = 127 * (result & 0x00FF_FFFF_FFFF_FFFF) + UInt64(b)
        }
        return result
    }
}
