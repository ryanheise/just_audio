package com.ryanheise.just_audio;

import android.content.Context;
import androidx.annotation.NonNull;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.util.HashMap;
import java.util.List;
import java.util.ArrayList;
import java.util.Map;

public class MainMethodCallHandler implements MethodCallHandler {

	private final Context applicationContext;
	private final BinaryMessenger messenger;

	private final Map<String, AudioPlayer> players = new HashMap<>();

	public MainMethodCallHandler(Context applicationContext,
			BinaryMessenger messenger) {
		this.applicationContext = applicationContext;
		this.messenger = messenger;
	}

	@Override
	public void onMethodCall(MethodCall call, @NonNull Result result) {
		switch (call.method) {
		case "init":
			final List<String> ids = call.arguments();
			String id = ids.get(0);
			players.put(id, new AudioPlayer(applicationContext, messenger, id,
					() -> players.remove(id)
			));
			result.success(null);
			break;
		case "setIosCategory":
			result.success(null);
			break;
		default:
			result.notImplemented();
			break;
		}
	}

	void dispose() {
		for (AudioPlayer player : new ArrayList<AudioPlayer>(players.values())) {
			player.dispose();
		}
	}
}
