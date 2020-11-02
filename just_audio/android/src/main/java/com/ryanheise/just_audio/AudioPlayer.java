package com.ryanheise.just_audio;

import android.content.Context;
import android.media.audiofx.LoudnessEnhancer;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import com.google.android.exoplayer2.C;
import com.google.android.exoplayer2.ExoPlaybackException;
import com.google.android.exoplayer2.PlaybackParameters;
import com.google.android.exoplayer2.Player;
import com.google.android.exoplayer2.SimpleExoPlayer;
import com.google.android.exoplayer2.Timeline;
import com.google.android.exoplayer2.audio.AudioAttributes;
import com.google.android.exoplayer2.audio.AudioListener;
import com.google.android.exoplayer2.metadata.Metadata;
import com.google.android.exoplayer2.metadata.MetadataOutput;
import com.google.android.exoplayer2.metadata.icy.IcyHeaders;
import com.google.android.exoplayer2.metadata.icy.IcyInfo;
import com.google.android.exoplayer2.source.ClippingMediaSource;
import com.google.android.exoplayer2.source.ConcatenatingMediaSource;
import com.google.android.exoplayer2.source.LoopingMediaSource;
import com.google.android.exoplayer2.source.MediaSource;
import com.google.android.exoplayer2.source.ProgressiveMediaSource;
import com.google.android.exoplayer2.source.ShuffleOrder;
import com.google.android.exoplayer2.source.ShuffleOrder.DefaultShuffleOrder;
import com.google.android.exoplayer2.source.TrackGroup;
import com.google.android.exoplayer2.source.TrackGroupArray;
import com.google.android.exoplayer2.source.dash.DashMediaSource;
import com.google.android.exoplayer2.source.hls.HlsMediaSource;
import com.google.android.exoplayer2.trackselection.TrackSelectionArray;
import com.google.android.exoplayer2.upstream.DataSource;
import com.google.android.exoplayer2.upstream.DefaultDataSourceFactory;
import com.google.android.exoplayer2.upstream.DefaultHttpDataSource;
import com.google.android.exoplayer2.upstream.DefaultHttpDataSourceFactory;
import com.google.android.exoplayer2.util.Util;
import io.flutter.Log;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.EventChannel.EventSink;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;

public class AudioPlayer implements MethodCallHandler, Player.EventListener, AudioListener, MetadataOutput {

    static final String TAG = "AudioPlayer";

    private static Random random = new Random();

    private final Context context;
    private final MethodChannel methodChannel;
    private final EventChannel eventChannel;
    private EventSink eventSink;

    private ProcessingState processingState;
    private long bufferedPosition;
    private Long start;
    private Long end;
    private Long seekPos;
    private long initialPos;
    private Integer initialIndex;
    private Result prepareResult;
    private Result playResult;
    private Result seekResult;
    private boolean seekProcessed;
    private boolean playing;
    private Map<String, MediaSource> mediaSources = new HashMap<String, MediaSource>();
    private IcyInfo icyInfo;
    private IcyHeaders icyHeaders;
    private int errorCount;

    private SimpleExoPlayer player;
    private Integer audioSessionId;
    private MediaSource mediaSource;
    private Integer currentIndex;
    private float _speed = 1;
	private boolean _skipSilence = false;
	private boolean _volumeBoostEnabled = false;
	private int _volumeBoostGainMB = 0;
	private LoudnessEnhancer loudness;
    private Map<LoopingMediaSource, MediaSource> loopingChildren = new HashMap<>();
    private Map<LoopingMediaSource, Integer> loopingCounts = new HashMap<>();
    private final Handler handler = new Handler();
    private final Runnable bufferWatcher = new Runnable() {
        @Override
        public void run() {
            if (player == null) {
                return;
            }

            long newBufferedPosition = player.getBufferedPosition();
            if (newBufferedPosition != bufferedPosition) {
                bufferedPosition = newBufferedPosition;
                broadcastPlaybackEvent();
            }
            switch (processingState) {
            case buffering:
                handler.postDelayed(this, 200);
                break;
            case ready:
                if (playing) {
                    handler.postDelayed(this, 500);
                } else {
                    handler.postDelayed(this, 1000);
                }
                break;
            }
        }
    };

