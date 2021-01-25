package com.ryanheise.just_audio;

import android.media.audiofx.Visualizer;
import io.flutter.plugin.common.BinaryMessenger;
import java.util.HashMap;
import java.util.Map;

public class BetterVisualizer {
    private Visualizer visualizer;
    private final BetterEventChannel waveformEventChannel;
    private final BetterEventChannel fftEventChannel;
    private Integer audioSessionId;
    private int captureRate;
    private int captureSize;
    private boolean enableWaveform;
    private boolean enableFft;
    private boolean pendingStartRequest;
    private boolean hasPermission;

    public BetterVisualizer(final BinaryMessenger messenger, String id) {
        waveformEventChannel = new BetterEventChannel(messenger, "com.ryanheise.just_audio.waveform_events." + id);
        fftEventChannel = new BetterEventChannel(messenger, "com.ryanheise.just_audio.fft_events." + id);
    }

    public int getSamplingRate() {
        return visualizer.getSamplingRate();
    }

    public void setHasPermission(boolean hasPermission) {
        this.hasPermission = hasPermission;
        if (audioSessionId != null && hasPermission && pendingStartRequest) {
            start(captureRate, captureSize, enableWaveform, enableFft);
        }
    }

    public boolean hasPermission() {
        return hasPermission;
    }

    public void onAudioSessionId(Integer audioSessionId) {
        this.audioSessionId = audioSessionId;
        if (audioSessionId != null && hasPermission && pendingStartRequest) {
            start(captureRate, captureSize, enableWaveform, enableFft);
        }
    }

    public void start(Integer captureRate, Integer captureSize, final boolean enableWavefrom, final boolean enableFft) {
        if (visualizer != null) return;
        if (captureRate == null) {
            captureRate = Visualizer.getMaxCaptureRate() / 2;
        } else if (captureRate > Visualizer.getMaxCaptureRate()) {
            captureRate = Visualizer.getMaxCaptureRate();
        }
        if (captureSize == null) {
            captureSize = Visualizer.getCaptureSizeRange()[1];
        } else if (captureSize > Visualizer.getCaptureSizeRange()[1]) {
            captureSize = Visualizer.getCaptureSizeRange()[1];
        } else if (captureSize < Visualizer.getCaptureSizeRange()[0]) {
            captureSize = Visualizer.getCaptureSizeRange()[0];
        }
        this.enableWaveform = enableWaveform;
        this.enableFft = enableFft;
        this.captureRate = captureRate;
        if (audioSessionId == null || !hasPermission) {
            pendingStartRequest = true;
            return;
        }
        pendingStartRequest = false;
        visualizer = new Visualizer(audioSessionId);
        visualizer.setCaptureSize(captureSize);
        visualizer.setDataCaptureListener(new Visualizer.OnDataCaptureListener() {
            public void onWaveFormDataCapture(Visualizer visualizer, byte[] waveform, int samplingRate) {
                Map<String, Object> event = new HashMap<String, Object>();
                event.put("samplingRate", samplingRate);
                event.put("data", waveform);
                waveformEventChannel.success(event);
            }
            public void onFftDataCapture(Visualizer visualizer, byte[] fft, int samplingRate) {
                Map<String, Object> event = new HashMap<String, Object>();
                event.put("samplingRate", samplingRate);
                event.put("data", fft);
                fftEventChannel.success(event);
            }
        }, captureRate, enableWavefrom, enableFft);
        visualizer.setEnabled(true);
    }

    public void stop() {
        if (visualizer == null) return;
        visualizer.setDataCaptureListener(null, captureRate, enableWaveform, enableFft);
        visualizer.setEnabled(false);
        visualizer.release();
        visualizer = null;
    }

    public void dispose() {
        stop();
        waveformEventChannel.endOfStream();
        fftEventChannel.endOfStream();
    }
}
