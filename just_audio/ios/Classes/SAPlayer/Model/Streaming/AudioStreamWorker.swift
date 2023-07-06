//
//  AudioStreamWorker.swift
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

/**
 init task
 +
 |
 |
 +-----v-----+     suspend()   +---------+          +-----------+
 | suspended <-----------------> running +----------> completed |
 +-----+-----+     resume()    +----+----+          +-----------+
 |                            |
 |                            | cancel()
 |                            |
 |          cancel()   +------v------+
 +---------------------> cancelling  |
 +-------------+
 */

protocol AudioDataStreamable {
    // if user taps download then starts to stream
    init(progressCallback: @escaping (_ id: ID, _ dto: StreamProgressDTO) -> Void, doneCallback: @escaping (_ id: ID, _ error: Error?) -> Bool) // Bool is should save or not

    var HTTPHeaderFields: [String: String]? { get set }

    func start(withID id: ID, withRemoteURL url: URL, withInitialData data: Data?, andTotalBytesExpectedPreviously previousTotalBytesExpected: Int64?)
    func pause(withId id: ID)
    func resume(withId id: ID)
    func stop(withId id: ID) // FIXME: with persistent play we should return a Data so that download can resume
    func seek(withId id: ID, withByteOffset offset: UInt64)
    func getRunningID() -> ID?
}

/// Policy for streaming
/// - only one stream at a time
/// - starting a stream will cancel the previous
/// - when seeking, assume that previous data is discarded
class AudioStreamWorker: NSObject, AudioDataStreamable {
    private let TIMEOUT = 60.0

    fileprivate let progressCallback: (_ id: ID, _ dto: StreamProgressDTO) -> Void
    // Will ony be called when the task object will no longer be active
    // Why? So upper layer knows that current streaming activity for this ID is done
    // Why? To know if we should persist the stream data assuming successful completion
    fileprivate let doneCallback: (_ id: ID, _ error: Error?) -> Bool
    private var session: URLSession!

    var HTTPHeaderFields: [String: String]?

    private var id: ID?
    private var url: URL?
    private var task: URLSessionDataTask?
    private var previousTotalBytesExpectedFromInitalData: Int64?
    private var initialDataBytesCount: Int64 = 0
    fileprivate var totalBytesExpectedForWholeFile: Int64?
    fileprivate var totalBytesExpectedForCurrentStream: Int64?
    fileprivate var totalBytesReceived: Int64 = 0
    private var corruptedBecauseOfSeek = false

    /// Init
    ///
    /// - Parameters:
    ///   - progressCallback: generic callback
    ///   - doneCallback: when finished
    required init(progressCallback: @escaping (_ id: ID, _ dto: StreamProgressDTO) -> Void, doneCallback: @escaping (_ id: ID, _ error: Error?) -> Bool) {
        self.progressCallback = progressCallback
        self.doneCallback = doneCallback
        super.init()

        let config = URLSessionConfiguration.background(withIdentifier: "SwiftAudioPlayer.stream")
        // Specifies that the phone should keep trying till it receives connection instead of dropping immediately
        if #available(iOS 11.0, tvOS 11.0, *) {
            config.waitsForConnectivity = true
        }
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil) // TODO: should we use ephemeral
    }

    func start(withID id: ID, withRemoteURL url: URL, withInitialData data: Data? = nil, andTotalBytesExpectedPreviously previousTotalBytesExpected: Int64? = nil) {
        Log.info("selfID: \(self.id ?? "none"), paramID: \(id) initialData: \(data?.count ?? 0)")

        killPreviousTaskIfNeeded()
        self.id = id
        self.url = url
        previousTotalBytesExpectedFromInitalData = previousTotalBytesExpected

        if let data = data {
            var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: TIMEOUT)
            HTTPHeaderFields?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            request.addValue("bytes=\(data.count)-", forHTTPHeaderField: "Range")
            task = session.dataTask(with: request)
            task?.taskDescription = id

            initialDataBytesCount = Int64(data.count)
            totalBytesReceived = initialDataBytesCount
            totalBytesExpectedForWholeFile = previousTotalBytesExpected

            let progress = previousTotalBytesExpected != nil ? Double(initialDataBytesCount) / Double(previousTotalBytesExpected!) : 0

            let dto = StreamProgressDTO(progress: progress, data: data, totalBytesExpected: totalBytesExpectedForWholeFile)

            progressCallback(id, dto)

            task?.resume()
        } else {
            var request = URLRequest(url: url)
            HTTPHeaderFields?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            task = session.dataTask(with: request)
            task?.taskDescription = id
            task?.resume()
        }
    }

    private func killPreviousTaskIfNeeded() {
        guard let task = task else { return }
        if task.state == .running || task.state == .suspended {
            task.cancel()
        }
        self.task = nil
        corruptedBecauseOfSeek = false
        totalBytesExpectedForWholeFile = nil
        totalBytesReceived = 0
        initialDataBytesCount = 0
    }

    func pause(withId id: ID) {
        Log.info("selfID: \(self.id ?? "none"), paramID: \(id)")
        guard self.id == id else {
            Log.error("incorrect ID for command")
            return
        }

        guard let task = task else {
            Log.error("tried to stop a non-existent task")
            return
        }

        if task.state == .running {
            task.suspend()
        } else {
            Log.monitor("tried to pause a task that's already suspended")
        }
    }

    func resume(withId id: ID) {
        Log.info("selfID: \(self.id ?? "none"), paramID: \(id)")
        guard self.id == id else {
            Log.error("incorrect ID for command")
            return
        }

        guard let task = task else {
            Log.error("tried to resume a non-existent task")
            return
        }

        if task.state == .suspended {
            task.resume()
        } else {
            Log.monitor("tried to resume a non-suspended task")
        }
    }

    func stop(withId id: ID) {
        Log.info("selfID: \(self.id ?? "none"), paramID: \(id)")
        guard self.id == id else {
            Log.warn("incorrect ID for command")
            return
        }

        guard let task = task else {
            Log.error("tried to stop a non-existent task")
            return
        }

        if task.state == .running || task.state == .suspended {
            task.cancel()
            self.task = nil
        } else {
            Log.error("stream_error tried to stop a task that's in state: \(task.state.rawValue)")
        }
    }

    func seek(withId id: ID, withByteOffset offset: UInt64) {
        Log.info("selfID: \(self.id ?? "none"), paramID: \(id), offset: \(offset)")
        guard self.id == id else {
            Log.error("incorrect ID for command")
            return
        }

        guard let url = url else {
            Log.monitor("tried to seek without having URL")
            return
        }
        stop(withId: id)
        totalBytesReceived = 0
        corruptedBecauseOfSeek = true
        progressCallback(id, StreamProgressDTO(progress: 0, data: Data(), totalBytesExpected: totalBytesExpectedForWholeFile))

        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: TIMEOUT)
        HTTPHeaderFields?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.addValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        task = session.dataTask(with: request)
        task?.resume()
    }

    func getRunningID() -> ID? {
        if let task = task, task.state == .running, let id = id {
            return id
        }
        return nil
    }
}

