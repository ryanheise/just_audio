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
    
    override func load(engine: AVAudioEngine, player: AVAudioPlayerNode, completionHandler: @escaping AVAudioPlayerNodeCompletionHandler) throws {
        let audioFile = try! AVAudioFile(forReading: URL(fileURLWithPath: uri))
        let audioFormat = audioFile.processingFormat
        let audioFrameCount = UInt32(audioFile.length)
        
        let audioFileBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: audioFrameCount)!
        try! audioFile.read(into: audioFileBuffer)
        
        duration = TimeInterval(Double(audioFileBuffer.frameLength) / audioFileBuffer.format.sampleRate)
        
        engine.connect(player, to:engine.mainMixerNode, format: audioFileBuffer.format)
        
        player.scheduleBuffer(audioFileBuffer, completionCallbackType: .dataPlayedBack, completionHandler: completionHandler)
    }
    
    override func getDuration() -> TimeInterval {
        return duration ?? 0
    }
}
