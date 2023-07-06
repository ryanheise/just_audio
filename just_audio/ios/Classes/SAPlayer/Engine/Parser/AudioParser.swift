//
//  AudioParser.swift
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

/**
 DEFINITIONS

 An audio stream is a continuous series of data that represents a sound, such as a song.

 A channel is a discrete track of monophonic audio. A monophonic stream has one channel; a stereo stream has two channels.

 A sample is single numerical value for a single audio channel in an audio stream.

 A frame is a collection of time-coincident samples. For instance, a linear PCM stereo sound file has two samples per frame, one for the left channel and one for the right channel.

 A packet is a collection of one or more contiguous frames. A packet defines the smallest meaningful set of frames for a given audio data format, and is the smallest data unit for which time can be measured. In linear PCM audio, a packet holds a single frame. In compressed formats, it typically holds more; in some formats, the number of frames per packet varies.

 The sample rate for a stream is the number of frames per second of uncompressed (or, for compressed formats, the equivalent in decompressed) audio.

 */

// TODO: what if user seeks beyond the data we have? What if we're done but user seeks even further than what we have

class AudioParser: AudioParsable {
    private var MIN_PACKETS_TO_HAVE_AVAILABLE_BEFORE_THROTTLING_PARSING = 8192 // this will be modified when we know the file format to be just enough packets to fill up 1 pcm buffer
    private var framesPerBuffer: Int = 1

    // MARK: - For OS parser class

    var parsedAudioHeaderPacketCount: UInt64 = 0
    var parsedAudioPacketDataSize: UInt64 = 0
    var parsedAudioDataOffset: UInt64 = 0
    var streamID: AudioFileStreamID?
    public var fileAudioFormat: AVAudioFormat? {
        didSet {
            if let format = fileAudioFormat, oldValue == nil {
                MIN_PACKETS_TO_HAVE_AVAILABLE_BEFORE_THROTTLING_PARSING = framesPerBuffer / Int(format.streamDescription.pointee.mFramesPerPacket)
                parsedFileAudioFormatCallback(format)
            }
        }
    }

    // MARK: - Our vars

    // Init
    let url: AudioURL
    var throttler: AudioThrottleable!

    // Our use
    var expectedFileSizeInBytes: UInt64?
    var networkProgress: Double = 0
    var parsedFileAudioFormatCallback: (AVAudioFormat) -> Void
    var indexSeekOffset: AVAudioPacketCount = 0
    var shouldPreventPacketFromFillingUp = false

    public var totalPredictedPacketCount: AVAudioPacketCount {
        if parsedAudioHeaderPacketCount != 0 {
            // TODO: we should log the duration to the server for better user experience
            return max(AVAudioPacketCount(parsedAudioHeaderPacketCount), AVAudioPacketCount(audioPackets.count))
        }

        let sizeOfFileInBytes: UInt64 = expectedFileSizeInBytes != nil ? expectedFileSizeInBytes! : 0

        guard let bytesPerPacket = averageBytesPerPacket else {
            return AVAudioPacketCount(0)
        }

        let predictedCount = AVAudioPacketCount(Double(sizeOfFileInBytes) / bytesPerPacket)

        guard networkProgress != 1.0 else {
            return min(AVAudioPacketCount(audioPackets.count), predictedCount)
        }

        return predictedCount
    }

    var sumOfParsedAudioBytes: UInt32 = 0
    var numberOfPacketsParsed: UInt32 = 0
    var audioPackets: [(AudioStreamPacketDescription?, Data)] = [] {
        didSet {
            if let audioPacketByteSize = audioPackets.last?.0?.mDataByteSize {
                sumOfParsedAudioBytes += audioPacketByteSize
            } else if let audioPacketByteSize = audioPackets.last?.1.count { // for uncompressed audio there are no descriptors to say how many bytes of audio are in this packet so we approximate by data size
                sumOfParsedAudioBytes += UInt32(audioPacketByteSize)
            }

            numberOfPacketsParsed += 1

            // TODO: duration will not be accurate with WAV or AIFF
        }
    }

    private let lockQueue = DispatchQueue(label: "SwiftAudioPlayer.Parser.packets.lock")
    var lastSentAudioPacketIndex = -1

    /**
     Audio packets varry in size. The first one parsed in a batch of audio
     packets is usually off by 1 from the others. We use the
     averageByesPerPacket for two things. 1. Predicting total audio packet count
     which is used for duration. 2. Calculate seeking spot for throttler and
     network seek. This used to be an Int but caused inacuracies for longer
     podcasts. Since Double->Int is floored the parser would ask for byte 979312
     but that spot is actually suppose to be 982280 from the throttler's perspective
     */
    var averageBytesPerPacket: Double? {
        if numberOfPacketsParsed == 0 {
            return nil
        }

        return Double(sumOfParsedAudioBytes) / Double(numberOfPacketsParsed)
    }

