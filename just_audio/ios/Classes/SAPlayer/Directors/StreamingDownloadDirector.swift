//
//  StreamingDownloadDirector.swift
//  SwiftAudioPlayer
//
//  Created by Tanha Kabir on 4/16/21.
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

public class StreamingDownloadDirector {
    private var currentAudioKey: Key?

    var closures: DirectorThreadSafeClosures<Double> = DirectorThreadSafeClosures()

    init() {}

    func setKey(_ key: Key) {
        currentAudioKey = key
    }

    func resetCache() {
        closures.resetCache()
    }

    func clear() {
        closures.clear()
    }

    func attach(closure: @escaping (Double) throws -> Void) -> UInt {
        return closures.attach(closure: closure)
    }

    func detach(withID id: UInt) {
        closures.detach(id: id)
    }
}

extension StreamingDownloadDirector {
    func didUpdate(_ key: Key, networkStreamProgress: Double) {
        guard key == currentAudioKey else {
            Log.debug("silence old updates")
            return
        }

        closures.broadcast(payload: networkStreamProgress)
    }
}
