package com.ryanheise.just_audio;

import android.content.Context;
import androidx.annotation.NonNull;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.util.ArrayList;
import java.util.List;

public class MethodCallHandlerImpl implements MethodCallHandler {

	private final Context applicationContext;
	private final BinaryMessenger messenger;

	private final List<AudioPlayer> players = new ArrayList<>();

	public MethodCallHandlerImpl(Context applicationContext,
			BinaryMessenger messenger) {
		this.applicationContext = applicationContext;
		this.messenger = messenger;
	}

	@Override
	public void onMethodCall(MethodCall call, @NonNull Result result) {
		switch (call.method) {
			case "init":
				final List<?> args = (List<?>) call.arguments;
				String id = (String) args.get(0);
				players.add(new AudioPlayer(applicationContext, messenger, id));
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
		for (AudioPlayer player : players) {
			player.dispose();
		}

		players.clear();
	}
}
