package com.ryanheise.just_audio;

import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaTimestamp;
import android.os.Handler;
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
import java.util.Deque;
import java.util.LinkedList;
import java.util.List;
import sonic.Sonic;

public class AudioPlayer implements MethodCallHandler {
	private final Registrar registrar;
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
	private String url;
	private volatile PlaybackState state;
	private PlaybackState stateBeforeSeek;
	private long updateTime;
	private int updatePosition;
	private Deque<SeekRequest> seekRequests = new LinkedList<>();

	private MediaExtractor extractor;
	private MediaFormat format;
	private Sonic sonic;
	private int channelCount;
	private int sampleRate;
	private int duration;
	private MediaCodec codec;
	private AudioTrack audioTrack;
	private PlayThread playThread;
	private int start;
	private Integer untilPosition;
	private Object monitor = new Object();
	private float volume = 1.0f;
	private float speed = 1.0f;
	private Thread mainThread;
	private byte[] chunk;

	public AudioPlayer(final Registrar registrar, final String id) {
		mainThread = Thread.currentThread();
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
	}

	private void checkForDiscontinuity() {
		final long now = System.currentTimeMillis();
		final int position = getCurrentPosition();
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
			case "play":
				play((Integer)args.get(0));
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

	private int getCurrentPosition() {
		if (state == PlaybackState.none || state == PlaybackState.connecting) {
			return 0;
		} else if (seekRequests.size() > 0) {
			return seekRequests.peekFirst().pos;
		} else {
			return (int)(extractor.getSampleTime() / 1000);
		}
	}

	private void transition(final PlaybackState newState) {
		transition(state, newState);
	}

	private void transition(final PlaybackState oldState, final PlaybackState newState) {
		state = newState;
		if (oldState != PlaybackState.playing && newState == PlaybackState.playing) {
			startObservingPosition();
		}
		broadcastPlaybackEvent();
	}

	private void bgTransition(final PlaybackState newState) {
		bgTransition(state, newState);
	}

	private void bgTransition(final PlaybackState oldState, final PlaybackState newState) {
		// Redundant assignment which ensures the state is set
		// immediately in the background thread.
		state = newState;
		handler.post(new Runnable() {
			@Override
			public void run() {
				transition(oldState, newState);
			}
		});
	}

	public void setUrl(final String url, final Result result) throws IOException {
		if (state != PlaybackState.none && state != PlaybackState.stopped && state != PlaybackState.completed) {
			throw new IllegalStateException("Can call setUrl only from none/stopped/completed states");
		}
		transition(PlaybackState.connecting);
		this.url = url;
		if (extractor != null) {
			extractor.release();
		}
		new Thread(() -> {
			try {
				blockingInitExtractorAndCodec();

				sonic = new Sonic(sampleRate, channelCount);
				sonic.setVolume(volume);
				sonic.setSpeed(speed);

				bgTransition(PlaybackState.stopped);
				handler.post(() -> result.success(duration));
			} catch (Exception e) {
				e.printStackTrace();
				handler.post(() -> result.error("Error: " + e, null, null));
			}
		}).start();
	}

	public void play(final Integer untilPosition) {
		if (untilPosition != null && untilPosition <= start) {
			throw new IllegalArgumentException("untilPosition must be >= 0");
		}
		this.untilPosition = untilPosition;
		switch (state) {
		case stopped:
		case completed:
			ensureStopped();
			transition(PlaybackState.playing);
			playThread = new PlayThread();
			playThread.start();
			break;
		case paused:
			synchronized (monitor) {
				transition(PlaybackState.playing);
				monitor.notifyAll();
			}
			break;
		default:
			throw new IllegalStateException("Can call play only from stopped, completed and paused states (" + state + ")");
		}
	}

	private void ensureStopped() {
		synchronized (monitor) {
			try {
				while (playThread != null) {
					monitor.wait();
				}
			} catch (Exception e) {}
		}
	}

	public void pause() {
		switch (state) {
		case playing:
		case buffering:
			synchronized (monitor) {
				transition(PlaybackState.paused);
				audioTrack.pause();
				monitor.notifyAll();
			}
			break;
		default:
			throw new IllegalStateException("Can call pause only from playing and buffering states");
		}
	}

	public void stop(final Result result) {
		switch (state) {
		case stopped:
			break;
		case completed:
			transition(PlaybackState.stopped);
			break;
		// TODO: Allow stopping from buffered state.
		case playing:
		case paused:
			synchronized (monitor) {
				// It takes some time for the PlayThread to actually wind down
				// so other methods that transition from the stopped state should
				// wait for playThread == null with ensureStopped().
				PlaybackState oldState = state;
				transition(PlaybackState.stopped);
				if (oldState == PlaybackState.paused) {
					monitor.notifyAll();
				} else {
					audioTrack.pause();
				}
				new Thread(() -> {
					ensureStopped();
					handler.post(() -> result.success(null));
				}).start();
			}
			break;
		default:
			throw new IllegalStateException("Can call stop only from playing, paused and buffering states");
		}
	}

	public void setVolume(final float volume) {
		this.volume = volume;
		if (sonic != null) {
			sonic.setVolume(volume);
		}
	}

	public void setSpeed(final float speed) {
		// NOTE: existing audio data in the pipeline will continue
		// to play out at the speed it was already processed at. So
		// for a brief moment, checkForDiscontinuity() may erroneously
		// detect some buffering.
		// TODO: Sort this out. The cheap workaround would be to disable
		// checks for discontinuity during this brief moment.
		this.speed = speed;
		if (sonic != null) {
			sonic.setSpeed(speed);
		}
		broadcastPlaybackEvent();
	}

	// TODO: Test whether this times out the MediaCodec on Ogg files.
	// See: https://stackoverflow.com/questions/22109050/mediacodec-dequeueoutputbuffer-times-out-when-seeking-with-ogg-audio-files
	public void seek(final int position, final Result result) {
		synchronized (monitor) {
			if (state == PlaybackState.none || state == PlaybackState.connecting) {
				throw new IllegalStateException("Cannot call seek in none or connecting states");
			}
			if (state == PlaybackState.stopped) {
				ensureStopped();
			}
			start = position;
			if (seekRequests.size() == 0) {
				stateBeforeSeek = state;
			}
			seekRequests.addLast(new SeekRequest(position, result));
			handler.removeCallbacks(positionObserver);
			transition(PlaybackState.buffering);
			if (stateBeforeSeek == PlaybackState.stopped) {
				new Thread(() -> {
					processSeekRequests();
				}).start();
			} else {
				monitor.notifyAll();
			}
		}
	}

	public void dispose() {
		if (state != PlaybackState.stopped && state != PlaybackState.completed && state != PlaybackState.none) {
			throw new IllegalStateException("Can call dispose only from stopped/completed/none states");
		}
		if (extractor != null) {
			ensureStopped();
			transition(PlaybackState.none);
			extractor.release();
			extractor = null;
			codec.stop();
			codec.release();
			codec = null;
			chunk = null;
		}
	}

	private void blockingInitExtractorAndCodec() throws IOException {
		extractor = new MediaExtractor();
		extractor.setDataSource(url);
		format = selectAudioTrack(extractor);
		channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
		sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE);
		long durationMs = format.getLong(MediaFormat.KEY_DURATION);
		duration = (int)(durationMs / 1000);
		start = 0;
		codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME));
		codec.configure(format, null, null, 0);
		codec.start();
	}

	private MediaFormat selectAudioTrack(MediaExtractor extractor) throws IOException {
		int trackCount = extractor.getTrackCount();
		for (int i = 0; i < trackCount; i++) {
			MediaFormat format = extractor.getTrackFormat(i);
			if (format.getString(MediaFormat.KEY_MIME).startsWith("audio/")) {
				extractor.selectTrack(i);
				return format;
			}
		}
		throw new RuntimeException("No audio track found");
	}

	private void processSeekRequests() {
		while (seekRequests.size() > 0) {
			SeekRequest seekRequest = seekRequests.removeFirst();
			extractor.seekTo(seekRequest.pos*1000L, MediaExtractor.SEEK_TO_CLOSEST_SYNC);
			if (seekRequests.size() == 0) {
				bgTransition(stateBeforeSeek);
				stateBeforeSeek = null;
			}
			handler.post(() -> seekRequest.result.success(null));
		}
	}

	private void startObservingPosition() {
		handler.removeCallbacks(positionObserver);
		handler.post(positionObserver);
	}

	private class PlayThread extends Thread {
		private static final int TIMEOUT = 1000;
		private static final int FRAME_SIZE = 1024*2;
		private static final int BEHIND_LIMIT = 500; // ms
		private byte[] silence;
		private boolean finishedDecoding = false;

		@Override
		public void run() {
			boolean reachedEnd = false;
			int encoding = AudioFormat.ENCODING_PCM_16BIT;
			int channelFormat = channelCount==1?AudioFormat.CHANNEL_OUT_MONO:AudioFormat.CHANNEL_OUT_STEREO;
			int minSize = AudioTrack.getMinBufferSize(sampleRate, channelFormat, encoding);
			int audioTrackBufferSize = minSize * 4;
			audioTrack = new AudioTrack(
					AudioManager.STREAM_MUSIC,
					sampleRate,
					channelFormat,
					encoding,
					audioTrackBufferSize,
					AudioTrack.MODE_STREAM);

			silence = new byte[audioTrackBufferSize];

			MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
			boolean firstSample = true;
			int decoderIdleCount = 0;
			boolean finishedReading = false;
			int progress = 0;
			byte[] sonicOut = new byte[audioTrackBufferSize];
			try {
				audioTrack.play();
				while (!finishedDecoding) {

					if (checkForRequest()) continue;

					// put data into input buffer

					if (!finishedReading) {
						int inputBufferIndex = codec.dequeueInputBuffer(TIMEOUT);
						if (inputBufferIndex >= 0) {
							ByteBuffer inputBuffer = codec.getInputBuffer(inputBufferIndex);
							long presentationTime = extractor.getSampleTime();
							int presentationTimeMs = (int)(presentationTime / 1000);
							int sampleSize = extractor.readSampleData(inputBuffer, 0);
							if (firstSample && sampleSize == 2 && format.getString(MediaFormat.KEY_MIME).equals("audio/mp4a-latm")) {
								// Skip initial frames.
								extractor.advance();
							} else if (sampleSize >= 0) {
								codec.queueInputBuffer(inputBufferIndex, 0, sampleSize, presentationTime, 0);
								extractor.advance();
							} else {
								codec.queueInputBuffer(inputBufferIndex, 0, 0, -1, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
								finishedReading = true;
							}
							firstSample = false;
						}
					}

					if (checkForRequest()) continue;

					// read data from output buffer

					int outputBufferIndex = codec.dequeueOutputBuffer(info, TIMEOUT);
					decoderIdleCount++;
					if (outputBufferIndex >= 0) {
						int currentPosition = (int)(info.presentationTimeUs/1000);
						ByteBuffer buf = codec.getOutputBuffer(outputBufferIndex);
						if (info.size > 0) {
							decoderIdleCount = 0;

							if (chunk == null || chunk.length < info.size) {
								chunk = new byte[info.size];
							}
							buf.get(chunk, 0, info.size);
							buf.clear();

							// put decoded data into sonic

							if (chunk.length > 0) {
								sonic.writeBytesToStream(chunk, chunk.length);
							} else {
								sonic.flushStream();
							}

							// output sonic'd data to audioTrack

							int numWritten;
							do {
								numWritten = sonic.readBytesFromStream(sonicOut, sonicOut.length);
								if (numWritten > 0) {
									audioTrack.write(sonicOut, 0, numWritten);
								}
							} while (numWritten > 0);
						}

						// Detect end of playback

						codec.releaseOutputBuffer(outputBufferIndex, false);
						if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
							if (untilPosition != null) {
								extractor.release();
								codec.flush();
								codec.stop();
								codec.release();
								blockingInitExtractorAndCodec();
								finishedReading = false;
								finishedDecoding = false;
								decoderIdleCount = 0;
								audioTrack.pause();
								bgTransition(PlaybackState.paused);
							} else {
								audioTrack.pause();
								finishedDecoding = true;
								reachedEnd = true;
							}
						} else if (untilPosition != null && currentPosition >= untilPosition) {
							// NOTE: When streaming audio over bluetooth, it clips off
							// the last 200-300ms of the clip, even though it has been
							// written to the AudioTrack. So, we need an option to pad the
							// audio with an extra 200-300ms of silence.
							// Could be a good idea to do the same at the start
							// since some bluetooth headphones fade in and miss the
							// first little bit.

							Arrays.fill(sonicOut, (byte)0);
							audioTrack.write(sonicOut, 0, sonicOut.length);
							bgTransition(PlaybackState.paused);
							audioTrack.pause();
						}
					} else if (outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
						// Don't expect this to happen in audio files, but could be wrong.
						// TODO: Investigate.
						//MediaFormat newFormat = codec.getOutputFormat();
					}
					if (decoderIdleCount >= 100) {
						// Data has stopped coming through the pipeline despite not receiving a
						// BUFFER_FLAG_END_OF_STREAM signal, so stop.
						System.out.println("decoderIdleCount >= 100. finishedDecoding = true");
						finishedDecoding = true;
						audioTrack.pause();
					}
				}
			} catch (IOException e) {
				e.printStackTrace();
			} finally {
				codec.flush();
				audioTrack.flush();
				audioTrack.release();
				audioTrack = null;
				synchronized (monitor) {
					start = 0;
					untilPosition = null;
					bgTransition(reachedEnd ? PlaybackState.completed : PlaybackState.stopped);
					extractor.seekTo(0L, MediaExtractor.SEEK_TO_CLOSEST_SYNC);
					handler.post(() -> broadcastPlaybackEvent());
					playThread = null;
					monitor.notifyAll();
				}
			}
		}

		// Return true to "continue" to the audio loop
		private boolean checkForRequest() {
			try {
				synchronized (monitor) {
					if (state == PlaybackState.paused) {
						while (state == PlaybackState.paused) {
							monitor.wait();
						}
						// Unpaused
						// Reset updateTime for higher accuracy.
						bgTransition(state);
						if (state == PlaybackState.playing) {
							audioTrack.play();
						} else if (state == PlaybackState.buffering) {
							// TODO: What if we are in the second checkForRequest call and
							// we ask to continue the loop, we may forget about dequeued
							// input buffers. Need to handle this correctly.
							return true;
						}
					} else if (state == PlaybackState.buffering && seekRequests.size() > 0) {
						// Seek requested
						codec.flush();
						audioTrack.flush();
						processSeekRequests();
						if (state != PlaybackState.stopped) {
							// The == stopped case is handled below.
							return true;
						}
					}
					if (state == PlaybackState.stopped) {
						finishedDecoding = true;
						return true;
					}
				}
			}
			catch (Exception e) {}
			return false;
		}
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

	class SeekRequest {
		public final int pos;
		public final Result result;

		public SeekRequest(int pos, Result result) {
			this.pos = pos;
			this.result = result;
		}
	}
}
