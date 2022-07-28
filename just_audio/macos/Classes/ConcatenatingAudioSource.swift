import AVFoundation

class ConcatenatingAudioSource: AudioSource {
    let audioSources: [AudioSource]
    let shuffleOrder: [Int]

    init(sid: String, audioSources: [AudioSource], shuffleOrder: [Int]) {
        self.audioSources = audioSources
        self.shuffleOrder = shuffleOrder
        super.init(sid: sid)
    }

    override func buildSequence() -> [IndexedAudioSource] {
        return audioSources.flatMap {
            $0.buildSequence()
        }
    }

    override func getShuffleIndices() -> [Int] {
        return shuffleOrder
    }
}