    var isParsingComplete: Bool {
        guard fileAudioFormat != nil else {
            return false
        }
        // TODO: will this ever return true? Predicted uses MAX of prediction of total packet length
        return audioPackets.count == totalPredictedPacketCount
    }

    var streamChangeListenerId: UInt?

    private var streamingDownloadDirector: StreamingDownloadDirector

    init(withRemoteUrl url: AudioURL, bufferSize: Int, withAudioDataManager audioDataManager: AudioDataManager, withStreamingDownloadDirector streamingDownloadDirector: StreamingDownloadDirector, parsedFileAudioFormatCallback: @escaping (AVAudioFormat) -> Void) throws {
        self.url = url
        framesPerBuffer = bufferSize
        self.parsedFileAudioFormatCallback = parsedFileAudioFormatCallback
        self.streamingDownloadDirector = streamingDownloadDirector
        throttler = AudioThrottler(withRemoteUrl: url, withDelegate: self, withAudioDataManager: audioDataManager, withStreamingDownloadDirector: streamingDownloadDirector)

        streamChangeListenerId = streamingDownloadDirector.attach { [weak self] progress in
            guard let self = self else { return }
            self.networkProgress = progress

            // initially parse a bunch of packets
            self.lockQueue.sync {
                if self.fileAudioFormat == nil {
                    self.processNextDataPacket()
                } else if self.audioPackets.count - self.lastSentAudioPacketIndex < self.MIN_PACKETS_TO_HAVE_AVAILABLE_BEFORE_THROTTLING_PARSING {
                    self.processNextDataPacket()
                }
            }
        }

        let context = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        // Open the stream and when we call parse data is fed into this stream
        guard AudioFileStreamOpen(context, ParserPropertyListener, ParserPacketListener, kAudioFileMP3Type, &streamID) == noErr else {
            throw ParserError.couldNotOpenStream
        }
    }

    deinit {
        if let id = streamChangeListenerId {
            streamingDownloadDirector.detach(withID: id)
        }
    }

    func pullPacket(atIndex index: AVAudioPacketCount) throws -> (AudioStreamPacketDescription?, Data) {
        determineIfMoreDataNeedsToBeParsed(index: index)

        // Check if we've reached the end of the packets. We have two scenarios:
        //     1. We've reached the end of the packet data and the file has been completely parsed
        //     2. We've reached the end of the data we currently have downloaded, but not the file

        let packetIndex = index - indexSeekOffset

        var exception: ParserError?
        var packet: (AudioStreamPacketDescription?, Data) = (nil, Data())
        lockQueue.sync { [weak self] in
            guard let self = self else {
                return
            }
            if packetIndex >= self.audioPackets.count {
                if isParsingComplete {
                    exception = ParserError.readerAskingBeyondEndOfFile
                    return
                } else {
                    Log.debug("Tried to pull packet at index: \(packetIndex) when only have: \(self.audioPackets.count), we predict \(self.totalPredictedPacketCount) in total")
                    exception = ParserError.notEnoughDataForReader
                    return
                }
            }

            lastSentAudioPacketIndex = Int(packetIndex)
            packet = audioPackets[Int(packetIndex)]
        }
        if let exception = exception {
            throw exception
        } else {
            return packet
        }
    }

    private func determineIfMoreDataNeedsToBeParsed(index: AVAudioPacketCount) {
        lockQueue.sync { [weak self] in
            guard let self = self else {
                return
            }
            if index > self.audioPackets.count - self.MIN_PACKETS_TO_HAVE_AVAILABLE_BEFORE_THROTTLING_PARSING {
                self.processNextDataPacket()
            }
        }
    }

    func tellSeek(toIndex index: AVAudioPacketCount) {
        // Already within the processed audio packets. Ignore
        var isIndexValid = true
        lockQueue.sync { [weak self] in
            guard let self = self else {
                return
            }
            if self.indexSeekOffset <= index, index < self.audioPackets.count + Int(self.indexSeekOffset) {
                isIndexValid = false
            }
        }
        guard isIndexValid else { return }

        guard let byteOffset = getOffset(fromPacketIndex: index) else {
            return
        }
        Log.info("did not have processed audio for index: \(index) / offset: \(byteOffset)")

        indexSeekOffset = index

        // NOTE: Order matters. Need to prevent appending to the array before we clean it. Just in case
        // then we tell the throttler to send us appropriate packet
        shouldPreventPacketFromFillingUp = true
        lockQueue.sync {
            self.audioPackets = []
        }

        throttler.tellSeek(offset: byteOffset)
        processNextDataPacket()
    }

