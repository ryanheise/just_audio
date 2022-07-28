import AVFAudio

class UriAudioSource: IndexedAudioSource {
    var uri: String
    var duration: TimeInterval? = nil
    
    init(sid: String, uri: String) {
        self.uri = uri
        
        if uri.hasPrefix("file://") {
            self.uri = String(uri[uri.index(uri.startIndex, offsetBy: 7)...])
        }
        
        super.init(sid: sid)
    }
    
    override func load(engine: AVAudioEngine, playerNode: AVAudioPlayerNode, speedControl: AVAudioUnitVarispeed, completionHandler: @escaping AVAudioPlayerNodeCompletionHandler) throws {
        let audioFile = try! AVAudioFile(forReading: URL(fileURLWithPath: uri))
        let audioFormat = audioFile.fileFormat
    
        duration = TimeInterval(Double(audioFile.length) / audioFormat.sampleRate)
        
        playerNode.scheduleFile(audioFile, at: nil, completionCallbackType: .dataPlayedBack, completionHandler: completionHandler)
    }
    
    override func getDuration() -> TimeInterval {
        return duration ?? 0
    }
}
