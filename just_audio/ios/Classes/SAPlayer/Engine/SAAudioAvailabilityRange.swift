//
//  SAAudioAvailabilityRange.swift
//  SwiftAudioPlayer
//
//  Created by Tanha Kabir on 2019-02-18.
//  Copyright © 2019 Tanha Kabir, Jon Mercer
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation

// Think of it as the grey buffer line from youtube
public struct SAAudioAvailabilityRange {
    let startingNeedle: Needle
    let durationLoadedByNetwork: Duration
    let predictedDurationToLoad: Duration
    let isPlayable: Bool

    public var bufferingProgress: Double {
        return (startingNeedle + durationLoadedByNetwork) / predictedDurationToLoad
    }

    public var startingBufferTimePositon: Double {
        return startingNeedle
    }

    public var totalDurationBuffered: Double {
        return durationLoadedByNetwork
    }

    public var isReadyForPlaying: Bool {
        return isPlayable
    }

    var secondsLeftToBuffer: Double {
        return predictedDurationToLoad - (startingNeedle + durationLoadedByNetwork)
    }

    public func contains(_ needle: Double) -> Bool {
        return needle >= startingNeedle && (needle - startingNeedle) < durationLoadedByNetwork
    }

    public func reachedEndOfAudio(needle: Double) -> Bool {
        var needleAtEnd = false

        if totalDurationBuffered > 0, needle > 0 {
            needleAtEnd = needle >= totalDurationBuffered - 5
        }

        // if most of the audio is buffered for long audio or in short audio there isn't many seconds left to buffer it means wwe've reached the end of the audio

        let isBuffered = (bufferingProgress > 0.99 || secondsLeftToBuffer < 5)

        return isBuffered && needleAtEnd
    }

    public func isCompletelyBuffered() -> Bool {
        return startingNeedle + durationLoadedByNetwork >= predictedDurationToLoad
    }
}