    private func getOffset(fromPacketIndex index: AVAudioPacketCount) -> UInt64? {
        // Clear current buffer if we have audio format
        guard fileAudioFormat != nil, let bytesPerPacket = averageBytesPerPacket else {
            Log.error("should not get here \(String(describing: fileAudioFormat)) and \(String(describing: averageBytesPerPacket))")
            return nil
        }

        return UInt64(Double(index) * bytesPerPacket) + parsedAudioDataOffset
    }

    func pollRangeOfSecondsAvailableFromNetwork() -> (Needle, Duration) {
        let range = throttler.pollRangeOfBytesAvailable()

        let startPacket = getPacket(fromOffset: range.0) != nil ? getPacket(fromOffset: range.0)! : 0

        guard let startFrame = getFrame(forPacket: startPacket), let startNeedle = getNeedle(forFrame: startFrame) else {
            return (0, 0)
        }

        guard let endPacket = getPacket(fromOffset: range.1), let endFrame = getFrame(forPacket: endPacket), let endNeedle = getNeedle(forFrame: endFrame) else {
            return (0, 0)
        }

        return (startNeedle, Duration(endNeedle))
    }

    private func getPacket(fromOffset offset: UInt64) -> AVAudioPacketCount? {
        guard fileAudioFormat != nil, let bytesPerPacket = averageBytesPerPacket else { return nil }
        let audioDataBytes = Int(offset) - Int(parsedAudioDataOffset)

        guard audioDataBytes > 0 else { // Because we error out if we try to set a negative number as AVAudioPacketCount which is a UInt32
            return nil
        }

        return AVAudioPacketCount(Double(audioDataBytes) / bytesPerPacket)
    }

    private func getFrame(forPacket packet: AVAudioPacketCount) -> AVAudioFrameCount? {
        guard let framesPerPacket = fileAudioFormat?.streamDescription.pointee.mFramesPerPacket else { return nil }
        return packet * framesPerPacket
    }

    private func getNeedle(forFrame frame: AVAudioFrameCount) -> Needle? {
        guard let _ = fileAudioFormat?.streamDescription.pointee, let frameCount = totalPredictedAudioFrameCount, let duration = predictedDuration else { return nil }

        guard duration > 0 else { return nil }

        return Needle(TimeInterval(frame) / TimeInterval(frameCount) * duration)
    }

    func append(description: AudioStreamPacketDescription?, data: Data) {
        lockQueue.sync {
            self.audioPackets.append((description, data))
        }
    }

    func invalidate() {
        throttler.invalidate()

        // FIXME: See Note below. Don't remove this until the problem has been properly solved
        // if let sId = streamID {
        //    let result = AudioFileStreamClose(sId)
        //    if result != noErr {
        //        Log.monitor("parser_error", ParserError.failedToParseBytes(result).errorDescription)
        //    }
        // }
        /**
         We saw a bad access in the parser. We think this is because AudioFileStreamClose is called before the parser finished parsing a set of networkPackets.

         Three solutions we thought of:
         1. Make parser a singleton and have callbacks that use and ID
         2. Do some math on network data size and parsed packets. The parsed packets get 99.9% to the network data
         3. Uncomment AudioFileStreamClose. There will be potential memory leaks

         We chose option 3 because:
         + we looked at memory hit and it was neglegible
         + simplest solution
         – we might forget about commenting this out  and run into a bug
         */
    }

    private func processNextDataPacket() {
        throttler.pullNextDataPacket { [weak self] d in
            guard let self = self else { return }
            guard let data = d else { return }

            self.lockQueue.sync {
                Log.debug("processing data count: \(data.count) :: already had \(self.audioPackets.count) audio packets")
            }
            self.shouldPreventPacketFromFillingUp = false
            do {
                let sID = self.streamID!
                let dataSize = data.count

                _ = try data.accessBytes { (bytes: UnsafePointer<UInt8>) in
                    let result: OSStatus = AudioFileStreamParseBytes(sID, UInt32(dataSize), bytes, [])
                    guard result == noErr else {
                        Log.monitor(ParserError.failedToParseBytes(result).errorDescription as Any)
                        throw ParserError.failedToParseBytes(result)
                    }
                }
            } catch {
                Log.monitor(error.localizedDescription)
            }
        }
    }
}

// MARK: - AudioThrottleDelegate

extension AudioParser: AudioThrottleDelegate {
    func didUpdate(totalBytesExpected bytes: Int64) {
        expectedFileSizeInBytes = UInt64(bytes)
    }
}
