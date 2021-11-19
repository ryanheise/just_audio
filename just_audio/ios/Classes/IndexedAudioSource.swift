import AVFAudio
import AudioKit

class IndexedAudioSource: AudioSource {
    var duration: CMTime = .invalid
    var position: CMTime = .invalid
    var isAttached = false
    
    func load(player: AudioPlayer) throws {
        throw PluginError.runtimeError("no buffer")
    }

    override func buildSequence(sequence: inout [IndexedAudioSource], treeIndex: Int) -> Int {
        sequence.append(self)
        return treeIndex + 1
    }
}
