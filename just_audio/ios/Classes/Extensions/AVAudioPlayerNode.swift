//
//  AVAudioPlayerNode.swift
//  just_audio
//
//  Created by kuama on 22/08/22.
//

import Foundation

extension AVAudioPlayerNode {
    var currentTime: CMTime {
        if let nodeTime: AVAudioTime = lastRenderTime, let playerTime: AVAudioTime = playerTime(forNodeTime: nodeTime) {
            let currentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
            let milliSeconds = Int64(currentTime * 1000)
            return milliSeconds < 0 ? CMTime.zero : CMTime(value: milliSeconds, timescale: 1000)
        }
        return CMTime.zero
    }
}
