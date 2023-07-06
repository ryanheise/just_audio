//
//  AudioParserPropertyListener.swift
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

func ParserPropertyListener(_ context: UnsafeMutableRawPointer, _ streamId: AudioFileStreamID, _ propertyId: AudioFileStreamPropertyID, _: UnsafeMutablePointer<AudioFileStreamPropertyFlags>) {
    let selfAudioParser = Unmanaged<AudioParser>.fromOpaque(context).takeUnretainedValue()

    Log.info("audio file stream property: \(propertyId.description)")
    switch propertyId {
    case kAudioFileStreamProperty_DataFormat:
        var fileAudioFormat = AudioStreamBasicDescription()
        GetPropertyValue(&fileAudioFormat, streamId, propertyId)
        selfAudioParser.fileAudioFormat = AVAudioFormat(streamDescription: &fileAudioFormat)
    case kAudioFileStreamProperty_AudioDataPacketCount:
        GetPropertyValue(&selfAudioParser.parsedAudioHeaderPacketCount, streamId, propertyId)
    case kAudioFileStreamProperty_AudioDataByteCount:
        GetPropertyValue(&selfAudioParser.parsedAudioPacketDataSize, streamId, propertyId)
        selfAudioParser.expectedFileSizeInBytes = selfAudioParser.parsedAudioDataOffset + selfAudioParser.parsedAudioPacketDataSize
    case kAudioFileStreamProperty_DataOffset:
        GetPropertyValue(&selfAudioParser.parsedAudioDataOffset, streamId, propertyId)

        if selfAudioParser.parsedAudioPacketDataSize != 0 {
            selfAudioParser.expectedFileSizeInBytes = selfAudioParser.parsedAudioDataOffset + selfAudioParser.parsedAudioPacketDataSize
        }

    default:
        break
    }
}

// property is like the medatada of
func GetPropertyValue<T>(_ value: inout T, _ streamId: AudioFileStreamID, _ propertyId: AudioFileStreamPropertyID) {
    var propertySize: UInt32 = 0
    guard AudioFileStreamGetPropertyInfo(streamId, propertyId, &propertySize, nil) == noErr else { // try to get the size of the property
        Log.monitor("failed to get info for property:\(propertyId.description)")
        return
    }

    guard AudioFileStreamGetProperty(streamId, propertyId, &propertySize, &value) == noErr else {
        Log.monitor("failed to get propery value for: \(propertyId.description)")
        return
    }
}
