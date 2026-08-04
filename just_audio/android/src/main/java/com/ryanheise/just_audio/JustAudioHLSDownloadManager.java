package com.ryanheise.just_audio;

import android.content.Context;
import android.net.Uri;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import androidx.media3.common.C;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.util.Util;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.datasource.HttpDataSource;
import androidx.media3.datasource.cache.NoOpCacheEvictor;
import androidx.media3.datasource.cache.SimpleCache;
import androidx.media3.database.StandaloneDatabaseProvider;
import androidx.media3.exoplayer.offline.Download;
import androidx.media3.exoplayer.offline.DownloadCursor;
import androidx.media3.exoplayer.offline.DownloadIndex;
import androidx.media3.exoplayer.offline.DownloadManager;
import androidx.media3.exoplayer.offline.DownloadRequest;
import androidx.media3.exoplayer.scheduler.Requirements;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.datasource.cache.CacheDataSource;
import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executor;
import java.util.concurrent.Executors;

/**
 * Android HLS Download Manager using ExoPlayer's DownloadManager
 */
public class JustAudioHLSDownloadManager {
    private static final String TAG = "JustAudioHLSDownloadManager";
    private static final String DOWNLOAD_CONTENT_DIRECTORY = "just_audio_hls_downloads";

    private static volatile JustAudioHLSDownloadManager INSTANCE;

    private final Context context;
    private DownloadManager downloadManager;
    private SimpleCache downloadCache;
    private final Map<String, JustAudioHLSCachePlugin.DownloadProgressCallback> downloadCallbacks = new ConcurrentHashMap<>();
    private final Executor progressMonitorExecutor = Executors.newSingleThreadExecutor();

    private JustAudioHLSDownloadManager(Context context) {
        this.context = context.getApplicationContext();
        initialize();
    }

    public static JustAudioHLSDownloadManager getInstance(Context context) {
        if (INSTANCE == null) {
            synchronized (JustAudioHLSDownloadManager.class) {
                if (INSTANCE == null) {
                    INSTANCE = new JustAudioHLSDownloadManager(context);
                }
            }
        }
        return INSTANCE;
    }

    private void initialize() {
        try {
            Log.d(TAG, "Initializing HLS Download Manager...");

            File downloadDirectory = new File(context.getCacheDir(), DOWNLOAD_CONTENT_DIRECTORY);
            if (!downloadDirectory.exists()) {
                downloadDirectory.mkdirs();
            }

            downloadCache = new SimpleCache(
                    downloadDirectory,
                    new NoOpCacheEvictor(),
                    new StandaloneDatabaseProvider(context));

            Requirements requirements = new Requirements(Requirements.NETWORK);

            downloadManager = new DownloadManager(
                    context,
                    new StandaloneDatabaseProvider(context),
                    downloadCache,
                    createHttpDataSourceFactory(),
                    Runnable::run);

            downloadManager.setRequirements(requirements);
            downloadManager.setMaxParallelDownloads(2);
            downloadManager.setMinRetryCount(3);

            downloadManager.addListener(new DownloadManager.Listener() {
                @Override
                public void onDownloadChanged(
                        @NonNull DownloadManager downloadManager,
                        @NonNull Download download,
                        @Nullable Exception finalException) {
                    String url = download.request.uri.toString();
                    Log.d(TAG, "Download state changed: " + url + " -> " + getDownloadStateString(download.state));

                    JustAudioHLSCachePlugin.DownloadProgressCallback callback = downloadCallbacks.get(url);
                    if (callback != null) {
                        if (finalException != null) {
                            Log.e(TAG, "Download exception for " + url, finalException);
                            callback.onProgress(0.0, finalException.getMessage());
                            downloadCallbacks.remove(url);
                        } else if (download.state == Download.STATE_COMPLETED) {
                            Log.d(TAG, "Download completed for " + url);
                            callback.onProgress(1.0, null);
                            downloadCallbacks.remove(url);
                        } else if (download.state == Download.STATE_FAILED) {
                            String error = "Download failed with error code: " + download.failureReason;
                            Log.e(TAG, error);
                            callback.onProgress(0.0, error);
                            downloadCallbacks.remove(url);
                        }
                    }
                }

                @Override
                public void onDownloadRemoved(
                        @NonNull DownloadManager downloadManager,
                        @NonNull Download download) {
                    Log.d(TAG, "Download removed: " + download.request.uri.toString());
                }
            });

            downloadManager.resumeDownloads();

            Log.d(TAG, "HLS Download Manager initialized successfully");
        } catch (Exception e) {
            Log.e(TAG, "Failed to initialize HLS Download Manager", e);
        }
    }

