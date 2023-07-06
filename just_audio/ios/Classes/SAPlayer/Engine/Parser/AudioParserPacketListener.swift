//
//  AudioParserPacketListener.swift
//  SwiftAudioPlayer
//
//  Created by Tanha Kabir on 2019-01-29.
//  Copyright © 2019 Tanha Kabir, Jon Mercer, Moy Inzunza
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

#if swift(>=5.3)
    func ParserPacketListener(_ context: UnsafeMutableRawPointer, _ byteCount: UInt32, _ packetCount: UInt32, _ streamData: UnsafeRawPointer, _ packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        parserPacket(context, byteCount, packetCount, streamData, packetDescriptions)
    }

#else
    func ParserPacketListener(_ context: UnsafeMutableRawPointer, _ byteCount: UInt32, _ packetCount: UInt32, _ streamData: UnsafeRawPointer, _ packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>) {
        parserPacket(context, byteCount, packetCount, streamData, packetDescriptions)
    }
#endif

func parserPacket(_ context: UnsafeMutableRawPointer, _: UInt32, _ packetCount: UInt32, _ streamData: UnsafeRawPointer, _ packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
    let selfAudioParser = Unmanaged<AudioParser>.fromOpaque(context).takeUnretainedValue()

    guard let fileAudioFormat = selfAudioParser.fileAudioFormat else {
        Log.monitor("should not have reached packet listener without a data format")
        return
    }

    guard selfAudioParser.shouldPreventPacketFromFillingUp == false else {
        Log.error("skipping parsing packets because of seek")
        return
    }

    // TODO: refactor this after we get it working
    if let compressedPacketDescriptions = packetDescriptions { // is compressed audio (.mp3)
        Log.debug("compressed audio")
        for i in 0 ..< Int(packetCount) {
            let audioPacketDescription = compressedPacketDescriptions[i]
            let audioPacketStart = Int(audioPacketDescription.mStartOffset)
            let audioPacketSize = Int(audioPacketDescription.mDataByteSize)
            let audioPacketData = Data(bytes: streamData.advanced(by: audioPacketStart), count: audioPacketSize)
            selfAudioParser.append(description: audioPacketDescription, data: audioPacketData)
        }
    } else { // not compressed audio (.wav)
        Log.debug("uncompressed audio")
        let format = fileAudioFormat.streamDescription.pointee
        let bytesPerAudioPacket = Int(format.mBytesPerPacket)
        for i in 0 ..< Int(packetCount) {
            let audioPacketStart = i * bytesPerAudioPacket
            let audioPacketSize = bytesPerAudioPacket
            let audioPacketData = Data(bytes: streamData.advanced(by: audioPacketStart), count: audioPacketSize)
            selfAudioParser.append(description: nil, data: audioPacketData)
        }
    }
}
