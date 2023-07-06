//
//  DownloadProgressDirector.swift
//  SwiftAudioPlayer
//
//  Created by Tanha Kabir on 2019-02-17.
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

public class DownloadProgressDirector {
    var closures: DirectorThreadSafeClosuresDeprecated<Double> = DirectorThreadSafeClosuresDeprecated()

    init(audioDataManager: AudioDataManager) {
        audioDataManager.attach { [weak self] key, progress in
            self?.closures.broadcast(key: key, payload: progress)
        }
    }

    func create() {}

    func clear() {
        closures.clear()
    }

    func attach(closure: @escaping (Key, Double) throws -> Void) -> UInt {
        return closures.attach(closure: closure)
    }

    func detach(withID id: UInt) {
        closures.detach(id: id)
    }
}
