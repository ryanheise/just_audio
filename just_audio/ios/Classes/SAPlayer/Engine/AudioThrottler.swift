//
//  AudioThrottler.swift
//  SwiftAudioPlayer
//
//  Created by Tanha Kabir on 2019-01-29.
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

protocol AudioThrottleDelegate: AnyObject {
    func didUpdate(totalBytesExpected bytes: Int64)
}

protocol AudioThrottleable {
    init(withRemoteUrl url: AudioURL, withDelegate delegate: AudioThrottleDelegate, withAudioDataManager audioDataManager: AudioDataManager, withStreamingDownloadDirector streamingDownloadDirector: StreamingDownloadDirector)
    func pullNextDataPacket(_ callback: @escaping (Data?) -> Void)
    func tellSeek(offset: UInt64)
    func pollRangeOfBytesAvailable() -> (UInt64, UInt64)
    func invalidate()
}

class AudioThrottler: AudioThrottleable {
    private let queue = DispatchQueue(label: "SwiftAudioPlayer.Throttler", qos: .userInitiated)

    // Init
    let url: AudioURL
    weak var delegate: AudioThrottleDelegate?

    private var networkData: [Data] = [] {
        didSet {
//            Log.test("NETWORK DATA \(networkData.count)")
        }
    }

    private var lastSentDataPacketIndex = -1

    var shouldThrottle = false
    var byteOffsetBecauseOfSeek: UInt = 0

    // This will be sent once at beginning of stream and every network seek
    var totalBytesExpected: Int64? {
        didSet {
            if let bytes = totalBytesExpected {
                delegate?.didUpdate(totalBytesExpected: Int64(byteOffsetBecauseOfSeek) + bytes)
            }
        }
    }

    var largestPollingOffsetDifference: UInt64 = 1

    private var audioDataManager: AudioDataManager

    required init(withRemoteUrl url: AudioURL, withDelegate delegate: AudioThrottleDelegate, withAudioDataManager audioDataManager: AudioDataManager, withStreamingDownloadDirector streamingDownloadDirector: StreamingDownloadDirector) {
        self.url = url
        self.delegate = delegate
        self.audioDataManager = audioDataManager

        audioDataManager.startStream(withRemoteURL: url) { [weak self] (pto: StreamProgressPTO) in
            guard let self = self else { return }
            Log.debug("received stream data of size \(pto.getData().count) and progress: \(pto.getProgress())")

            if let totalBytesExpected = pto.getTotalBytesExpected() {
                self.totalBytesExpected = totalBytesExpected
            }

            self.queue.async { [weak self] in
                self?.networkData.append(pto.getData())
                streamingDownloadDirector.didUpdate(url.key, networkStreamProgress: pto.getProgress())
            }
        }
    }

    func tellSeek(offset: UInt64) {
        Log.info("seek with offset: \(offset)")

        queue.async { [weak self] in
            self?.seekQueueHelper(offset)
        }
    }

    func seekQueueHelper(_ offset: UInt64) {
        let offsetToFind = Int(offset) - Int(byteOffsetBecauseOfSeek)

        var shouldStartNewStream = false

        // if we have no data start a new stream after seek
        if networkData.count == 0 {
            shouldStartNewStream = true
        }

        // if what we're looking for is outside of available data, start a new stream
        if offset < byteOffsetBecauseOfSeek || offsetToFind > networkData.sum {
            shouldStartNewStream = true
        }

        // we should have the data within our cache. find it and save the index for the next pull
        if let indexOfDataContainingOffset = networkData.getIndexContainingByteOffset(offsetToFind) {
            lastSentDataPacketIndex = indexOfDataContainingOffset - 1
        }

        if shouldStartNewStream {
            byteOffsetBecauseOfSeek = UInt(offset)
            lastSentDataPacketIndex = -1
            audioDataManager.seekStream(withRemoteURL: url, toByteOffset: offset)

            networkData = []
            return
        }

        Log.error("83672 Should not get here")
    }

    func pollRangeOfBytesAvailable() -> (UInt64, UInt64) {
        let start = byteOffsetBecauseOfSeek
        let end = networkData.sum + Int(byteOffsetBecauseOfSeek)

        return (UInt64(start), UInt64(end))
    }

    func pullNextDataPacket(_ callback: @escaping (Data?) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.lastSentDataPacketIndex < self.networkData.count - 1 else {
                callback(nil)
                return
            }

            self.lastSentDataPacketIndex += 1

            callback(self.networkData[self.lastSentDataPacketIndex])
        }
    }

    func invalidate() {
        audioDataManager.deleteStream(withRemoteURL: url)
    }
}

extension Array where Element == Data {
    var sum: Int {
        guard count > 0 else { return 0 }
        return reduce(0) { $0 + $1.count }
    }

    func getIndexContainingByteOffset(_ offset: Int) -> Int? {
        var dataCount = 0

        for (i, data) in enumerated() {
            if offset >= dataCount, offset <= dataCount + data.count {
                return i
            }

            dataCount += data.count
        }

        return nil
    }
}
