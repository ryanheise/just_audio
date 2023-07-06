//
//  AudioConverterListener.swift
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

import AudioToolbox
import AVFoundation
import Foundation

func ConverterListener(_: AudioConverterRef, _ packetCount: UnsafeMutablePointer<UInt32>, _ ioData: UnsafeMutablePointer<AudioBufferList>, _ outPacketDescriptions: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    let selfAudioConverter = Unmanaged<AudioConverter>.fromOpaque(context!).takeUnretainedValue()

    guard let parser = selfAudioConverter.parser else {
        Log.monitor("ReaderMissingParserError")
        return ReaderMissingParserError
    }

    guard let fileAudioFormat = parser.fileAudioFormat else {
        Log.monitor("ReaderMissingSourceFormatError")
        return ReaderMissingSourceFormatError
    }

    var audioPacketFromParser: (AudioStreamPacketDescription?, Data)?
    do {
        audioPacketFromParser = try parser.pullPacket(atIndex: selfAudioConverter.currentAudioPacketIndex)
        Log.debug("received packet from parser at index: \(selfAudioConverter.currentAudioPacketIndex)")
    } catch ParserError.notEnoughDataForReader {
        return ReaderNotEnoughDataError
    } catch ParserError.readerAskingBeyondEndOfFile {
        // On output, the number of packets of audio data provided for conversion,
        // or 0 if there is no more data to convert.
        packetCount.pointee = 0
        return ReaderReachedEndOfDataError
    } catch {
        return ReaderShouldNotHappenError
    }

    guard let audioPacket = audioPacketFromParser else {
        return ReaderShouldNotHappenError
    }

    if let lastBuffer = selfAudioConverter.converterBuffer {
        lastBuffer.deallocate()
    }

    // Copy data over (note we've only processing a single packet of data at a time)
    var packet = audioPacket.1
    let packetByteCount = packet.count // this is not the count of an array
    ioData.pointee.mNumberBuffers = 1
    ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer.allocate(byteCount: packetByteCount, alignment: 0)
    _ = packet.accessMutableBytes { (bytes: UnsafeMutablePointer<UInt8>) in
        memcpy((ioData.pointee.mBuffers.mData?.assumingMemoryBound(to: UInt8.self))!, bytes, packetByteCount)
    }
    ioData.pointee.mBuffers.mDataByteSize = UInt32(packetByteCount)

    selfAudioConverter.converterBuffer = ioData.pointee.mBuffers.mData

    // Handle packet descriptions for compressed formats (MP3, AAC, etc)
    let fileFormatDescription = fileAudioFormat.streamDescription.pointee
    if fileFormatDescription.mFormatID != kAudioFormatLinearPCM {
        if outPacketDescriptions?.pointee == nil {
            if let lastDescription = selfAudioConverter.converterDescriptions {
                lastDescription.deallocate()
            }

            outPacketDescriptions?.pointee = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
        }
        outPacketDescriptions?.pointee?.pointee.mDataByteSize = UInt32(packetByteCount)
        outPacketDescriptions?.pointee?.pointee.mStartOffset = 0
        outPacketDescriptions?.pointee?.pointee.mVariableFramesInPacket = 0
    }

    selfAudioConverter.converterDescriptions = outPacketDescriptions?.pointee

    packetCount.pointee = 1

    // we've successfully given a packet to the LPCM buffer now we can process the next audio packet
    selfAudioConverter.currentAudioPacketIndex = selfAudioConverter.currentAudioPacketIndex + 1

    return noErr
}
