//
//  PlaybackEvent.swift
//  just_audio
//
//  Created by kuama on 22/08/22.
//

import Foundation

struct PlaybackEvent {
    let processingState: ProcessingState
    let updatePosition: CMTime
    let updateTime: Int64
    let duration: CMTime
    let currentIndex: Int
}
