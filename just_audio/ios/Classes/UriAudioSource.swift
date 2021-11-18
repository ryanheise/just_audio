class UriAudioSource: IndexedAudioSource {
    let uri: String
    init(sid: String, uri: String) {
        self.uri = uri
        super.init(sid: sid)
    }
}
