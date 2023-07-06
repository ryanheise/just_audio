//
//  Date.swift
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

extension Date {
    /**
     Finds the 64-bit representation of UTC. rand() uses UTC as a seed, so using the raw UTC should be sufficient for our case.

     - Returns: A 64-bit representation of time.
     */
    static func getUTC64() -> UInt {
        // "On 32-bit platforms, UInt is the same size as UInt32, and on 64-bit platforms, UInt is the same size as UInt64."

        if #available(iOS 11.0, *) {
            return UInt(Date().timeIntervalSince1970.bitPattern)
        } else {
            let time = Date().timeIntervalSince1970.bitPattern & 0xFFFF_FFFF
            return UInt(time)
        }
    }

    /**
     - Returns: UTC in seconds.
     */
    static func getUTC() -> UTC {
        return Int(Date().timeIntervalSince1970)
    }
}