    public AudioPlayer(final Context applicationContext, final BinaryMessenger messenger, final String id) {
        this.context = applicationContext;
        methodChannel = new MethodChannel(messenger, "com.ryanheise.just_audio.methods." + id);
        methodChannel.setMethodCallHandler(this);
        eventChannel = new EventChannel(messenger, "com.ryanheise.just_audio.events." + id);
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
        processingState = ProcessingState.none;
    }

    private void startWatchingBuffer() {
        handler.removeCallbacks(bufferWatcher);
        handler.post(bufferWatcher);
    }

    @Override
    public void onAudioSessionId(int audioSessionId) {
        if (audioSessionId == C.AUDIO_SESSION_ID_UNSET) {
            this.audioSessionId = null;
        } else {
            this.audioSessionId = audioSessionId;
        }
        if(_volumeBoostEnabled) {
			setVolumeBoost(true, _volumeBoostGainMB);
		}
    }

    @Override
    public void onMetadata(Metadata metadata) {
        for (int i = 0; i < metadata.length(); i++) {
            final Metadata.Entry entry = metadata.get(i);
            if (entry instanceof IcyInfo) {
                icyInfo = (IcyInfo) entry;
                broadcastPlaybackEvent();
            }
        }
    }

    @Override
    public void onTracksChanged(TrackGroupArray trackGroups, TrackSelectionArray trackSelections) {
        for (int i = 0; i < trackGroups.length; i++) {
            TrackGroup trackGroup = trackGroups.get(i);

            for (int j = 0; j < trackGroup.length; j++) {
                Metadata metadata = trackGroup.getFormat(j).metadata;

                if (metadata != null) {
                    for (int k = 0; k < metadata.length(); k++) {
                        final Metadata.Entry entry = metadata.get(k);
                        if (entry instanceof IcyHeaders) {
                            icyHeaders = (IcyHeaders) entry;
                            broadcastPlaybackEvent();
                        }
                    }
                }
            }
        }
    }

    @Override
    public void onPositionDiscontinuity(int reason) {
        switch (reason) {
        case Player.DISCONTINUITY_REASON_PERIOD_TRANSITION:
        case Player.DISCONTINUITY_REASON_SEEK:
            onItemMayHaveChanged();
            break;
        }
    }

    @Override
    public void onTimelineChanged(Timeline timeline, int reason) {
        if (initialPos != C.TIME_UNSET || initialIndex != null) {
            player.seekTo(initialIndex, initialPos);
            initialIndex = null;
            initialPos = C.TIME_UNSET;
        }
        if (reason == Player.TIMELINE_CHANGE_REASON_DYNAMIC) {
            onItemMayHaveChanged();
        }
    }

    private void onItemMayHaveChanged() {
        Integer newIndex = player.getCurrentWindowIndex();
        if (newIndex != currentIndex) {
            currentIndex = newIndex;
        }
        broadcastPlaybackEvent();
    }

    @Override
    public void onPlayerStateChanged(boolean playWhenReady, int playbackState) {
        switch (playbackState) {
        case Player.STATE_READY:
            if (prepareResult != null) {
                transition(ProcessingState.ready);
                Map<String, Object> response = new HashMap<>();
                response.put("duration", 1000 * getDuration());
                prepareResult.success(response);
                prepareResult = null;
            } else {
                transition(ProcessingState.ready);
            }
            if (seekProcessed) {
                completeSeek();
            }
            break;
        case Player.STATE_BUFFERING:
            if (processingState != ProcessingState.buffering && processingState != ProcessingState.loading) {
                transition(ProcessingState.buffering);
                startWatchingBuffer();
            }
            break;
        case Player.STATE_ENDED:
            if (processingState != ProcessingState.completed) {
                transition(ProcessingState.completed);
            }
            if (playResult != null) {
                playResult.success(new HashMap<String, Object>());
                playResult = null;
            }
            break;
        }
    }

