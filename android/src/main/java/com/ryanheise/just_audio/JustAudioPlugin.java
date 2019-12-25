package com.ryanheise.just_audio;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import java.util.List;

/** JustAudioPlugin */
public class JustAudioPlugin implements MethodCallHandler {
  /** Plugin registration. */
  public static void registerWith(Registrar registrar) {
    final MethodChannel channel = new MethodChannel(registrar.messenger(), "com.ryanheise.just_audio.methods");
    channel.setMethodCallHandler(new JustAudioPlugin(registrar));
  }

	private Registrar registrar;

	public JustAudioPlugin(Registrar registrar) {
		this.registrar = registrar;
	}

  @Override
  public void onMethodCall(MethodCall call, Result result) {
		switch (call.method) {
		case "init":
			final List<?> args = (List<?>)call.arguments;
			String id = (String)args.get(0);
			new AudioPlayer(registrar, id);
			result.success(null);
			break;
		default:
			result.notImplemented();
			break;
		}
  }
}
