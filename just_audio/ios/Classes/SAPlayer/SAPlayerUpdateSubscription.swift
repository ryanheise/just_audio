//
//  SAPlayerUpdateSubscription.swift
//  SwiftAudioPlayer
//
//  Created by Tanha Kabir on 2019-02-18.
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

public extension SAPlayer {
    /**
     Receive updates for changing values from the player, such as the duration, elapsed time of playing audio, download progress, and etc.
     */
    struct Updates {
        public let elapsedTime: ElapsedTime
        public let duration: Duration
        public let playingStatus: PlayingStatus
        public let streamingBuffer: StreamingBuffer
        public let audioDownloading: AudioDownloading
        public let audioQueue: AudioQueue

        init(player: SAPlayer) {
            elapsedTime = .init(audioClockDirector: player.audioClockDirector)
            duration = .init(audioClockDirector: player.audioClockDirector)
            playingStatus = .init(audioClockDirector: player.audioClockDirector)
            streamingBuffer = .init(audioClockDirector: player.audioClockDirector)
            audioDownloading = .init(downloadProgressDirector: player.downloadProgressDirector)
            audioQueue = .init(audioQueueDirector: player.audioQueueDirector)
        }

        /**
         Updates to changes in the timestamp/elapsed time of the current initialized audio. Aka, where the scrubber's pointer of the audio should be at.
         */
        public struct ElapsedTime {
            private var audioClockDirector: AudioClockDirector

            internal init(audioClockDirector: AudioClockDirector) {
                self.audioClockDirector = audioClockDirector
            }

            /**
             Subscribe to updates in elapsed time of the playing audio. Aka, the current timestamp of the audio.

             - Note: It's recommended to have a weak reference to a class that uses this function

             - Parameter closure: The closure that will receive the updates of the changes in time.
             - Parameter timePosition: The current time within the audio that is playing.
             - Returns: the id for the subscription in the case you would like to unsubscribe to updates for the closure.
             */
            public func subscribe(_ closure: @escaping (_ timePosition: Double) -> Void) -> UInt {
                audioClockDirector.attachToChangesInNeedle(closure: closure)
            }

            /**
             Stop recieving updates of changes in elapsed time of audio.

             - Parameter id: The closure with this id will stop receiving updates.
             */
            public func unsubscribe(_ id: UInt) {
                audioClockDirector.detachFromChangesInNeedle(withID: id)
            }
        }

        /**
         Updates to changes in the duration of the current initialized audio. Especially helpful for audio that is being streamed and can change with more data.

         - Note: If you are streaming from a source that does not have an expected size at the beginning of a stream, such as live streams, duration will be constantly updating to best known value at the time (which is the seconds buffered currently and not necessarily the actual total duration of audio).
         */
        public struct Duration {
            private var audioClockDirector: AudioClockDirector

            internal init(audioClockDirector: AudioClockDirector) {
                self.audioClockDirector = audioClockDirector
            }

            /**
             Subscribe to updates to changes in duration of the current audio initialized.

             - Note: If you are streaming from a source that does not have an expected size at the beginning of a stream, such as live streams, duration will be constantly updating to best known value at the time (which is the seconds buffered currently and not necessarily the actual total duration of audio).

             - Note: It's recommended to have a weak reference to a class that uses this function

             - Parameter closure: The closure that will receive the updates of the changes in duration.
             - Parameter duration: The duration of the current initialized audio.
             - Returns: the id for the subscription in the case you would like to unsubscribe to updates for the closure.
             */
            public func subscribe(_ closure: @escaping (_ duration: Double) -> Void) -> UInt {
                return audioClockDirector.attachToChangesInDuration(closure: closure)
            }

            /**
             Stop recieving updates of changes in duration of the current initialized audio.

             - Parameter id: The closure with this id will stop receiving updates.
             */
            public func unsubscribe(_ id: UInt) {
                audioClockDirector.detachFromChangesInDuration(withID: id)
            }
        }

        /**
         Updates to changes in the playing/paused status of the player.
         */
        public struct PlayingStatus {
            private var audioClockDirector: AudioClockDirector

            internal init(audioClockDirector: AudioClockDirector) {
                self.audioClockDirector = audioClockDirector
            }

            /**
             Subscribe to updates to changes in the playing/paused status of audio.

             - Note: It's recommended to have a weak reference to a class that uses this function

             - Parameter closure: The closure that will receive the updates of the changes in duration.
             - Parameter playingStatus: Whether the player is playing audio or paused.
             - Returns: the id for the subscription in the case you would like to unsubscribe to updates for the closure.
             */
            public func subscribe(_ closure: @escaping (_ playingStatus: SAPlayingStatus) -> Void) -> UInt {
                return audioClockDirector.attachToChangesInPlayingStatus(closure: closure)
            }

