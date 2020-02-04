package com.ryanheise.just_audio;

import android.os.Handler;
import com.google.android.exoplayer2.C;
import com.google.android.exoplayer2.Player;
import com.google.android.exoplayer2.PlaybackParameters;
import com.google.android.exoplayer2.SimpleExoPlayer;
import com.google.android.exoplayer2.source.ClippingMediaSource;
import com.google.android.exoplayer2.source.MediaSource;
import com.google.android.exoplayer2.source.ProgressiveMediaSource;
import com.google.android.exoplayer2.source.dash.DashMediaSource;
import com.google.android.exoplayer2.source.hls.HlsMediaSource;
import com.google.android.exoplayer2.upstream.DataSource;
import com.google.android.exoplayer2.upstream.DefaultDataSourceFactory;
import com.google.android.exoplayer2.util.Util;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.EventChannel.EventSink;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedList;
import android.content.Context;
import android.net.Uri;
import java.util.List;

public class AudioPlayer implements MethodCallHandler, Player.EventListener {
	private final Registrar registrar;
	private final Context context;
	private final MethodChannel methodChannel;
	private final EventChannel eventChannel;
	private EventSink eventSink;
	private final Handler handler = new Handler();
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

	private final String id;
	private volatile PlaybackState state;
	private PlaybackState stateBeforeSeek;
	private long updateTime;
	private long updatePosition;

	private long duration;
	private Long start;
	private Long end;
	private float volume = 1.0f;
	private float speed = 1.0f;
	private Long seekPos;
	private Result prepareResult;
	private Result seekResult;
	private boolean seekProcessed;
	private MediaSource mediaSource;

	private SimpleExoPlayer player;

	public AudioPlayer(final Registrar registrar, final String id) {
		this.registrar = registrar;
		this.context = registrar.activeContext();
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

		player = new SimpleExoPlayer.Builder(context).build();
		player.addListener(this);
	}

	@Override
	public void onPlayerStateChanged(boolean playWhenReady, int playbackState) {
		switch (playbackState) {
		case Player.STATE_READY:
			if (prepareResult != null) {
				duration = player.getDuration();
				prepareResult.success(duration);
				prepareResult = null;
				transition(PlaybackState.stopped);
			}
			if (seekProcessed) {
				completeSeek();
			}
			break;
		case Player.STATE_BUFFERING:
			// TODO: use this instead of checkForDiscontinuity.
			break;
		case Player.STATE_ENDED:
			if (state != PlaybackState.completed) {
				transition(PlaybackState.completed);
			}
			break;
		}
	}

	@Override
	public void onSeekProcessed() {
		if (seekResult != null) {
			seekProcessed = true;
			if (player.getPlaybackState() == Player.STATE_READY) {
				completeSeek();
			}
		}
	}

	private void completeSeek() {
		seekProcessed = false;
		seekPos = null;
		transition(stateBeforeSeek);
		seekResult.success(null);
		stateBeforeSeek = null;
		seekResult = null;
	}

	private void checkForDiscontinuity() {
		final long now = System.currentTimeMillis();
		final long position = getCurrentPosition();
		final long timeSinceLastUpdate = now - updateTime;
		final long expectedPosition = updatePosition + (long)(timeSinceLastUpdate * speed);
		final long drift = position - expectedPosition;
		// Update if we've drifted or just started observing
		if (updateTime == 0L) {
			broadcastPlaybackEvent();
		} else if (drift < -100) {
			System.out.println("time discontinuity detected: " + drift);
			transition(PlaybackState.buffering);
		} else if (state == PlaybackState.buffering) {
			transition(PlaybackState.playing);
		}
	}

