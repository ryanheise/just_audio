//
//  AudioConverterErrors.swift
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

let ReaderReachedEndOfDataError: OSStatus = 932_332_581
let ReaderNotEnoughDataError: OSStatus = 932_332_582
let ReaderMissingSourceFormatError: OSStatus = 932_332_583
let ReaderMissingParserError: OSStatus = 932_332_584
let ReaderShouldNotHappenError: OSStatus = 932_332_585

public enum ConverterError: LocalizedError {
    case cannotLockQueue
    case converterFailed(OSStatus)
    case cannotCreatePCMBufferWithoutConverter
    case failedToCreateDestinationFormat
    case failedToCreatePCMBuffer
    case notEnoughData
    case parserMissingDataFormat
    case reachedEndOfFile
    case unableToCreateConverter(OSStatus)
    case superConcerningShouldNeverHappen
    case throttleParsingBuffersForEngine
    case failedToCreateParser

    public var errorDescription: String? {
        switch self {
        case .cannotLockQueue:
            Log.warn("Failed to lock queue")
            return "Failed to lock queue"
        case let .converterFailed(status):
            Log.warn(localizedDescriptionFromConverterError(status))
            return localizedDescriptionFromConverterError(status)
        case .failedToCreateDestinationFormat:
            Log.warn("Failed to create a destination (processing) format")
            return "Failed to create a destination (processing) format"
        case .failedToCreatePCMBuffer:
            Log.warn("Failed to create PCM buffer for reading data")
            return "Failed to create PCM buffer for reading data"
        case .notEnoughData:
            Log.warn("Not enough data for read-conversion operation")
            return "Not enough data for read-conversion operation"
        case .parserMissingDataFormat:
            Log.warn("Parser is missing a valid data format")
            return "Parser is missing a valid data format"
        case .reachedEndOfFile:
            Log.warn("Reached the end of the file")
            return "Reached the end of the file"
        case let .unableToCreateConverter(status):
            return localizedDescriptionFromConverterError(status)
        case .superConcerningShouldNeverHappen:
            Log.warn("Weird unexpected reader error. Should not have happened")
            return "Weird unexpected reader error. Should not have happened"
        case .cannotCreatePCMBufferWithoutConverter:
            Log.debug("Could not create a PCM Buffer because reader does not have a converter yet")
            return "Could not create a PCM Buffer because reader does not have a converter yet"
        case .throttleParsingBuffersForEngine:
            Log.warn("Preventing the reader from creating more PCM buffers since the player has more than 60 seconds of audio already to play")
            return "Preventing the reader from creating more PCM buffers since the player has more than 60 seconds of audio already to play"
        case .failedToCreateParser:
            Log.warn("Could not create a parser")
            return "Could not create a parser"
        }
    }

    func localizedDescriptionFromConverterError(_ status: OSStatus) -> String {
        switch status {
        case kAudioConverterErr_FormatNotSupported:
            return "Format not supported"
        case kAudioConverterErr_OperationNotSupported:
            return "Operation not supported"
        case kAudioConverterErr_PropertyNotSupported:
            return "Property not supported"
        case kAudioConverterErr_InvalidInputSize:
            return "Invalid input size"
        case kAudioConverterErr_InvalidOutputSize:
            return "Invalid output size"
        case kAudioConverterErr_BadPropertySizeError:
            return "Bad property size error"
        case kAudioConverterErr_RequiresPacketDescriptionsError:
            return "Requires packet descriptions"
        case kAudioConverterErr_InputSampleRateOutOfRange:
            return "Input sample rate out of range"
        case kAudioConverterErr_OutputSampleRateOutOfRange:
            return "Output sample rate out of range"
        case kAudioConverterErr_HardwareInUse:
            return "Hardware is in use"
        case kAudioConverterErr_NoHardwarePermission:
            return "No hardware permission"
        default:
            return "Unspecified error"
        }
    }
}
