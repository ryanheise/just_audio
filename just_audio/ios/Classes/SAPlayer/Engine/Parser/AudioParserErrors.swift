//
//  AudioParserErrors.swift
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

enum ParserError: LocalizedError {
    case couldNotOpenStream
    case failedToParseBytes(OSStatus)
    case notEnoughDataForReader
    case readerAskingBeyondEndOfFile

    var errorDescription: String? {
        switch self {
        case .couldNotOpenStream:
            return "Could not open stream for parsing"
        case let .failedToParseBytes(status):
            return localizedDescriptionFromParseError(status)
        case .notEnoughDataForReader:
            return "Not enough data for reader. Will attemp to seek"
        case .readerAskingBeyondEndOfFile:
            return "Reader asking for packets beyond the end of file"
        }
    }

    func localizedDescriptionFromParseError(_ status: OSStatus) -> String {
        switch status {
        case kAudioFileStreamError_UnsupportedFileType:
            return "The file type is not supported"
        case kAudioFileStreamError_UnsupportedDataFormat:
            return "The data format is not supported by this file type"
        case kAudioFileStreamError_UnsupportedProperty:
            return "The property is not supported"
        case kAudioFileStreamError_BadPropertySize:
            return "The size of the property data was not correct"
        case kAudioFileStreamError_NotOptimized:
            return "It is not possible to produce output packets because the file's packet table or other defining"
        case kAudioFileStreamError_InvalidPacketOffset:
            return "A packet offset was less than zero, or past the end of the file,"
        case kAudioFileStreamError_InvalidFile:
            return "The file is malformed, or otherwise not a valid instance of an audio file of its type, or is not recognized as an audio file"
        case kAudioFileStreamError_ValueUnknown:
            return "The property value is not present in this file before the audio data"
        case kAudioFileStreamError_DataUnavailable:
            return "The amount of data provided to the parser was insufficient to produce any result"
        case kAudioFileStreamError_IllegalOperation:
            return "An illegal operation was attempted"
        default:
            return "An unspecified error occurred"
        }
    }
}

/// This extension just helps us print out the name of an `AudioFileStreamPropertyID`. Purely for debugging and not essential to the main functionality of the parser.
public extension AudioFileStreamPropertyID {
    var description: String {
        switch self {
        case kAudioFileStreamProperty_ReadyToProducePackets:
            return "Ready to produce packets"
        case kAudioFileStreamProperty_FileFormat:
            return "File format"
        case kAudioFileStreamProperty_DataFormat:
            return "Data format"
        case kAudioFileStreamProperty_AudioDataByteCount:
            return "Byte count"
        case kAudioFileStreamProperty_AudioDataPacketCount:
            return "Packet count"
        case kAudioFileStreamProperty_DataOffset:
            return "Data offset"
        case kAudioFileStreamProperty_BitRate:
            return "Bit rate"
        case kAudioFileStreamProperty_FormatList:
            return "Format list"
        case kAudioFileStreamProperty_MagicCookieData:
            return "Magic cookie"
        case kAudioFileStreamProperty_MaximumPacketSize:
            return "Max packet size"
        case kAudioFileStreamProperty_ChannelLayout:
            return "Channel layout"
        case kAudioFileStreamProperty_PacketToFrame:
            return "Packet to frame"
        case kAudioFileStreamProperty_FrameToPacket:
            return "Frame to packet"
        case kAudioFileStreamProperty_PacketToByte:
            return "Packet to byte"
        case kAudioFileStreamProperty_ByteToPacket:
            return "Byte to packet"
        case kAudioFileStreamProperty_PacketTableInfo:
            return "Packet table"
        case kAudioFileStreamProperty_PacketSizeUpperBound:
            return "Packet size upper bound"
        case kAudioFileStreamProperty_AverageBytesPerPacket:
            return "Average bytes per packet"
        case kAudioFileStreamProperty_InfoDictionary:
            return "Info dictionary"
        default:
            return "Unknown"
        }
    }
}
