package com.ryanheise.just_audio;

import android.content.Context;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry.Registrar;

/**
 * JustAudioPlugin
 */
public class JustAudioPlugin implements FlutterPlugin {

	private MethodChannel channel;
	private MainMethodCallHandler methodCallHandler;

	public JustAudioPlugin() {
	}

	/**
	 * v1 plugin registration.
	 */
	public static void registerWith(Registrar registrar) {
		final JustAudioPlugin plugin = new JustAudioPlugin();
		plugin.startListening(registrar.context(), registrar.messenger());
		registrar.addViewDestroyListener(
				view -> {
					plugin.stopListening();
					return false;
				});
	}

	@Override
	public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
		startListening(binding.getApplicationContext(), binding.getBinaryMessenger());
	}

	@Override
	public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
		stopListening();
	}

	private void startListening(Context applicationContext, BinaryMessenger messenger) {
		methodCallHandler = new MainMethodCallHandler(applicationContext, messenger);

		channel = new MethodChannel(messenger, "com.ryanheise.just_audio.methods");
		channel.setMethodCallHandler(methodCallHandler);
	}

	private void stopListening() {
		methodCallHandler.dispose();
		methodCallHandler = null;

		channel.setMethodCallHandler(null);
	}
}
