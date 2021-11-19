import AVFAudio
import AudioKit

class UriAudioSource: IndexedAudioSource {
    var uri: String
    init(sid: String, uri: String) {
        self.uri = uri
        
        if uri.hasPrefix("file://") {
            self.uri = String(uri[uri.index(uri.startIndex, offsetBy: 7)...])
        }
        
        super.init(sid: sid)
    }
    
    override func load(player: AudioPlayer) throws {
        let audioFile = try! AVAudioFile(forReading: URL(fileURLWithPath: uri))
        try! player.load(file: audioFile)
    }
}