    public DataSource.Factory getCacheDataSourceFactory(Map<?, ?> headers) {
        DefaultHttpDataSource.Factory httpDataSourceFactory = new DefaultHttpDataSource.Factory()
                .setUserAgent(Util.getUserAgent(context, "just_audio"))
                .setAllowCrossProtocolRedirects(true);

        if (headers != null) {
            Map<String, String> stringHeaders = new HashMap<>();
            for (Object key : headers.keySet()) {
                stringHeaders.put((String) key, (String) headers.get(key));
            }
            if (!stringHeaders.isEmpty()) {
                httpDataSourceFactory.setDefaultRequestProperties(stringHeaders);
            }
        }
        DefaultDataSource.Factory upstreamFactory = new DefaultDataSource.Factory(context, httpDataSourceFactory);

        return new CacheDataSource.Factory()
                .setCache(downloadCache)
                .setUpstreamDataSourceFactory(upstreamFactory)
                .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR);
    }

    private HttpDataSource.Factory createHttpDataSourceFactory() {
        return new DefaultHttpDataSource.Factory()
                .setUserAgent(Util.getUserAgent(context, "JustAudio"))
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(DefaultHttpDataSource.DEFAULT_CONNECT_TIMEOUT_MILLIS)
                .setReadTimeoutMs(DefaultHttpDataSource.DEFAULT_READ_TIMEOUT_MILLIS);
    }

    /**
     * Start HLS download for the given URL
     */
    public void downloadHLS(
            String url,
            Map<String, String> headers,
            JustAudioHLSCachePlugin.DownloadProgressCallback callback) {
        try {
            Log.d(TAG, "Starting HLS download for URL: " + url);

            if (downloadManager == null) {
                callback.onProgress(0.0, "Download manager not initialized");
                return;
            }
            Uri uri = Uri.parse(url);
            String downloadId = url;
            Download existingDownload = null;

            try {
                existingDownload = downloadManager.getDownloadIndex().getDownload(downloadId);
            } catch (IOException e) {
                Log.w(TAG, "Failed to check existing download", e);
            }

            if (existingDownload != null) {
                Log.w(TAG, "Download already exists with state: " + getDownloadStateString(existingDownload.state));
                switch (existingDownload.state) {
                    case Download.STATE_COMPLETED:
                        Log.d(TAG, "Download already completed");
                        callback.onProgress(1.0, null);
                        return;
                    case Download.STATE_DOWNLOADING:
                    case Download.STATE_QUEUED:
                        Log.d(TAG, "Download already in progress, monitoring existing download");
                        downloadCallbacks.put(url, callback);
                        startProgressMonitoring(url, callback);
                        return;
                    case Download.STATE_FAILED:
                        Log.w(TAG, "Removing failed download and starting fresh");
                        downloadManager.removeDownload(downloadId);
                        break;
                }
            }
            String mimeType;

            if (url.contains(".m3u8") || url.toLowerCase().contains("hls")) {
                mimeType = MimeTypes.APPLICATION_M3U8;
            } else {
                Log.w(TAG, "URL doesn't appear to be HLS, but proceeding with HLS MIME type");
                mimeType = MimeTypes.APPLICATION_M3U8;
            }
            DownloadRequest downloadRequest = new DownloadRequest.Builder(downloadId, uri)
                    .setMimeType(mimeType)
                    .build();

            Log.d(TAG, "Created download request: ID=" + downloadRequest.id + ", URI=" + downloadRequest.uri
                    + ", MimeType=" + mimeType);

            downloadCallbacks.put(url, callback);
            downloadManager.addDownload(downloadRequest);

            startProgressMonitoring(url, callback);

            Log.d(TAG, "Started HLS download for: " + url);
        } catch (Exception e) {
            Log.e(TAG, "Failed to start HLS download for URL: " + url, e);
            callback.onProgress(0.0, "Failed to start download: " + e.getMessage());
        }
    }

    private void startProgressMonitoring(String url, JustAudioHLSCachePlugin.DownloadProgressCallback callback) {
        progressMonitorExecutor.execute(() -> {
            String downloadId = url;
            int checkCount = 0;

            while (checkCount < 120 && downloadCallbacks.containsKey(url)) {
                try {
                    checkCount++;
                    Download download = downloadManager.getDownloadIndex().getDownload(downloadId);

                    if (download == null) {
                        if (checkCount > 10) {
                            Log.w(TAG, "Download not found after multiple attempts");
                            callback.onProgress(0.0, "Download not found");
                            downloadCallbacks.remove(url);
                            break;
                        }
                    } else {
                        double progress = getDownloadProgressForDownload(download);
                        // Only call callback for intermediate progress, completion is handled by
                        // listener
                        if (download.state == Download.STATE_DOWNLOADING && progress < 1.0) {
                            // Don't call callback here to avoid double-calling, the listener handles
                            // completion
                        }
                    }

                    Thread.sleep(1000); // Check every second
                } catch (Exception e) {
                    Log.e(TAG, "Error monitoring download progress", e);
                    break;
                }
            }
        });
    }

    /**
     * Check if HLS is downloaded
     */
    public boolean isHLSDownloaded(String url) {
        try {
            String downloadId = url;
            Download download = downloadManager.getDownloadIndex().getDownload(downloadId);
            boolean isCompleted = download != null && download.state == Download.STATE_COMPLETED;
            Log.d(TAG, "Checking download status for " + url + ": " + isCompleted);
            return isCompleted;
        } catch (Exception e) {
            Log.e(TAG, "Failed to check HLS download status for URL: " + url, e);
            return false;
        }
    }

    /**
     * Get HLS download progress (0.0 to 1.0)
     */
    public double getHLSDownloadProgress(String url) {
        try {
            String downloadId = url;
            Download download = downloadManager.getDownloadIndex().getDownload(downloadId);

            if (download == null) {
                return 0.0;
            }
            return getDownloadProgressForDownload(download);
        } catch (Exception e) {
            Log.e(TAG, "Failed to get HLS download progress for URL: " + url, e);
            return 0.0;
        }
    }

    private double getDownloadProgressForDownload(Download download) {
        double percentDownloaded = download.getPercentDownloaded();
        if (percentDownloaded != C.PERCENTAGE_UNSET) {
            if (download.state == Download.STATE_COMPLETED)
                return 1.0;
            return Math.max(0.0, Math.min(1.0, percentDownloaded / 100.0));
        }
        long bytesDownloaded = download.getBytesDownloaded();
        if (bytesDownloaded > 0) {
            double estimatedProgress;
            if (bytesDownloaded < 5 * 1024 * 1024) {
                estimatedProgress = bytesDownloaded / (10.0 * 1024 * 1024);
            } else if (bytesDownloaded < 15 * 1024 * 1024) {
                estimatedProgress = 0.5 + (bytesDownloaded - 5 * 1024 * 1024) / (20.0 * 1024 * 1024);
            } else {
                estimatedProgress = 0.75 + (bytesDownloaded - 15 * 1024 * 1024) / (60.0 * 1024 * 1024);
            }
            return Math.min(0.95, estimatedProgress);
        }
        return 0.0;
    }

    /**
     * Delete HLS download
     */
    public boolean deleteHLSDownload(String url) {
        try {
            String downloadId = url;
            downloadManager.removeDownload(downloadId);
            downloadCallbacks.remove(url);
            Log.d(TAG, "Deleted HLS download for: " + url);
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Failed to delete HLS download", e);
            return false;
        }
    }

    /**
     * Cancel HLS download
     */
    public void cancelHLSDownload(String url) {
        try {
            String downloadId = url;
            downloadManager.removeDownload(downloadId);

            JustAudioHLSCachePlugin.DownloadProgressCallback callback = downloadCallbacks.remove(url);
            if (callback != null) {
                callback.onProgress(0.0, "Download cancelled");
            }

            Log.d(TAG, "Cancelled HLS download for: " + url);
        } catch (Exception e) {
            Log.e(TAG, "Failed to cancel HLS download", e);
        }
    }

    /**
     * Get all HLS downloads
     */
    public List<Map<String, Object>> getAllHLSDownloads() {
        List<Map<String, Object>> downloads = new ArrayList<>();
        try (DownloadCursor cursor = downloadManager.getDownloadIndex().getDownloads()) {
            int count = 0;
            while (cursor.moveToNext()) {
                Download download = cursor.getDownload();
                Log.d(TAG, "Found download: id=" + download.request.id + ", uri=" + download.request.uri + ", state="
                        + download.state);
                Map<String, Object> downloadInfo = new HashMap<>();
                downloadInfo.put("url", download.request.uri.toString());
                downloadInfo.put("id", download.request.id); // <-- add this
                downloadInfo.put("progress", getDownloadProgressForDownload(download));
                downloadInfo.put("isCompleted", download.state == Download.STATE_COMPLETED);
                downloadInfo.put("state", getDownloadStateString(download.state));
                downloads.add(downloadInfo);
                count++;
            }
            Log.d(TAG, "Total downloads found: " + count);
        } catch (Exception e) {
            Log.e(TAG, "Failed to get all HLS downloads", e);
        }
        return downloads;
    }

    /**
     * Clear all downloads
     */
    public void clearAllDownloads() {
        try (DownloadCursor cursor = downloadManager.getDownloadIndex().getDownloads()) {
            while (cursor.moveToNext()) {
                Download download = cursor.getDownload();
                downloadManager.removeDownload(download.request.id);
            }
            downloadCallbacks.clear();
            Log.d(TAG, "Cleared all downloads");
        } catch (Exception e) {
            Log.e(TAG, "Failed to clear all downloads", e);
        }
    }

    /**
     * Get cached URI for downloaded content (for offline playback)
     */
    @Nullable
    public String getCachedUri(String url) {
        try {
            String downloadId = url;
            Download download = downloadManager.getDownloadIndex().getDownload(downloadId);
            if (download != null && download.state == Download.STATE_COMPLETED) {
                return downloadId;
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to get cached URI for URL: " + url, e);
        }
        return null;
    }

    private String getDownloadStateString(int state) {
        switch (state) {
            case Download.STATE_QUEUED:
                return "queued";
            case Download.STATE_DOWNLOADING:
                return "downloading";
            case Download.STATE_COMPLETED:
                return "completed";
            case Download.STATE_FAILED:
                return "failed";
            case Download.STATE_REMOVING:
                return "removing";
            case Download.STATE_RESTARTING:
                return "restarting";
            case Download.STATE_STOPPED:
                return "stopped";
            default:
                return "unknown";
        }
    }

    /**
     * Release resources
     */
    public void release() {
        if (downloadManager != null) {
            downloadManager.release();
        }
        downloadCallbacks.clear();
    }
}
