//
//  SAPlayerPresenter.swift
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

import AVFoundation
import Foundation
import MediaPlayer

class SAPlayerPresenter {
    weak var delegate: SAPlayerDelegate?
    var shouldPlayImmediately = false // for auto-play

    var needle: Needle?
    var duration: Duration?

    private var key: String?
    private var isPlaying: SAPlayingStatus = .buffering

    private var urlKeyMap: [Key: URL] = [:]

    var durationRef: UInt = 0
    var needleRef: UInt = 0
    var playingStatusRef: UInt = 0
    var audioQueue: [SAAudioQueueItem] = []

    var audioClockDirector: AudioClockDirector
    var audioQueueDirector: AudioQueueDirector

    init(delegate: SAPlayerDelegate?, audioClockDirector: AudioClockDirector, audioQueueDirector: AudioQueueDirector) {
        self.delegate = delegate
        self.audioClockDirector = audioClockDirector
        self.audioQueueDirector = audioQueueDirector

        durationRef = audioClockDirector.attachToChangesInDuration(closure: { [weak self] duration in
            guard let self = self else { throw DirectorError.closureIsDead }

            self.delegate?.updateLockScreenPlaybackDuration(duration: duration)
            self.duration = duration

            self.delegate?.setLockScreenInfo(withMediaInfo: self.delegate?.mediaInfo, duration: duration)
        })

        needleRef = audioClockDirector.attachToChangesInNeedle(closure: { [weak self] needle in
            guard let self = self else { throw DirectorError.closureIsDead }

            self.needle = needle
            self.delegate?.updateLockScreenElapsedTime(needle: needle)
        })

        playingStatusRef = audioClockDirector.attachToChangesInPlayingStatus(closure: { [weak self] isPlaying in
            guard let self = self else { throw DirectorError.closureIsDead }

            if isPlaying == .paused, self.shouldPlayImmediately {
                self.shouldPlayImmediately = false
                self.handlePlay()
            }

            // solves bug nil == owningEngine || GetEngine() == owningEngine where too many
            // ended statuses were notified to cause 2 engines to be initialized and causes an error.
            // TODO: don't need guard
            guard isPlaying != self.isPlaying else { return }
            self.isPlaying = isPlaying

            if self.isPlaying == .ended {
                self.playNextAudioIfExists()
            }
        })
    }

    func getUrl(forKey key: Key) -> URL? {
        return urlKeyMap[key]
    }

    func addUrlToKeyMap(_ url: URL) {
        urlKeyMap[url.key] = url
    }

    func handleClear() {
        delegate?.clearEngine()
        audioClockDirector.resetCache()

        needle = nil
        duration = nil
        key = nil
        delegate?.mediaInfo = nil
        delegate?.clearLockScreenInfo()
    }

    func handlePlaySavedAudio(withSavedUrl url: URL) {
        resetCacheForNewAudio(url: url)
        delegate?.setLockScreenControls(presenter: self)
        delegate?.startAudioDownloaded(withSavedUrl: url)
    }

    func handlePlayStreamedAudio(withRemoteUrl url: URL, bitrate: SAPlayerBitrate) {
        resetCacheForNewAudio(url: url)
        delegate?.setLockScreenControls(presenter: self)
        delegate?.startAudioStreamed(withRemoteUrl: url, bitrate: bitrate)
    }

    private func resetCacheForNewAudio(url: URL) {
        key = url.key
        urlKeyMap[url.key] = url

        audioClockDirector.setKey(url.key)
        audioClockDirector.resetCache()
    }

    func handleQueueStreamedAudio(withRemoteUrl url: URL, mediaInfo: SALockScreenInfo?, bitrate: SAPlayerBitrate) {
        audioQueue.append(SAAudioQueueItem(loc: .remote, url: url, mediaInfo: mediaInfo, bitrate: bitrate))
    }

    func handleQueueSavedAudio(withSavedUrl url: URL, mediaInfo: SALockScreenInfo?) {
        audioQueue.append(SAAudioQueueItem(loc: .saved, url: url, mediaInfo: mediaInfo))
    }

    func handleRemoveFirstQueuedItem() -> URL? {
        guard audioQueue.count != 0 else { return nil }

        return audioQueue.remove(at: 0).url
    }

    func handleClearQueued() -> [URL] {
        guard audioQueue.count != 0 else { return [] }

        let urls = audioQueue.map { item in
            item.url
        }

        audioQueue = []
        return urls
    }

    func handleStopStreamingAudio() {
        delegate?.clearEngine()
        audioClockDirector.resetCache()
    }
}

// MARK: - Used by outside world including:

// SPP, lock screen, directors
extension SAPlayerPresenter {
    func handleTogglePlayingAndPausing() {
        if isPlaying == .playing {
            handlePause()
        } else if isPlaying == .paused {
            handlePlay()
        }
    }

    func handleAudioRateChanged(rate: Float) {
        delegate?.updateLockScreenChangePlaybackRate(speed: rate)
    }

    func handleScrubbingIntervalsChanged() {
        delegate?.updateLockScreenSkipIntervals()
    }
}

// MARK: - For lock screen

extension SAPlayerPresenter: LockScreenViewPresenter {
    func getIsPlaying() -> Bool {
        return isPlaying == .playing
    }

    func handlePlay() {
        delegate?.playEngine()
        delegate?.updateLockScreenPlaying()
    }

    func handlePause() {
        delegate?.pauseEngine()
        delegate?.updateLockScreenPaused()
    }

    func handleSkipBackward() {
        guard let backward = delegate?.skipBackwardSeconds else { return }
        handleSeek(toNeedle: (needle ?? 0) - backward)
    }

    func handleSkipForward() {
        guard let forward = delegate?.skipForwardSeconds else { return }
        handleSeek(toNeedle: (needle ?? 0) + forward)
    }

    func handleSeek(toNeedle needle: Needle) {
        delegate?.seekEngine(toNeedle: needle)
    }
}

// MARK: - AVAudioEngineDelegate

extension SAPlayerPresenter: AudioEngineDelegate {
    var audioModifiers: [AVAudioUnit] {
        delegate?.audioModifiers ?? []
    }

    func didError() {
        Log.monitor("We should have handled engine error")
    }
}

// MARK: - Autoplay

extension SAPlayerPresenter {
    func playNextAudioIfExists() {
        Log.info("looking foor next audio in queue to play")
        guard audioQueue.count > 0 else {
            Log.info("no queued audio")
            return
        }
        let nextAudioURL = audioQueue.removeFirst()

        Log.info("getting ready to play \(nextAudioURL)")
        audioQueueDirector.changeInQueue(url: nextAudioURL.url)

        handleClear()

        delegate?.mediaInfo = nextAudioURL.mediaInfo

        switch nextAudioURL.loc {
        case .remote:
            handlePlayStreamedAudio(withRemoteUrl: nextAudioURL.url, bitrate: nextAudioURL.bitrate)
        case .saved:
            handlePlaySavedAudio(withSavedUrl: nextAudioURL.url)
        }

        shouldPlayImmediately = true
    }
}
