//
//  AudioParsable.swift
//  SwiftAudioPlayer
//
//  Created by Tanha Kabir on 2019-01-29.
//  Copyright © 2019 Tanha Kabir, Jon Mercer
//
//  This file was modified and adapted from https://github.com/syedhali/AudioStreamer
//  which was released under Apache License 2.0. Apache License 2.0 requires explicit
//  documentation of modified files from source and a copy of the Apache License 2.0
//  in the project which is under the name Credited_LICENSE.
//
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

import AVFoundation
import Foundation

protocol AudioParsable { // For the layer above us
    var fileAudioFormat: AVAudioFormat? { get }
    var totalPredictedPacketCount: AVAudioPacketCount { get }
    func tellSeek(toIndex index: AVAudioPacketCount)
    func pollRangeOfSecondsAvailableFromNetwork() -> (Needle, Duration)
    func pullPacket(atIndex index: AVAudioPacketCount) throws -> (AudioStreamPacketDescription?, Data)
    func invalidate() // deinit caused concurrency problems
}

extension AudioParsable { // For the layer above us
    var predictedDuration: Duration? {
        guard let sampleRate = fileAudioFormat?.sampleRate else { return nil }
        guard let totalPredictedFrameCount = totalPredictedAudioFrameCount else { return nil }
        return Duration(totalPredictedFrameCount) / Duration(sampleRate)
    }

    var totalPredictedAudioFrameCount: AUAudioFrameCount? {
        guard let framesPerPacket = fileAudioFormat?.streamDescription.pointee.mFramesPerPacket else { return nil }
        return AVAudioFrameCount(totalPredictedPacketCount) * AVAudioFrameCount(framesPerPacket)
    }
}
