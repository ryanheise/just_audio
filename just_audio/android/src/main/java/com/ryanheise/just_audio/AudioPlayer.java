package com.ryanheise.just_audio;

import android.content.Context;
import android.net.Uri;
import android.os.Handler;
import com.google.android.exoplayer2.C;
import com.google.android.exoplayer2.ExoPlaybackException;
import com.google.android.exoplayer2.MediaItem;
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
import com.google.android.exoplayer2.util.MimeTypes;
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
    private boolean playing;
    private Map<String, MediaSource> mediaSources = new HashMap<String, MediaSource>();
    private IcyInfo icyInfo;
    private IcyHeaders icyHeaders;
    private int errorCount;
    private AudioAttributes pendingAudioAttributes;

    private SimpleExoPlayer player;
    private Integer audioSessionId;
    private MediaSource mediaSource;
    private Integer currentIndex;
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
    public void onAudioSessionIdChanged(int audioSessionId) {
        if (audioSessionId == C.AUDIO_SESSION_ID_UNSET) {
            this.audioSessionId = null;
        } else {
            this.audioSessionId = audioSessionId;
        }
        broadcastPlaybackEvent();
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
            int windowIndex = initialIndex != null ? initialIndex : 0;
            player.seekTo(windowIndex, initialPos);
            initialIndex = null;
            initialPos = C.TIME_UNSET;
        }
        onItemMayHaveChanged();
    }

    private void onItemMayHaveChanged() {
        Integer newIndex = player.getCurrentWindowIndex();
        if (newIndex != currentIndex) {
            currentIndex = newIndex;
        }
        broadcastPlaybackEvent();
    }

    @Override
    public void onPlaybackStateChanged(int playbackState) {
        switch (playbackState) {
        case Player.STATE_READY:
            if (prepareResult != null) {
                transition(ProcessingState.ready);
                Map<String, Object> response = new HashMap<>();
                response.put("duration", getDuration() == C.TIME_UNSET ? null : (1000 * getDuration()));
                prepareResult.success(response);
                prepareResult = null;
                if (pendingAudioAttributes != null) {
                    player.setAudioAttributes(pendingAudioAttributes, false);
                    pendingAudioAttributes = null;
                }
            } else {
                transition(ProcessingState.ready);
            }
            if (seekResult != null) {
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
            Timeline timeline = player.getCurrentTimeline();
            // This condition is due to: https://github.com/ryanheise/just_audio/pull/310
            if (nextIndex < timeline.getWindowCount()) {
                // TODO: pass in initial position here.
                player.setMediaSource(mediaSource);
                player.prepare();
                player.seekTo(nextIndex, 0);
            }
        }
    }

    private void completeSeek() {
        seekPos = null;
        seekResult.success(new HashMap<String, Object>());
        seekResult = null;
    }

    @Override
    public void onMethodCall(final MethodCall call, final Result result) {
        ensurePlayerInitialized();

        try {
            switch (call.method) {
            case "load":
                Long initialPosition = getLong(call.argument("initialPosition"));
                Integer initialIndex = call.argument("initialIndex");
                load(getAudioSource(call.argument("audioSource")),
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
                setVolume((float) ((double) ((Double) call.argument("volume"))));
                result.success(new HashMap<String, Object>());
                break;
            case "setSpeed":
                setSpeed((float) ((double) ((Double) call.argument("speed"))));
                result.success(new HashMap<String, Object>());
                break;
            case "setLoopMode":
                setLoopMode((Integer) call.argument("loopMode"));
                result.success(new HashMap<String, Object>());
                break;
            case "setShuffleMode":
                setShuffleModeEnabled((Integer) call.argument("shuffleMode") == 1);
                result.success(new HashMap<String, Object>());
                break;
            case "setShuffleOrder":
                setShuffleOrder(call.argument("audioSource"));
                result.success(new HashMap<String, Object>());
                break;
            case "setAutomaticallyWaitsToMinimizeStalling":
                result.success(new HashMap<String, Object>());
                break;
            case "seek":
                Long position = getLong(call.argument("position"));
                Integer index = call.argument("index");
                seek(position == null ? C.TIME_UNSET : position / 1000, index, result);
                break;
            case "concatenatingInsertAll":
                concatenating(call.argument("id"))
                        .addMediaSources(call.argument("index"), getAudioSources(call.argument("children")), handler, () -> result.success(new HashMap<String, Object>()));
                concatenating(call.argument("id"))
                        .setShuffleOrder(decodeShuffleOrder(call.argument("shuffleOrder")));
                break;
            case "concatenatingRemoveRange":
                concatenating(call.argument("id"))
                        .removeMediaSourceRange(call.argument("startIndex"), call.argument("endIndex"), handler, () -> result.success(new HashMap<String, Object>()));
                concatenating(call.argument("id"))
                        .setShuffleOrder(decodeShuffleOrder(call.argument("shuffleOrder")));
                break;
            case "concatenatingMove":
                concatenating(call.argument("id"))
                        .moveMediaSource(call.argument("currentIndex"), call.argument("newIndex"), handler, () -> result.success(new HashMap<String, Object>()));
                concatenating(call.argument("id"))
                        .setShuffleOrder(decodeShuffleOrder(call.argument("shuffleOrder")));
                break;
            case "setAndroidAudioAttributes":
                setAudioAttributes(call.argument("contentType"), call.argument("flags"), call.argument("usage"));
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

    private ShuffleOrder decodeShuffleOrder(List<Integer> indexList) {
        int[] shuffleIndices = new int[indexList.size()];
        for (int i = 0; i < shuffleIndices.length; i++) {
            shuffleIndices[i] = indexList.get(i);
        }
        return new DefaultShuffleOrder(shuffleIndices, random.nextLong());
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

    private void setShuffleOrder(final Object json) {
        Map<?, ?> map = (Map<?, ?>)json;
        String id = mapGet(map, "id");
        MediaSource mediaSource = mediaSources.get(id);
        if (mediaSource == null) return;
        switch ((String)mapGet(map, "type")) {
        case "concatenating":
            ConcatenatingMediaSource concatenatingMediaSource = (ConcatenatingMediaSource)mediaSource;
            concatenatingMediaSource.setShuffleOrder(decodeShuffleOrder(mapGet(map, "shuffleOrder")));
            List<Object> children = mapGet(map, "children");
            for (Object child : children) {
                setShuffleOrder(child);
            }
            break;
        case "looping":
            setShuffleOrder(mapGet(map, "child"));
            break;
        }
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
                    .createMediaSource(new MediaItem.Builder()
                            .setUri(Uri.parse((String)map.get("uri")))
                            .setTag(id)
                            .build());
        case "dash":
            return new DashMediaSource.Factory(buildDataSourceFactory())
                    .createMediaSource(new MediaItem.Builder()
                            .setUri(Uri.parse((String)map.get("uri")))
                            .setMimeType(MimeTypes.APPLICATION_MPD)
                            .setTag(id)
                            .build());
        case "hls":
            return new HlsMediaSource.Factory(buildDataSourceFactory())
                    .createMediaSource(new MediaItem.Builder()
                            .setUri(Uri.parse((String)map.get("uri")))
                            .setMimeType(MimeTypes.APPLICATION_M3U8)
                            .build());
        case "concatenating":
            MediaSource[] mediaSources = getAudioSourcesArray(map.get("children"));
            return new ConcatenatingMediaSource(
                    false, // isAtomic
                    (Boolean)map.get("useLazyPreparation"),
                    decodeShuffleOrder(mapGet(map, "shuffleOrder")),
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
            return new LoopingMediaSource(looperChild, count);
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
        if (!(json instanceof List)) throw new RuntimeException("List expected: " + json);
        List<?> audioSources = (List<?>)json;
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
        currentIndex = initialIndex != null ? initialIndex : 0;
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
        this.mediaSource = mediaSource;
        // TODO: pass in initial position here.
        player.setMediaSource(mediaSource);
        player.prepare();
    }

    private void ensurePlayerInitialized() {
        if (player == null) {
            player = new SimpleExoPlayer.Builder(context).build();
            onAudioSessionIdChanged(player.getAudioSessionId());
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
        AudioAttributes audioAttributes = builder.build();
        if (processingState == ProcessingState.loading) {
            // audio attributes should be set either before or after loading to
            // avoid an ExoPlayer glitch.
            pendingAudioAttributes = audioAttributes;
        } else {
            player.setAudioAttributes(audioAttributes, false);
        }
    }

    private void broadcastPlaybackEvent() {
        final Map<String, Object> event = new HashMap<String, Object>();
        long updatePosition = getCurrentPosition();
        Long duration = getDuration() == C.TIME_UNSET ? null : (1000 * getDuration());
        event.put("processingState", processingState.ordinal());
        event.put("updatePosition", 1000 * updatePosition);
        event.put("updateTime", System.currentTimeMillis());
        event.put("bufferedPosition", 1000 * Math.max(updatePosition, bufferedPosition));
        event.put("icyMetadata", collectIcyMetadata());
        event.put("duration", duration);
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
        if (player.getPlaybackParameters().speed != speed)
            player.setPlaybackParameters(new PlaybackParameters(speed));
        broadcastPlaybackEvent();
    }

    public void setLoopMode(final int mode) {
        player.setRepeatMode(mode);
    }

    public void setShuffleModeEnabled(final boolean enabled) {
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
        int windowIndex = index != null ? index : player.getCurrentWindowIndex();
        player.seekTo(windowIndex, position);
    }

    public void dispose() {
        if (processingState == ProcessingState.loading) {
            abortExistingConnection();
        }
        if (playResult != null) {
            playResult.success(new HashMap<String, Object>());
            playResult = null;
        }
        mediaSources.clear();
        mediaSource = null;
        if (player != null) {
            player.release();
            player = null;
            transition(ProcessingState.none);
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
        }
    }

    private void abortExistingConnection() {
        sendError("abort", "Connection aborted");
    }

    public static Long getLong(Object o) {
        return (o == null || o instanceof Long) ? (Long)o : new Long(((Integer)o).intValue());
    }

    @SuppressWarnings("unchecked")
    static <T> T mapGet(Object o, String key) {
        if (o instanceof Map) {
            return (T) ((Map<?, ?>)o).get(key);
        } else {
            return null;
        }
    }

    enum ProcessingState {
        none,
        loading,
        buffering,
        ready,
        completed
    }
}
