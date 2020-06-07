package com.ryanheise.just_audio;

import android.content.Context;
import android.util.SparseArray;
import androidx.annotation.NonNull;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class MethodCallHandlerImpl implements MethodCallHandler {

	private final Context applicationContext;
	private final BinaryMessenger messenger;

	private final SparseArray<AudioPlayer> players = new SparseArray<>();

	public MethodCallHandlerImpl(Context applicationContext,
			BinaryMessenger messenger) {
		this.applicationContext = applicationContext;
		this.messenger = messenger;
	}

	@Override
	public void onMethodCall(MethodCall call, @NonNull Result result) {
		switch (call.method) {
			case "init": {
				String id = call.argument("id");
				players.put(Integer.parseInt(id), new AudioPlayer(applicationContext, messenger, id));
				result.success(null);
				break;
			}
			case "dispose": {
				final Integer id = call.argument("id");
				final AudioPlayer player = players.get(id);

				if (player != null) {
					player.dispose();
					players.remove(id);
				}
			}
			case "setIosCategory":
				result.success(null);
				break;
			default:
				result.notImplemented();
				break;
		}
	}

	void dispose() {
		final int size = players.size();
		for (int i = 0; i < size; i++) {
			final AudioPlayer player = players.valueAt(i);
			player.dispose();
		}

		players.clear();
	}
}
