package com.ryanheise.audio_player;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;

/** AudioPlayerPlugin */
public class AudioPlayerPlugin implements MethodCallHandler {
  /** Plugin registration. */
  public static void registerWith(Registrar registrar) {
    final MethodChannel channel = new MethodChannel(registrar.messenger(), "com.ryanheise.audio_player.methods");
    channel.setMethodCallHandler(new AudioPlayerPlugin(registrar));
  }

	private Registrar registrar;

	public AudioPlayerPlugin(Registrar registrar) {
		this.registrar = registrar;
	}

  @Override
  public void onMethodCall(MethodCall call, Result result) {
		switch (call.method) {
		case "init":
			long id = (Long)call.arguments;
			new AudioPlayer(registrar, id);
			result.success(null);
			break;
		default:
			result.notImplemented();
			break;
		}
  }
}
