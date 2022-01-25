

class UriAudioSource: IndexedAudioSource {
    var uri: String
    var duration: TimeInterval?
    var simpleRate: Double = 0
    var simpleTime: Int64 = 0

    init(sid: String, uri: String) {
        self.uri = uri

        if uri.hasPrefix("file://") {
            self.uri = String(uri[uri.index(uri.startIndex, offsetBy: 7)...])
        }

        super.init(sid: sid)
    }

    override func load(engine _: AVAudioEngine, playerNode: AVAudioPlayerNode, speedControl _: AVAudioUnitVarispeed, completionHandler _: @escaping AVAudioPlayerNodeCompletionHandler) throws {
        let url = uri.starts(with: "ipod-library://") ? URL(string: uri)! : URL(fileURLWithPath: uri)

        let audioFile = try! AVAudioFile(forReading: url)
        let audioFormat = audioFile.fileFormat

        simpleRate = audioFormat.sampleRate
        simpleTime = audioFile.length
        duration = TimeInterval(Double(audioFile.length) / audioFormat.sampleRate)

        playerNode.scheduleFile(audioFile, at: nil, completionHandler: { print("Hola") })
    }

    override func getSampleRate() -> Double {
        return simpleRate
    }

    override func getSampleTime() -> Int64 {
        return simpleTime
    }

    override func getDuration() -> TimeInterval {
        return duration ?? 0
    }
}