    @Override
    public void onPlayerError(ExoPlaybackException error) {
        switch (error.type) {
        case ExoPlaybackException.TYPE_SOURCE:
            Log.e(TAG, "TYPE_SOURCE: " + error.getSourceException().getMessage());
            break;

        case ExoPlaybackException.TYPE_RENDERER:
            Log.e(TAG, "TYPE_RENDERER: " + error.getRendererException().getMessage());
            break;

        case ExoPlaybackException.TYPE_UNEXPECTED:
            Log.e(TAG, "TYPE_UNEXPECTED: " + error.getUnexpectedException().getMessage());
            break;

        default:
            Log.e(TAG, "default: " + error.getUnexpectedException().getMessage());
        }
        sendError(String.valueOf(error.type), error.getMessage());
        errorCount++;
        if (player.hasNext() && currentIndex != null && errorCount <= 5) {
            int nextIndex = currentIndex + 1;
            player.prepare(mediaSource);
            player.seekTo(nextIndex, 0);
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
        seekResult.success(new HashMap<String, Object>());
        seekResult = null;
    }

    @Override
    public void onMethodCall(final MethodCall call, final Result result) {
        ensurePlayerInitialized();

        final Map<?, ?> request = (Map<?, ?>) call.arguments;
        try {
            switch (call.method) {
            case "load":
                Long initialPosition = getLong(request.get("initialPosition"));
                Integer initialIndex = (Integer)request.get("initialIndex");
                load(getAudioSource(request.get("audioSource")),
                        initialPosition == null ? C.TIME_UNSET : initialPosition / 1000,
                        initialIndex, result);
                break;
            case "play":
                play(result);
                break;
            case "pause":
                pause();
                result.success(new HashMap<String, Object>());
                break;
            case "setVolume":
                setVolume((float) ((double) ((Double) request.get("volume"))));
                result.success(new HashMap<String, Object>());
                break;
            case "setSpeed":
                setSpeed((float) ((double) ((Double) request.get("speed"))));
                result.success(new HashMap<String, Object>());
                break;
            case "setSkipSilence":
				setSkipSilence((Boolean) request.get("enabled"));
				result.success(null);
				break;
			case "setVolumeBoost":
				setVolumeBoost((Boolean) request.get("enabled"), (Integer) request.get("gainmB"));
				result.success(null);
				break;
            case "setLoopMode":
                setLoopMode((Integer) request.get("loopMode"));
                result.success(new HashMap<String, Object>());
                break;
            case "setShuffleMode":
                setShuffleModeEnabled((Integer) request.get("shuffleMode") == 1);
                result.success(new HashMap<String, Object>());
                break;
            case "setAutomaticallyWaitsToMinimizeStalling":
                result.success(new HashMap<String, Object>());
                break;
            case "seek":
                Long position = getLong(request.get("position"));
                Integer index = (Integer)request.get("index");
                seek(position == null ? C.TIME_UNSET : position / 1000, index, result);
                break;
            case "concatenatingInsertAll":
                concatenating(request.get("id"))
                        .addMediaSources((Integer)request.get("index"), getAudioSources(request.get("children")), handler, () -> result.success(new HashMap<String, Object>()));
                break;
            case "concatenatingRemoveRange":
                concatenating(request.get("id"))
                        .removeMediaSourceRange((Integer)request.get("startIndex"), (Integer)request.get("endIndex"), handler, () -> result.success(new HashMap<String, Object>()));
                break;
            case "concatenatingMove":
                concatenating(request.get("id"))
                        .moveMediaSource((Integer)request.get("currentIndex"), (Integer)request.get("newIndex"), handler, () -> result.success(new HashMap<String, Object>()));
                break;
            case "setAndroidAudioAttributes":
                setAudioAttributes((Integer)request.get("contentType"), (Integer)request.get("flags"), (Integer)request.get("usage"));
                result.success(new HashMap<String, Object>());
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

    // Set the shuffle order for mediaSource, with currentIndex at
    // the first position. Traverse the tree incrementing index at each
    // node.
    private int setShuffleOrder(MediaSource mediaSource, int index) {
        if (mediaSource instanceof ConcatenatingMediaSource) {
            final ConcatenatingMediaSource source = (ConcatenatingMediaSource)mediaSource;
            // Find which child is current
            Integer currentChildIndex = null;
            for (int i = 0; i < source.getSize(); i++) {
                final int indexBefore = index;
                final MediaSource child = source.getMediaSource(i);
                index = setShuffleOrder(child, index);
                // If currentIndex falls within this child, make this child come first.
                if (currentIndex >= indexBefore && currentIndex < index) {
                    currentChildIndex = i;
                }
            }
            // Shuffle so that the current child is first in the shuffle order
            source.setShuffleOrder(createShuffleOrder(source.getSize(), currentChildIndex));
        } else if (mediaSource instanceof LoopingMediaSource) {
            final LoopingMediaSource source = (LoopingMediaSource)mediaSource;
            // The ExoPlayer API doesn't provide accessors for these so we have
            // to index them ourselves.
            MediaSource child = loopingChildren.get(source);
            int count = loopingCounts.get(source);
            for (int i = 0; i < count; i++) {
                index = setShuffleOrder(child, index);
            }
        } else {
            // An actual media item takes up one spot in the playlist.
            index++;
        }
        return index;
    }

    private static int[] shuffle(int length, Integer firstIndex) {
        final int[] shuffleOrder = new int[length];
        for (int i = 0; i < length; i++) {
            final int j = random.nextInt(i + 1);
            shuffleOrder[i] = shuffleOrder[j];
            shuffleOrder[j] = i;
        }
        if (firstIndex != null) {
            for (int i = 1; i < length; i++) {
                if (shuffleOrder[i] == firstIndex) {
                    final int v = shuffleOrder[0];
                    shuffleOrder[0] = shuffleOrder[i];
                    shuffleOrder[i] = v;
                    break;
                }
            }
        }
        return shuffleOrder;
    }

    // Create a shuffle order optionally fixing the first index.
    private ShuffleOrder createShuffleOrder(int length, Integer firstIndex) {
        int[] shuffleIndices = shuffle(length, firstIndex);
        return new DefaultShuffleOrder(shuffleIndices, random.nextLong());
    }

    private ConcatenatingMediaSource concatenating(final Object index) {
        return (ConcatenatingMediaSource)mediaSources.get((String)index);
    }

    private MediaSource getAudioSource(final Object json) {
        Map<?, ?> map = (Map<?, ?>)json;
        String id = (String)map.get("id");
        MediaSource mediaSource = mediaSources.get(id);
        if (mediaSource == null) {
            mediaSource = decodeAudioSource(map);
            mediaSources.put(id, mediaSource);
        }
        return mediaSource;
    }

    private MediaSource decodeAudioSource(final Object json) {
        Map<?, ?> map = (Map<?, ?>)json;
        String id = (String)map.get("id");
        switch ((String)map.get("type")) {
        case "progressive":
            return new ProgressiveMediaSource.Factory(buildDataSourceFactory())
                    .setTag(id)
                    .createMediaSource(Uri.parse((String)map.get("uri")));
        case "dash":
            return new DashMediaSource.Factory(buildDataSourceFactory())
                    .setTag(id)
                    .createMediaSource(Uri.parse((String)map.get("uri")));
        case "hls":
            return new HlsMediaSource.Factory(buildDataSourceFactory())
                    .setTag(id)
                    .createMediaSource(Uri.parse((String)map.get("uri")));
        case "concatenating":
            MediaSource[] mediaSources = getAudioSourcesArray(map.get("children"));
            return new ConcatenatingMediaSource(
                    false, // isAtomic
                    (Boolean)map.get("useLazyPreparation"),
                    new DefaultShuffleOrder(mediaSources.length),
                    mediaSources);
        case "clipping":
            Long start = getLong(map.get("start"));
            Long end = getLong(map.get("end"));
            return new ClippingMediaSource(getAudioSource(map.get("child")),
                    start != null ? start : 0,
                    end != null ? end : C.TIME_END_OF_SOURCE);
        case "looping":
            Integer count = (Integer)map.get("count");
            MediaSource looperChild = getAudioSource(map.get("child"));
            LoopingMediaSource looper = new LoopingMediaSource(looperChild, count);
            // TODO: store both in a single map
            loopingChildren.put(looper, looperChild);
            loopingCounts.put(looper, count);
            return looper;
        default:
            throw new IllegalArgumentException("Unknown AudioSource type: " + map.get("type"));
        }
    }

    private MediaSource[] getAudioSourcesArray(final Object json) {
        List<MediaSource> mediaSources = getAudioSources(json);
        MediaSource[] mediaSourcesArray = new MediaSource[mediaSources.size()];
        mediaSources.toArray(mediaSourcesArray);
        return mediaSourcesArray;
    }

    private List<MediaSource> getAudioSources(final Object json) {
        List<Object> audioSources = (List<Object>)json;
        List<MediaSource> mediaSources = new ArrayList<MediaSource>();
        for (int i = 0 ; i < audioSources.size(); i++) {
            mediaSources.add(getAudioSource(audioSources.get(i)));
        }
        return mediaSources;
    }

    private DataSource.Factory buildDataSourceFactory() {
        String userAgent = Util.getUserAgent(context, "just_audio");
        DataSource.Factory httpDataSourceFactory = new DefaultHttpDataSourceFactory(
                userAgent,
                DefaultHttpDataSource.DEFAULT_CONNECT_TIMEOUT_MILLIS,
                DefaultHttpDataSource.DEFAULT_READ_TIMEOUT_MILLIS,
                true
        );
        return new DefaultDataSourceFactory(context, httpDataSourceFactory);
    }

    private void load(final MediaSource mediaSource, final long initialPosition, final Integer initialIndex, final Result result) {
        this.initialPos = initialPosition;
        this.initialIndex = initialIndex;
        switch (processingState) {
        case none:
            break;
        case loading:
            abortExistingConnection();
            player.stop();
            break;
        default:
            player.stop();
            break;
        }
        errorCount = 0;
        prepareResult = result;
        transition(ProcessingState.loading);
        if (player.getShuffleModeEnabled()) {
            setShuffleOrder(mediaSource, 0);
        }
        this.mediaSource = mediaSource;
        player.prepare(mediaSource);
    }

    private void ensurePlayerInitialized() {
        if (player == null) {
            player = new SimpleExoPlayer.Builder(context).build();
            player.addMetadataOutput(this);
            player.addListener(this);
            player.addAudioListener(this);
        }
    }

    private void setAudioAttributes(int contentType, int flags, int usage) {
        ensurePlayerInitialized();
        AudioAttributes.Builder builder = new AudioAttributes.Builder();
        builder.setContentType(contentType);
        builder.setFlags(flags);
        builder.setUsage(usage);
        //builder.setAllowedCapturePolicy((Integer)json.get("allowedCapturePolicy"));
        player.setAudioAttributes(builder.build());
    }

    private void broadcastPlaybackEvent() {
        final Map<String, Object> event = new HashMap<String, Object>();
        long updatePosition = getCurrentPosition();
        long duration = getDuration();
        event.put("processingState", processingState.ordinal());
        event.put("updatePosition", 1000 * updatePosition);
        event.put("updateTime", System.currentTimeMillis());
        event.put("bufferedPosition", 1000 * Math.max(updatePosition, bufferedPosition));
        event.put("icyMetadata", collectIcyMetadata());
        event.put("duration", 1000 * getDuration());
        event.put("currentIndex", currentIndex);
        event.put("androidAudioSessionId", audioSessionId);

        if (eventSink != null) {
            eventSink.success(event);
        }
    }

    private Map<String, Object> collectIcyMetadata() {
        final Map<String, Object> icyData = new HashMap<>();
        if (icyInfo != null) {
            final Map<String, String> info = new HashMap<>();
            info.put("title", icyInfo.title);
            info.put("url", icyInfo.url);
            icyData.put("info", info);
        }
        if (icyHeaders != null) {
            final Map<String, Object> headers = new HashMap<>();
            headers.put("bitrate", icyHeaders.bitrate);
            headers.put("genre", icyHeaders.genre);
            headers.put("name", icyHeaders.name);
            headers.put("metadataInterval", icyHeaders.metadataInterval);
            headers.put("url", icyHeaders.url);
            headers.put("isPublic", icyHeaders.isPublic);
            icyData.put("headers", headers);
        }
        return icyData;
    }

    private long getCurrentPosition() {
        if (processingState == ProcessingState.none || processingState == ProcessingState.loading) {
            return 0;
        } else if (seekPos != null && seekPos != C.TIME_UNSET) {
            return seekPos;
        } else {
            return player.getCurrentPosition();
        }
    }

    private long getDuration() {
        if (processingState == ProcessingState.none || processingState == ProcessingState.loading) {
            return C.TIME_UNSET;
        } else {
            return player.getDuration();
        }
    }

    private void sendError(String errorCode, String errorMsg) {
        if (prepareResult != null) {
            prepareResult.error(errorCode, errorMsg, null);
            prepareResult = null;
        }

        if (eventSink != null) {
            eventSink.error(errorCode, errorMsg, null);
        }
    }

    private void transition(final ProcessingState newState) {
        processingState = newState;
        broadcastPlaybackEvent();
    }

    private String getLowerCaseExtension(Uri uri) {
        // Until ExoPlayer provides automatic detection of media source types, we
        // rely on the file extension. When this is absent, as a temporary
        // workaround we allow the app to supply a fake extension in the URL
        // fragment. e.g.  https://somewhere.com/somestream?x=etc#.m3u8
        String fragment = uri.getFragment();
        String filename = fragment != null && fragment.contains(".") ? fragment : uri.getPath();
        return filename.replaceAll("^.*\\.", "").toLowerCase();
    }

    public void play(Result result) {
        if (player.getPlayWhenReady()) {
            result.success(new HashMap<String, Object>());
            return;
        }
        if (playResult != null) {
            playResult.success(new HashMap<String, Object>());
        }
        playResult = result;
        startWatchingBuffer();
        player.setPlayWhenReady(true);
        if (processingState == ProcessingState.completed && playResult != null) {
            playResult.success(new HashMap<String, Object>());
            playResult = null;
        }
    }

    public void pause() {
        if (!player.getPlayWhenReady()) return;
        player.setPlayWhenReady(false);
        if (playResult != null) {
            playResult.success(new HashMap<String, Object>());
            playResult = null;
        }
    }

    public void setVolume(final float volume) {
        player.setVolume(volume);
    }

    public void setSpeed(final float speed) {
        _speed = speed;
		if(_skipSilence) {
			player.setPlaybackParameters(new PlaybackParameters(_speed, 1, _skipSilence));
		} else {
			player.setPlaybackParameters(new PlaybackParameters(speed));
		}
        broadcastPlaybackEvent();
    }

    public void setSkipSilence(final boolean skipSilence) {
		_skipSilence = skipSilence;
		player.setPlaybackParameters(new PlaybackParameters(_speed, 1, skipSilence));
	}

	public void setVolumeBoost(final boolean enabled, final int gainmB) {
		if(android.os.Build.VERSION.SDK_INT >= 19 && audioSessionId != null) {
			_volumeBoostEnabled = enabled;
			_volumeBoostGainMB = gainmB;
			Log.e(TAG, "setVolumeBoost in android 2 : " + enabled);
			loudness = new LoudnessEnhancer(audioSessionId);
			loudness.setEnabled(enabled);
			loudness.setTargetGain(gainmB);
		}
	}

    public void setLoopMode(final int mode) {
        player.setRepeatMode(mode);
    }

    public void setShuffleModeEnabled(final boolean enabled) {
        if (enabled) {
            setShuffleOrder(mediaSource, 0);
        }
        player.setShuffleModeEnabled(enabled);
    }

    public void seek(final long position, final Integer index, final Result result) {
        if (processingState == ProcessingState.none || processingState == ProcessingState.loading) {
            result.success(new HashMap<String, Object>());
            return;
        }
        abortSeek();
        seekPos = position;
        seekResult = result;
        seekProcessed = false;
        int windowIndex = index != null ? index : player.getCurrentWindowIndex();
        player.seekTo(windowIndex, position);
    }

    public void dispose() {
        if (processingState == ProcessingState.loading) {
            abortExistingConnection();
        }
        mediaSources.clear();
        mediaSource = null;
        loopingChildren.clear();
        if (player != null) {
            player.release();
            player = null;
            transition(ProcessingState.none);
        }
        if(loudness != null) {
			loudness.release();
		}
        if (eventSink != null) {
            eventSink.endOfStream();
        }
    }

    private void abortSeek() {
        if (seekResult != null) {
            seekResult.success(new HashMap<String, Object>());
            seekResult = null;
            seekPos = null;
            seekProcessed = false;
        }
    }

    private void abortExistingConnection() {
        sendError("abort", "Connection aborted");
    }

    public static Long getLong(Object o) {
        return (o == null || o instanceof Long) ? (Long)o : new Long(((Integer)o).intValue());
    }

    enum ProcessingState {
        none,
        loading,
        buffering,
        ready,
        completed
    }
}
