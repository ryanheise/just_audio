import Flutter

class BetterEventChannel: NSObject, FlutterStreamHandler {
    let eventChannel: FlutterEventChannel
    var eventSink: FlutterEventSink? = nil
    
    init(name: String, messenger: FlutterBinaryMessenger) {
        eventChannel = FlutterEventChannel(name: name, binaryMessenger: messenger)
        super.init()
        eventChannel.setStreamHandler(self)
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
    
    func sendEvent(_ event: Any) {
        eventSink?(event)
    }
}
