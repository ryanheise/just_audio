import Flutter

class BetterEventChannel: NSObject, FlutterStreamHandler {
    let eventChannel: FlutterEventChannel
    var eventSink: FlutterEventSink?

    init(name: String, messenger: FlutterBinaryMessenger) {
        eventChannel = FlutterEventChannel(name: name, binaryMessenger: messenger)
        super.init()
        eventChannel.setStreamHandler(self)
    }

    func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    func sendEvent(_ event: Any) {
        eventSink?(event)
    }

    func dispose() {
        eventChannel.setStreamHandler(nil)
    }
}