// MARK: - URLSessionDataDelegate

extension AudioStreamWorker: URLSessionDataDelegate {
    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Log.debug("selfID: ", id, " dataTaskID: ", dataTask.taskDescription, " dataSize: ", data.count, " expected: ", totalBytesExpectedForWholeFile, " received: ", totalBytesReceived)
        guard let id = id else {
            // FIXME: should be an error when done with testing phase
            Log.monitor("stream worker in weird state 9847467")
            return
        }

        guard task == dataTask else {
            Log.error("stream_error not the same task 638283") // Probably because of seek
            return
        }

        guard var totalBytesExpected = totalBytesExpectedForCurrentStream else {
            Log.monitor("should not be called 223r2")
            return
        }

        if totalBytesExpected <= 0 {
            totalBytesExpected = totalBytesReceived
        }

        totalBytesReceived = totalBytesReceived + Int64(data.count)
        let progress = Double(totalBytesReceived) / Double(totalBytesExpected)

        Log.debug("network streaming progress \(progress)")
        progressCallback(id, StreamProgressDTO(progress: progress, data: data, totalBytesExpected: totalBytesExpected))
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        Log.debug(dataTask.taskDescription, id, response.description)
        guard id != nil else {
            Log.monitor("stream worker in weird state 2049jg3")
            return
        }

        guard task == dataTask else {
            Log.error("stream_error not the same task 517253")
            return
        }

        Log.info("response length: \(response.expectedContentLength)")

        // the value will smaller if you seek. But we want to hold the OG total for duration calculations
        if !corruptedBecauseOfSeek {
            totalBytesExpectedForWholeFile = response.expectedContentLength + initialDataBytesCount
        }

        totalBytesExpectedForCurrentStream = response.expectedContentLength
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Log.debug(task.taskDescription, id)
        guard let id = id else {
            Log.error("stream_error stream worker in weird state 345b45")
            return
        }

        if self.task != task && self.task != nil {
            Log.error("stream_error not the same task 3901833")
            return
        }

        if let err: NSError = error as NSError? {
            if err.domain == NSURLErrorDomain && err.code == NSURLErrorCancelled {
                Log.info("cancelled downloading")
                let _ = doneCallback(id, nil)
                return
            }

            if err.domain == NSURLErrorDomain && err.code == NSURLErrorNetworkConnectionLost {
                Log.error("lost connection")
                let _ = doneCallback(id, nil)
                return
            }

            Log.monitor("\(task.currentRequest?.url?.absoluteString ?? "nil url") error: \(err.localizedDescription)")

            _ = doneCallback(id, err)
            return
        }

        let shouldSave = doneCallback(id, nil)
        if shouldSave, !corruptedBecauseOfSeek {
            // TODO: want to save file after streaming so we do not have to download again
//            guard (task.response?.suggestedFilename?.pathExtension) != nil else {
//                Log.monitor("Could not determine file type for file from id: \(task.taskDescription ?? "nil") and url: \(task.currentRequest?.url?.absoluteString ?? "nil")")
//                return
//            }

            // TODO: no longer saving streamed files
            //            FileStorage.Audio.write(id, fileExtension: fileType, data: data)
        }
    }

    func urlSession(_: URLSession, taskIsWaitingForConnectivity _: URLSessionTask) {
        // TODO: Notify to user that waiting for better connection
    }
}
