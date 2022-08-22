

class UriAudioSource: IndexedAudioSource {
    var url: URL
    var duration: CMTime = .invalid

    init(sid: String, uri: String) {
        url = UriAudioSource.urlFrom(uri: uri)

        super.init(sid: sid)
    }

    override func load(engine _: AVAudioEngine, playerNode: AVAudioPlayerNode, speedControl _: AVAudioUnitVarispeed, position: CMTime?, completionHandler: @escaping () -> Void) throws {
        let audioFile = try! AVAudioFile(forReading: url)
        let audioFormat = audioFile.fileFormat

        duration = UriAudioSource.durationFrom(audioFile: audioFile)
        let sampleRate = audioFormat.sampleRate

        if let position = position, position.seconds > 0 {
            let framePosition = AVAudioFramePosition(sampleRate * position.seconds)

            let missingTime = duration.seconds - position.seconds
            let framesToPlay = AVAudioFrameCount(sampleRate * missingTime)

            if framesToPlay > 1000 {
                playerNode.scheduleSegment(audioFile, startingFrame: framePosition, frameCount: framesToPlay, at: nil, completionHandler: completionHandler)
            }
        } else {
            playerNode.scheduleFile(audioFile, at: nil, completionHandler: completionHandler)
        }
    }

    override func getDuration() -> CMTime {
        return duration
    }

    static func durationFrom(audioFile: AVAudioFile) -> CMTime {
        let seconds = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        return CMTime(value: Int64(seconds * 1000), timescale: 1000)
    }

    static func urlFrom(uri: String) -> URL {
        if uri.hasPrefix("ipod-library://") || uri.hasPrefix("file://") {
            return URL(string: uri)!
        } else {
            return URL(fileURLWithPath: uri)
        }
    }
}