            /**
             Stop recieving updates of changes in the playing/paused status of audio.

             - Parameter id: The closure with this id will stop receiving updates.
             */
            public func unsubscribe(_ id: UInt) {
                audioClockDirector.detachFromChangesInPlayingStatus(withID: id)
            }
        }

        /**
         Updates to changes in the progress of downloading audio for streaming. Information about range of audio available and if the audio is playable. Look at `SAAudioAvailabilityRange` for more information.
         */
        public struct StreamingBuffer {
            private var audioClockDirector: AudioClockDirector

            internal init(audioClockDirector: AudioClockDirector) {
                self.audioClockDirector = audioClockDirector
            }

            /**
             Subscribe to updates to changes in the progress of downloading audio for streaming. Information about range of audio available and if the audio is playable. Look at SAAudioAvailabilityRange for more information. For progress of downloading audio that saves to the phone for playback later, look at AudioDownloading instead.

             - Note: For live streams that don't have an expected audio length from the beginning of the stream; the duration is constantly changing and equal to the total seconds buffered from the SAAudioAvailabilityRange.

             - Note: It's recommended to have a weak reference to a class that uses this function

             - Parameter closure: The closure that will receive the updates of the changes in duration.
             - Parameter buffer: Availabity of audio that has been downloaded to play.
             - Returns: the id for the subscription in the case you would like to unsubscribe to updates for the closure.
             */
            public func subscribe(_ closure: @escaping (_ buffer: SAAudioAvailabilityRange) -> Void) -> UInt {
                return audioClockDirector.attachToChangesInBufferedRange(closure: closure)
            }

            /**
             Stop recieving updates of changes in streaming progress.

             - Parameter id: The closure with this id will stop receiving updates.
             */
            public func unsubscribe(_ id: UInt) {
                audioClockDirector.detachFromChangesInBufferedRange(withID: id)
            }
        }

        /**
         Updates to changes in the progress of downloading audio in the background. This does not correspond to progress in streaming downloads, look at StreamingBuffer for streaming progress.
         */
        public struct AudioDownloading {
            private var downloadProgressDirector: DownloadProgressDirector

            init(downloadProgressDirector: DownloadProgressDirector) {
                self.downloadProgressDirector = downloadProgressDirector
            }

            /**
             Subscribe to updates to changes in the progress of downloading audio. This does not correspond to progress in streaming downloads, look at StreamingBuffer for streaming progress.

             - Note: It's recommended to have a weak reference to a class that uses this function

             - Parameter closure: The closure that will receive the updates of the changes in duration.
             - Parameter url: The corresponding remote URL for the updated download progress.
             - Parameter progress: Value from 0.0 to 1.0 indicating progress of download.
             - Returns: the id for the subscription in the case you would like to unsubscribe to updates for the closure.
             */
            public func subscribe(on player: SAPlayer, _ closure: @escaping (_ url: URL, _ progress: Double) -> Void) -> UInt {
                return downloadProgressDirector.attach(closure: { key, progress in
                    guard let url = player.getUrl(forKey: key) else { return }
                    closure(url, progress)
                })
            }

            /**
             Stop recieving updates of changes in download progress.

             - Parameter id: The closure with this id will stop receiving updates.
             */
            public func unsubscribe(_ id: UInt) {
                downloadProgressDirector.detach(withID: id)
            }
        }

        public struct AudioQueue {
            private var audioQueueDirector: AudioQueueDirector

            internal init(audioQueueDirector: AudioQueueDirector) {
                self.audioQueueDirector = audioQueueDirector
            }

            /**
             Subscribe to updates to changes in the progress of your audio queue. When streaming audio playback completes
             and continues onto the next track, the closure is invoked.
             - Note: It's recommended to have a weak reference to a class that uses this function
             - Parameter closure: The closure that will receive the updates of the changes in duration.
             - Parameter url: The corresponding remote URL for the forthcoming audio file.
             - Returns: the id for the subscription in the case you would like to unsubscribe to updates for the closure.
             */
            public func subscribe(_ closure: @escaping (_ newUrl: URL) -> Void) -> UInt {
                return audioQueueDirector.attach(closure: closure)
            }

            /**
             Stop recieving updates of changes in download progress.
             - Parameter id: The closure with this id will stop receiving updates.
             */
            public func unsubscribe(_ id: UInt) {
                audioQueueDirector.detach(withID: id)
            }
        }
    }
}
