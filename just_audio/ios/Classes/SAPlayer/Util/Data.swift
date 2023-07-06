//
//  Data.swift
//  SwiftAudioPlayer
//
//  Created by Tanha Kabir on 2019-11-29.
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

extension Data {
    // Introduced in Swift 5, withUnsafeBytes using UnsafePointers is deprecated
    // https://mjtsai.com/blog/2019/03/27/swift-5-released/
    func accessBytes<R>(_ body: (UnsafePointer<UInt8>) throws -> R) rethrows -> R {
        return try withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) -> R in
            let unsafeBufferPointer = rawBufferPointer.bindMemory(to: UInt8.self)
            guard let unsafePointer = unsafeBufferPointer.baseAddress else {
                Log.error("")
                var int: UInt8 = 0
                return try body(&int)
            }
            return try body(unsafePointer)
        }
    }

    mutating func accessMutableBytes<R>(_ body: (UnsafeMutablePointer<UInt8>) throws -> R) rethrows -> R {
        return try withUnsafeMutableBytes { (rawBufferPointer: UnsafeMutableRawBufferPointer) -> R in
            let unsafeMutableBufferPointer = rawBufferPointer.bindMemory(to: UInt8.self)
            guard let unsafeMutablePointer = unsafeMutableBufferPointer.baseAddress else {
                Log.error("")
                var int: UInt8 = 0
                return try body(&int)
            }
            return try body(unsafeMutablePointer)
        }
    }
}
