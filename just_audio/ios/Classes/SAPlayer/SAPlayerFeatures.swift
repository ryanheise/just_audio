//
//  SAPlayerFeature.swift
//  SwiftAudioPlayer
//
//  Created by Tanha Kabir on 3/10/21.
//

import AVFoundation
import Foundation

public extension SAPlayer {
    /**
     Special features for audio manipulation. These are examples of manipulations you can do with the player outside of this library. This is just an aggregation of community contibuted ones.

     - Note: These features assume default state of the player and `audioModifiers` meaning some expect the first audio modifier to be the default `AVAudioUnitTimePitch` that comes with the SAPlayer.
     */
    struct Features {
        /**
         Feature to skip silences in spoken word audio. The player will speed up the rate of audio playback when silence is detected.

         - Important: The first audio modifier must be the default `AVAudioUnitTimePitch` that comes with the SAPlayer for this feature to work.
         */
        public struct SkipSilences {
            static var enabled: Bool = false
            static var originalRate: Float = 1.0

            /**
             Enable feature to skip silences in spoken word audio. The player will speed up the rate of audio playback when silence is detected. This can be called at any point of audio playback.

             - Precondition: The first audio modifier must be the default `AVAudioUnitTimePitch` that comes with the SAPlayer for this feature to work.
             - Important: If you want to change the rate of the overall player while having skip silences on, please use `SAPlayer.Features.SkipSilences.setRateSafely()` to properly set the rate of the player. Any rate changes to the player will be ignored while using Skip Silences otherwise.
             */
            public static func enable(on player: SAPlayer) -> Bool {
                guard let engine = player.engine else { return false }

                Log.info("enabling skip silences feature")
                enabled = true
                originalRate = player.rate ?? 1.0
                let format = engine.mainMixerNode.outputFormat(forBus: 0)

                // look at documentation here to get an understanding of what is happening here: https://www.raywenderlich.com/5154-avaudioengine-tutorial-for-ios-getting-started#toc-anchor-005
                engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    guard let channelData = buffer.floatChannelData else {
                        return
                    }

                    let channelDataValue = channelData.pointee
                    let channelDataValueArray = stride(from: 0,
                                                       to: Int(buffer.frameLength),
                                                       by: buffer.stride).map { channelDataValue[$0] }

                    let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))

                    let avgPower = 20 * log10(rms)

                    let meterLevel = self.scaledPower(power: avgPower)
                    Log.debug("meterLevel: \(meterLevel)")
                    if meterLevel < 0.6 { // below 0.6 decibels is below audible audio
                        player.rate = originalRate + 0.5
                        Log.debug("speed up rate to \(String(describing: player.rate))")
                    } else {
                        player.rate = originalRate
                        Log.debug("slow down rate to \(String(describing: player.rate))")
                    }
                }

                return true
            }

            /**
             Disable feature to skip silences in spoken word audio. The player will speed up the rate of audio playback when silence is detected. This can be called at any point of audio playback.

             - Precondition: The first audio modifier must be the default `AVAudioUnitTimePitch` that comes with the SAPlayer for this feature to work.
             */
            public static func disable(on player: SAPlayer) -> Bool {
                guard let engine = player.engine else { return false }
                Log.info("disabling skip silences feature")
                engine.mainMixerNode.removeTap(onBus: 0)
                player.rate = originalRate
                enabled = false
                return true
            }

            /**
             Use this function to set the overall rate of the player for when skip silences is on. This ensures that the overall rate will be what is set through this function even as skip silences is on; if this function is not used then any changes asked of from the overall player while skip silences is on won't be recorded!

             - Important: The first audio modifier must be the default `AVAudioUnitTimePitch` that comes with the SAPlayer for this feature to work.
             */
            public static func setRateSafely(_ rate: Float, on player: SAPlayer) {
                originalRate = rate
                player.rate = rate
            }

            private static func scaledPower(power: Float) -> Float {
                guard power.isFinite else { return 0.0 }
                let minDb: Float = -80.0
                if power < minDb {
                    return 0.0
                } else if power >= 1.0 {
                    return 1.0
                } else {
                    return (abs(minDb) - abs(power)) / abs(minDb)
                }
            }
        }

        /**
         Feature to pause the player after a delay. This will happen regardless of if another audio clip has started.
         */
        public enum SleepTimer {
            static var timer: Timer?

            /**
             Enable feature to pause the player after a delay. This will happen regardless of if another audio clip has started.

             - Parameter afterDelay: The number of seconds to wait before pausing the audio
             */
            public static func enable(afterDelay delay: Double, on player: SAPlayer) {
                timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false, block: { _ in
                    player.pause()
                })
            }

            /**
             Disable feature to pause the player after a delay.
             */
            public static func disable() {
                timer?.invalidate()
            }
        }

        /**
         Feature to play the current playing audio on repeat until feature is disabled.
         */
        public enum Loop {
            static var enabled: Bool = false
            static var playingStatusId: UInt?

            /**
             Enable feature to play the current playing audio on loop. This will continue until the feature is disabled. And this feature works for both remote and saved audio.
             */
            public static func enable(on player: SAPlayer) {
                enabled = true

                guard playingStatusId == nil else { return }

                playingStatusId = SAPlayer.Updates.PlayingStatus(audioClockDirector: player.audioClockDirector).subscribe { status in
                    if status == .ended, enabled {
                        player.seekTo(seconds: 0.0)
                        player.play()
                    }
                }
            }

            /**
             Disable feature playing audio on loop.
             */
            public static func disable() {
                enabled = false
            }
        }
    }
}
