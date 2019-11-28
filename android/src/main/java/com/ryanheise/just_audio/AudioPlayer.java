package com.ryanheise.just_audio;

import android.media.MediaPlayer;
import android.media.MediaTimestamp;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.EventChannel.EventSink;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.util.List;
import java.io.IOException;
import android.os.Handler;
import java.util.ArrayList;
import io.flutter.plugin.common.PluginRegistry.Registrar;

public class AudioPlayer implements MethodCallHandler, MediaPlayer.OnCompletionListener {
	private final Registrar registrar;
	private final MethodChannel methodChannel;
	private final EventChannel eventChannel;
	private EventSink eventSink;
	private final Handler handler = new Handler();
	private Runnable endDetector;
	private final Runnable positionObserver = new Runnable() {
		@Override
		public void run() {
			if (state != PlaybackState.playing && state != PlaybackState.buffering)
				return;

			if (eventSink != null) {
				checkForDiscontinuity();
			}
			handler.postDelayed(this, 200);
		}
	};

	private final long id;
	private final MediaPlayer player;
	private PlaybackState state;
	private PlaybackState stateBeforeSeek;
	private long updateTime;
	private int updatePosition;
	private Integer seekPos;

	public AudioPlayer(final Registrar registrar, final long id) {
		this.registrar = registrar;
		this.id = id;
		methodChannel = new MethodChannel(registrar.messenger(), "com.ryanheise.just_audio.methods." + id);
		methodChannel.setMethodCallHandler(this);
		eventChannel = new EventChannel(registrar.messenger(), "com.ryanheise.just_audio.events." + id);
		eventChannel.setStreamHandler(new EventChannel.StreamHandler() {
			@Override
			public void onListen(final Object arguments, final EventSink eventSink) {
				AudioPlayer.this.eventSink = eventSink;
			}

			@Override
			public void onCancel(final Object arguments) {
				eventSink = null;
			}
		});
		state = PlaybackState.none;
		player = new MediaPlayer();
		player.setOnCompletionListener(this);
	}

	private void checkForDiscontinuity() {
		// TODO: Consider using player.setOnMediaTimeDiscontinuityListener()
		// when available in SDK. (Added in API level 28)
		final long now = System.currentTimeMillis();
		final int position = getCurrentPosition();
		final long timeSinceLastUpdate = now - updateTime;
		final long expectedPosition = updatePosition + timeSinceLastUpdate;
		final long drift = position - expectedPosition;
		// Update if we've drifted or just started observing
		if (updateTime == 0L) {
			broadcastPlayerState();
		} else if (drift < -100) {
			System.out.println("time discontinuity detected: " + drift);
			setPlaybackState(PlaybackState.buffering);
		} else if (state == PlaybackState.buffering) {
			setPlaybackState(PlaybackState.playing);
		}
	}

	@Override
	public void onCompletion(final MediaPlayer mp) {
		setPlaybackState(PlaybackState.stopped);
	}

	@Override
	public void onMethodCall(final MethodCall call, final Result result) {
		final List<?> args = (List<?>)call.arguments;
		try {
			switch (call.method) {
			case "setUrl":
				setUrl((String)args.get(0), result);
				break;
			case "play":
				play((Integer)args.get(0));
				result.success(null);
				break;
			case "pause":
				pause();
				result.success(null);
				break;
			case "stop":
				stop();
				result.success(null);
				break;
			case "setVolume":
				setVolume((Double)args.get(0));
				result.success(null);
				break;
			case "seek":
				seek((Integer)args.get(0), result);
				break;
			case "dispose":
				dispose();
				result.success(null);
				break;
			default:
				result.notImplemented();
				break;
			}
		} catch (IllegalStateException e) {
			e.printStackTrace();
			result.error("Illegal state", null, null);
		} catch (Exception e) {
			e.printStackTrace();
			result.error("Error", null, null);
		}
	}

	private void broadcastPlayerState() {
		final ArrayList<Object> event = new ArrayList<Object>();
		// state
		event.add(state.ordinal());
		// updatePosition
		event.add(updatePosition = getCurrentPosition());
		// updateTime
		event.add(updateTime = System.currentTimeMillis());
		eventSink.success(event);
	}

	private int getCurrentPosition() {
		if (state == PlaybackState.none || state == PlaybackState.connecting) {
			return 0;
		} else if (seekPos != null) {
			return seekPos;
		} else {
			return player.getCurrentPosition();
		}
	}

	private void setPlaybackState(final PlaybackState state) {
		final PlaybackState oldState = this.state;
		this.state = state;
		if (oldState != PlaybackState.playing && state == PlaybackState.playing) {
			startObservingPosition();
		}
		broadcastPlayerState();
	}

	public void setUrl(final String url, final Result result) throws IOException {
		setPlaybackState(PlaybackState.connecting);
		player.reset();
		player.setOnPreparedListener(new MediaPlayer.OnPreparedListener() {
			@Override
			public void onPrepared(final MediaPlayer mp) {
				setPlaybackState(PlaybackState.stopped);
				result.success(mp.getDuration());
			}
		});
		player.setDataSource(url);
		player.prepareAsync();
	}

	public void play(final Integer untilPosition) {
		// TODO: dynamically adjust the lag.
		final int lag = 6;
		final int start = getCurrentPosition();
		if (untilPosition != null && untilPosition <= start) {
			return;
		}
		player.start();
		setPlaybackState(PlaybackState.playing);
		if (endDetector != null) {
			handler.removeCallbacks(endDetector);
		}
		if (untilPosition != null) {
			final int duration = Math.max(0, untilPosition - start - lag);
			handler.postDelayed(new Runnable() {
				@Override
				public void run() {
					final int position = getCurrentPosition();
					if (position > untilPosition - 20) {
						pause();
					} else {
						final int duration = Math.max(0, untilPosition - position - lag);
						handler.postDelayed(this, duration);
					}
				}
			}, duration);
		}
	}

	public void pause() {
		player.pause();
		setPlaybackState(PlaybackState.paused);
	}

	public void stop() {
		player.pause();
		player.seekTo(0);
		setPlaybackState(PlaybackState.stopped);
	}

	public void setVolume(final double volume) {
		player.setVolume((float)volume, (float)volume);
	}

	public void seek(final int position, final Result result) {
		stateBeforeSeek = state;
		seekPos = position;
		handler.removeCallbacks(positionObserver);
		setPlaybackState(PlaybackState.buffering);
		player.setOnSeekCompleteListener(new MediaPlayer.OnSeekCompleteListener() {
			@Override
			public void onSeekComplete(final MediaPlayer mp) {
				seekPos = null;
				setPlaybackState(stateBeforeSeek);
				stateBeforeSeek = null;
				result.success(null);
				player.setOnSeekCompleteListener(null);
			}
		});
		player.seekTo(position);
	}

	public void dispose() {
		player.release();
		setPlaybackState(PlaybackState.none);
	}

	private void startObservingPosition() {
		handler.removeCallbacks(positionObserver);
		handler.post(positionObserver);
	}

	enum PlaybackState {
		none,
		stopped,
		paused,
		playing,
		buffering,
		connecting
	}
}