	@Override
	public void onMethodCall(final MethodCall call, final Result result) {
		final List<?> args = (List<?>)call.arguments;
		try {
			switch (call.method) {
			case "setUrl":
				setUrl((String)args.get(0), result);
				break;
			case "setClip":
				Object start = args.get(0);
				if (start != null && start instanceof Integer) {
					start = new Long((Integer)start);
				}
				Object end = args.get(1);
				if (end != null && end instanceof Integer) {
					end = new Long((Integer)end);
				}
				setClip((Long)start, (Long)end, result);
				break;
			case "play":
				play();
				result.success(null);
				break;
			case "pause":
				pause();
				result.success(null);
				break;
			case "stop":
				stop(result);
				break;
			case "setVolume":
				setVolume((float)((double)((Double)args.get(0))));
				result.success(null);
				break;
			case "setSpeed":
				setSpeed((float)((double)((Double)args.get(0))));
				result.success(null);
				break;
			case "seek":
				Object position = args.get(0);
				if (position instanceof Integer) {
					seek((Integer)position, result);
				} else {
					seek((Long)position, result);
				}
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
			result.error("Illegal state: " + e.getMessage(), null, null);
		} catch (Exception e) {
			e.printStackTrace();
			result.error("Error: " + e, null, null);
		}
	}

	private void broadcastPlaybackEvent() {
		final ArrayList<Object> event = new ArrayList<Object>();
		event.add(state.ordinal());
		event.add(updatePosition = getCurrentPosition());
		event.add(updateTime = System.currentTimeMillis());
		eventSink.success(event);
	}

	private long getCurrentPosition() {
		if (state == PlaybackState.none || state == PlaybackState.connecting) {
			return 0;
		} else if (seekPos != null) {
			return seekPos;
		} else {
			return player.getCurrentPosition();
		}
	}

	private void transition(final PlaybackState newState) {
		final PlaybackState oldState = state;
		state = newState;
		if (oldState != PlaybackState.playing && newState == PlaybackState.playing) {
			startObservingPosition();
		}
		broadcastPlaybackEvent();
	}

	public void setUrl(final String url, final Result result) throws IOException {
		abortExistingConnection();
		prepareResult = result;
		transition(PlaybackState.connecting);
		DataSource.Factory dataSourceFactory = new DefaultDataSourceFactory(context, Util.getUserAgent(context, "just_audio"));
		Uri uri = Uri.parse(url);
		if (uri.getPath().toLowerCase().endsWith(".mpd")) {
			mediaSource = new DashMediaSource.Factory(dataSourceFactory).createMediaSource(uri);
		} else if (uri.getPath().toLowerCase().endsWith(".m3u8")) {
			mediaSource = new HlsMediaSource.Factory(dataSourceFactory).createMediaSource(uri);
		} else {
			mediaSource = new ProgressiveMediaSource.Factory(dataSourceFactory).createMediaSource(uri);
		}
		player.prepare(mediaSource);
	}

	public void setClip(final Long start, final Long end, final Result result) {
		if (state == PlaybackState.none) {
			throw new IllegalStateException("Cannot call setClip from none state");
		}
		abortExistingConnection();
		this.start = start;
		this.end = end;
		prepareResult = result;
		if (start != null || end != null) {
			player.prepare(new ClippingMediaSource(mediaSource,
						(start != null ? start : 0) * 1000L,
						(end != null ? end : C.TIME_END_OF_SOURCE) * 1000L));
		} else {
			player.prepare(mediaSource);
		}
	}

	public void play() {
		switch (state) {
		case playing:
			break;
		case stopped:
		case completed:
		case buffering:
		case paused:
			player.setPlayWhenReady(true);
			if (seekResult != null) {
				stateBeforeSeek = PlaybackState.playing;
			} else {
				transition(PlaybackState.playing);
			}
			break;
		default:
			throw new IllegalStateException("Cannot call play from connecting/none states (" + state + ")");
		}
	}

	public void pause() {
		switch (state) {
		case paused:
			break;
		case playing:
		case buffering:
			player.setPlayWhenReady(false);
			transition(PlaybackState.paused);
			if (seekResult != null) {
				stateBeforeSeek = PlaybackState.paused;
			}
			break;
		default:
			throw new IllegalStateException("Can call pause only from playing and buffering states (" + state + ")");
		}
	}

	public void stop(final Result result) {
		switch (state) {
		case stopped:
			result.success(null);
			break;
		case connecting:
			abortExistingConnection();
			transition(PlaybackState.stopped);
			result.success(null);
			break;
		case buffering:
			abortSeek();
			// no break
		case completed:
		case playing:
		case paused:
			player.setPlayWhenReady(false);
			player.seekTo(0L);
			transition(PlaybackState.stopped);
			result.success(null);
			break;
		default:
			throw new IllegalStateException("Cannot call stop from none state");
		}
	}

	public void setVolume(final float volume) {
		this.volume = volume;
		player.setVolume(volume);
	}

	public void setSpeed(final float speed) {
		this.speed = speed;
		player.setPlaybackParameters(new PlaybackParameters(speed));
		broadcastPlaybackEvent();
	}

	public void seek(final long position, final Result result) {
		if (state == PlaybackState.none || state == PlaybackState.connecting) {
			throw new IllegalStateException("Cannot call seek from none none/connecting states");
		}
		abortSeek();
		seekPos = position;
		seekResult = result;
		seekProcessed = false;
		if (stateBeforeSeek == null) {
			stateBeforeSeek = state;
		}
		handler.removeCallbacks(positionObserver);
		transition(PlaybackState.buffering);
		player.seekTo(position);
	}

	public void dispose() {
		player.release();
		transition(PlaybackState.none);
	}

	private void abortSeek() {
		if (seekResult != null) {
			seekResult.success(null);
			seekResult = null;
			seekPos = null;
			stateBeforeSeek = null;
			seekProcessed = false;
		}
	}

	private void abortExistingConnection() {
		if (prepareResult != null) {
			prepareResult.success(null);
			prepareResult = null;
		}
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
		connecting,
		completed
	}
}
