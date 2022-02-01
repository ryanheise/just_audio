

class UriAudioSource: IndexedAudioSource {
    var url: URL
    var duration: TimeInterval = 0

    init(sid: String, uri: String) {
        self.url = UriAudioSource.urlFrom(uri: uri)

        super.init(sid: sid)
    }

    override func load(engine _: AVAudioEngine, playerNode: AVAudioPlayerNode, speedControl _: AVAudioUnitVarispeed, position: CMTime?, completionHandler: @escaping AVAudioPlayerNodeCompletionHandler) throws {

        let audioFile = try! AVAudioFile(forReading: url)
        let audioFormat = audioFile.fileFormat

        duration = TimeInterval(Double(audioFile.length) / audioFormat.sampleRate)
        let sampleRate = audioFormat.sampleRate
        
        if let position = position, position.seconds > 0 {
            
            let framePosition = AVAudioFramePosition(sampleRate * position.seconds)

            let missingTime = duration - position.seconds
            let framestoplay = AVAudioFrameCount(sampleRate * missingTime)

            if framestoplay > 1000 {
                playerNode.scheduleSegment(audioFile, startingFrame: framePosition, frameCount: framestoplay, at: nil,  completionCallbackType: .dataPlayedBack, completionHandler: completionHandler)
            }
        } else {
            playerNode.scheduleFile(audioFile, at: nil, completionCallbackType: .dataPlayedBack, completionHandler: completionHandler)
        }
    }
    
    override func getDuration() -> TimeInterval {
        return duration
    }
    
    static func urlFrom(uri: String) -> URL {
        if (uri.hasPrefix("ipod-library://")) {
            return URL(string: uri)!
        } else if (uri.hasPrefix("file://")) {
            let fineUri = String(uri[uri.index(uri.startIndex, offsetBy: 7)...])
            return URL(fileURLWithPath: fineUri);
        } else {
            return URL(fileURLWithPath: uri)
        }
    }
}
