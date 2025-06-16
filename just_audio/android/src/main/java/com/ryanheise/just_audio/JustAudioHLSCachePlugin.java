package com.ryanheise.just_audio;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class JustAudioHLSCachePlugin implements FlutterPlugin, MethodCallHandler {
    private static final String TAG = "JustAudioHLSCache";
    private static final String CHANNEL = "just_audio_hls_cache";

    private MethodChannel channel;
    private Context context;
    private JustAudioHLSDownloadManager downloadManager;
    private Handler mainHandler;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
        context = flutterPluginBinding.getApplicationContext();
        downloadManager = JustAudioHLSDownloadManager.getInstance(context);
        mainHandler = new Handler(Looper.getMainLooper());
        Log.d(TAG, "HLS Cache Plugin attached to engine");
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "downloadHLS":
                downloadHLS(call, result);
                break;
            case "isHLSDownloaded":
                isHLSDownloaded(call, result);
                break;
            case "getHLSDownloadProgress":
                getHLSDownloadProgress(call, result);
                break;
            case "deleteHLSDownload":
                deleteHLSDownload(call, result);
                break;
            case "cancelHLSDownload":
                cancelHLSDownload(call, result);
                break;
            case "listDownloads":
                listDownloads(result);
                break;
            case "clearAllDownloads":
                clearAllDownloads(result);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private void downloadHLS(MethodCall call, Result result) {
        String url = call.argument("url");
        Map<String, String> headers = call.argument("headers");

        if (url == null) {
            result.error("INVALID_ARGUMENT", "URL cannot be null", null);
            return;
        }

        if (headers == null) {
            headers = new HashMap<>();
        }
        Log.d(TAG, "Starting HLS download for: " + url);

        downloadManager.downloadHLS(url, headers, new DownloadProgressCallback() {
            @Override
            public void onProgress(double progress, String error) {
                mainHandler.post(() -> {
                    if (error != null) {
                        Map<String, Object> response = new HashMap<>();
                        response.put("success", false);
                        response.put("error", error);
                        result.success(response);
                    } else if (progress >= 1.0) {
                        Map<String, Object> response = new HashMap<>();
                        response.put("success", true);
                        result.success(response);
                    }
                });
            }
        });
    }

    private void isHLSDownloaded(MethodCall call, Result result) {
        String url = call.argument("url");

        if (url == null) {
            Map<String, Object> response = new HashMap<>();
            response.put("isDownloaded", false);
            result.success(response);
            return;
        }

        boolean isDownloaded = downloadManager.isHLSDownloaded(url);
        Map<String, Object> response = new HashMap<>();
        response.put("isDownloaded", isDownloaded);
        result.success(response);
    }

    private void getHLSDownloadProgress(MethodCall call, Result result) {
        String url = call.argument("url");

        if (url == null) {
            Map<String, Object> response = new HashMap<>();
            response.put("progress", 0.0);
            result.success(response);
            return;
        }

        double progress = downloadManager.getHLSDownloadProgress(url);
        Map<String, Object> response = new HashMap<>();
        response.put("progress", progress);
        result.success(response);
    }

    private void deleteHLSDownload(MethodCall call, Result result) {
        String url = call.argument("url");

        if (url == null) {
            Map<String, Object> response = new HashMap<>();
            response.put("deleted", false);
            result.success(response);
            return;
        }

        boolean deleted = downloadManager.deleteHLSDownload(url);
        Map<String, Object> response = new HashMap<>();
        response.put("deleted", deleted);
        result.success(response);
    }

    private void cancelHLSDownload(MethodCall call, Result result) {
        String url = call.argument("url");

        if (url == null) {
            Map<String, Object> response = new HashMap<>();
            response.put("cancelled", false);
            result.success(response);
            return;
        }

        downloadManager.cancelHLSDownload(url);
        Map<String, Object> response = new HashMap<>();
        response.put("cancelled", true);
        result.success(response);
    }

    private void listDownloads(Result result) {
        List<Map<String, Object>> downloads = downloadManager.getAllHLSDownloads();
        Map<String, Object> downloadMap = new HashMap<>();

        for (Map<String, Object> download : downloads) {
            String url = (String) download.get("url");
            if (url != null) {
                downloadMap.put(url, download);
            }
        }

        Map<String, Object> response = new HashMap<>();
        response.put("downloads", downloadMap);
        result.success(response);
    }

    private void clearAllDownloads(Result result) {
        downloadManager.clearAllDownloads();
        Map<String, Object> response = new HashMap<>();
        response.put("cleared", true);
        result.success(response);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        Log.d(TAG, "HLS Cache Plugin detached from engine");
    }

    public interface DownloadProgressCallback {
        void onProgress(double progress, String error);
    }
}
