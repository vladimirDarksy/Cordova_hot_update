/**
 * HotUpdates.java
 * Hot Updates Plugin for Cordova Android
 *
 * Frontend-controlled hot updates with WebView reload approach.
 * API matches iOS implementation v2.2.2
 *
 * Based on nordnetab/cordova-hot-code-push utilities.
 *
 * @version 2.2.2
 * @author Mustafin Vladimir
 */
package com.getmeback.hotupdates;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.webkit.MimeTypeMap;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;

import androidx.webkit.WebViewAssetLoader;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaPluginPathHandler;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import static com.getmeback.hotupdates.HotUpdatesConstants.*;
import static com.getmeback.hotupdates.HotUpdatesHelpers.*;

/**
 * Main plugin class for Hot Updates.
 * Provides frontend-controlled manual hot updates functionality.
 */
public class HotUpdates extends CordovaPlugin {

    // Paths
    private String filesDir;
    private String wwwPath;
    private String previousVersionPath;

    // State
    private boolean isDownloadingUpdate = false;
    private boolean isUpdateReadyToInstall = false;
    private String pendingUpdateVersion;
    private String appBundleVersion;

    // Lists
    private Set<String> ignoreList = new HashSet<>();
    private List<String> versionHistory = new ArrayList<>();

    // Canary timer
    private Handler canaryHandler;
    private Runnable canaryRunnable;

    // Executor for background tasks
    private ExecutorService executor = Executors.newSingleThreadExecutor();

    // ============================================================
    // Plugin Lifecycle
    // ============================================================

    @Override
    protected void pluginInitialize() {
        super.pluginInitialize();

        Context context = cordova.getActivity().getApplicationContext();
        filesDir = context.getFilesDir().getAbsolutePath();
        wwwPath = filesDir + "/" + DIR_WWW;
        previousVersionPath = filesDir + "/" + DIR_WWW_PREVIOUS;

        canaryHandler = new Handler(Looper.getMainLooper());

        loadConfiguration();
        loadIgnoreList();
        loadVersionHistory();

        // Reset download flag (in case app was killed during download)
        isDownloadingUpdate = false;
        getPrefs().edit().putBoolean(PREF_DOWNLOAD_IN_PROGRESS, false).apply();

        // Load pending state
        isUpdateReadyToInstall = getPrefs().getBoolean(PREF_PENDING_UPDATE_READY, false);
        if (isUpdateReadyToInstall) {
            pendingUpdateVersion = getPrefs().getString(PREF_PENDING_VERSION, null);
        }

        Log.d(TAG, "Initializing plugin...");

        checkAndInstallPendingUpdate();
        initializeWWWFolder();

        // Start canary timer for current version
        String currentVersion = getPrefs().getString(PREF_INSTALLED_VERSION, null);
        if (currentVersion != null) {
            String canaryVersion = getPrefs().getString(PREF_CANARY_VERSION, null);
            if (canaryVersion == null || !canaryVersion.equals(currentVersion)) {
                Log.d(TAG, "Starting canary timer for version " + currentVersion);
                startCanaryTimer();
            }
        }

        Log.d(TAG, "Plugin initialized (v" + appBundleVersion + ")");
    }

    @Override
    public void onStart() {
        super.onStart();
        // No redirect needed - PathHandler transparently serves from files/www
        // when an installed version exists, or falls through to assets/www otherwise
    }

    @Override
    public void onDestroy() {
        if (canaryHandler != null && canaryRunnable != null) {
            canaryHandler.removeCallbacks(canaryRunnable);
        }
        executor.shutdown();
        super.onDestroy();
    }

    // ============================================================
    // PathHandler - serve updated files via https://localhost/
    // ============================================================

    @Override
    public CordovaPluginPathHandler getPathHandler() {
        WebViewAssetLoader.PathHandler handler = path -> {
            try {
                // Only intercept if there's an installed version
                String installedVersion = getPrefs().getString(PREF_INSTALLED_VERSION, null);
                if (installedVersion == null) {
                    return null; // Let Cordova serve from assets/www
                }

                File wwwDir = new File(wwwPath);
                if (!wwwDir.exists()) {
                    return null;
                }

                if (path.isEmpty()) {
                    path = INDEX_HTML;
                }

                File file = new File(wwwDir, path);

                // Security: prevent path traversal
                if (!file.getCanonicalPath().startsWith(wwwDir.getCanonicalPath())) {
                    Log.e(TAG, "Path traversal attempt blocked: " + path);
                    return null;
                }

                if (!file.exists() || file.isDirectory()) {
                    return null; // Fall through to Cordova default handler
                }

                String mimeType = getMimeType(path);
                InputStream is = new FileInputStream(file);
                return new WebResourceResponse(mimeType, null, is);

            } catch (Exception e) {
                Log.e(TAG, "PathHandler error: " + e.getMessage());
                return null;
            }
        };

        return new CordovaPluginPathHandler(handler);
    }

    private String getMimeType(String path) {
        if (path.endsWith(".js") || path.endsWith(".mjs")) {
            return "application/javascript";
        } else if (path.endsWith(".wasm")) {
            return "application/wasm";
        } else if (path.endsWith(".html") || path.endsWith(".htm")) {
            return "text/html";
        } else if (path.endsWith(".css")) {
            return "text/css";
        } else if (path.endsWith(".json")) {
            return "application/json";
        } else if (path.endsWith(".svg")) {
            return "image/svg+xml";
        }

        String extension = MimeTypeMap.getFileExtensionFromUrl("file:///" + path);
        if (extension != null) {
            String mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension);
            if (mime != null) return mime;
        }
        return "application/octet-stream";
    }

    // ============================================================
    // Configuration
    // ============================================================

    private void loadConfiguration() {
        try {
            Context context = cordova.getActivity().getApplicationContext();
            appBundleVersion = context.getPackageManager()
                    .getPackageInfo(context.getPackageName(), 0).versionName;
        } catch (PackageManager.NameNotFoundException e) {
            appBundleVersion = "1.0.0";
        }
    }

    private SharedPreferences getPrefs() {
        return cordova.getActivity().getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    // ============================================================
    // JavaScript Interface
    // ============================================================

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        switch (action) {
            case "getUpdate":
                getUpdate(args, callbackContext);
                return true;
            case "forceUpdate":
                forceUpdate(callbackContext);
                return true;
            case "canary":
                canary(args, callbackContext);
                return true;
            case "getIgnoreList":
                getIgnoreList(callbackContext);
                return true;
            case "getVersionHistory":
                getVersionHistory(callbackContext);
                return true;
            case "getVersionInfo":
                getVersionInfo(callbackContext);
                return true;
            default:
                return false;
        }
    }

    // ============================================================
    // getUpdate - Download update
    // ============================================================

    private void getUpdate(JSONArray args, CallbackContext callbackContext) {
        JSONObject updateData = args.optJSONObject(0);

        if (updateData == null) {
            sendError(callbackContext, ERROR_UPDATE_DATA_REQUIRED, "Update data required");
            return;
        }

        String downloadURL = updateData.optString("url", null);
        if (downloadURL == null || downloadURL.isEmpty()) {
            sendError(callbackContext, ERROR_URL_REQUIRED, "URL is required");
            return;
        }

        String updateVersion = updateData.optString("version", "pending");

        Log.d(TAG, "getUpdate: v" + updateVersion + " from " + downloadURL);

        // Check if already installed
        String installedVersion = getPrefs().getString(PREF_INSTALLED_VERSION, null);
        if (installedVersion != null && installedVersion.equals(updateVersion)) {
            Log.d(TAG, "Version " + updateVersion + " already installed, skipping download");
            callbackContext.success();
            return;
        }

        // Check if already downloaded
        boolean hasPending = getPrefs().getBoolean(PREF_HAS_PENDING, false);
        String existingPendingVersion = getPrefs().getString(PREF_PENDING_VERSION, null);
        if (hasPending && existingPendingVersion != null && existingPendingVersion.equals(updateVersion)) {
            Log.d(TAG, "Version " + updateVersion + " already downloaded, skipping re-download");
            callbackContext.success();
            return;
        }

        // Check if download in progress
        if (isDownloadingUpdate) {
            sendError(callbackContext, ERROR_DOWNLOAD_IN_PROGRESS, "Download already in progress");
            return;
        }

        pendingUpdateVersion = updateVersion;
        downloadUpdate(downloadURL, callbackContext);
    }

    private void downloadUpdate(String downloadURL, CallbackContext callbackContext) {
        isDownloadingUpdate = true;
        getPrefs().edit().putBoolean(PREF_DOWNLOAD_IN_PROGRESS, true).apply();

        Log.d(TAG, "Starting download from: " + downloadURL);

        executor.execute(() -> {
            HttpURLConnection connection = null;
            InputStream input = null;
            FileOutputStream output = null;

            try {
                URL url = new URL(downloadURL);
                connection = (HttpURLConnection) url.openConnection();
                connection.setConnectTimeout(HTTP_CONNECT_TIMEOUT_MS);
                connection.setReadTimeout(HTTP_READ_TIMEOUT_MS);
                connection.connect();

                int responseCode = connection.getResponseCode();
                if (responseCode != HttpURLConnection.HTTP_OK) {
                    throw new IOException("HTTP error: " + responseCode);
                }

                // Download to temp file
                File tempZip = new File(filesDir, "update_temp.zip");
                input = new BufferedInputStream(connection.getInputStream());
                output = new FileOutputStream(tempZip);

                byte[] buffer = new byte[8192];
                int bytesRead;
                while ((bytesRead = input.read(buffer)) != -1) {
                    output.write(buffer, 0, bytesRead);
                }
                output.flush();
                output.close();
                output = null;
                input.close();
                input = null;

                Log.d(TAG, "Download completed, verifying...");

                // Verify and extract
                saveDownloadedUpdate(tempZip, callbackContext);

            } catch (Exception e) {
                Log.e(TAG, "Download failed: " + e.getMessage());
                isDownloadingUpdate = false;
                getPrefs().edit().putBoolean(PREF_DOWNLOAD_IN_PROGRESS, false).apply();

                String errorCode = ERROR_DOWNLOAD_FAILED;
                if (e.getMessage() != null && e.getMessage().startsWith("HTTP error:")) {
                    errorCode = ERROR_HTTP_ERROR;
                }
                sendErrorOnMain(cordova, callbackContext, errorCode, "Download failed: " + e.getMessage());

            } finally {
                if (output != null) try { output.close(); } catch (Exception ignored) {}
                if (input != null) try { input.close(); } catch (Exception ignored) {}
                if (connection != null) connection.disconnect();
            }
        });
    }

    private void saveDownloadedUpdate(File zipFile, CallbackContext callbackContext) {
        try {
            // Create temp directory for new download
            File newDownloadDir = new File(filesDir, DIR_TEMP_NEW_DOWNLOAD);
            deleteRecursive(newDownloadDir);
            newDownloadDir.mkdirs();

            // Extract ZIP
            if (!extractZip(zipFile, newDownloadDir)) {
                throw new IOException("Failed to extract ZIP");
            }

            // Find www folder
            File wwwInZip = findWwwFolder(newDownloadDir);
            if (wwwInZip == null) {
                deleteRecursive(newDownloadDir);
                throw new IOException("www folder not found in archive");
            }

            // Move to temp_downloaded_update
            File tempUpdateDir = new File(filesDir, DIR_TEMP_DOWNLOADED);
            deleteRecursive(tempUpdateDir);
            tempUpdateDir.mkdirs();

            File destWww = new File(tempUpdateDir, DIR_WWW);
            copyDirectory(wwwInZip, destWww);

            // Also copy to pending_update for auto-install on next launch
            File pendingDir = new File(filesDir, DIR_PENDING_UPDATE);
            deleteRecursive(pendingDir);
            pendingDir.mkdirs();
            copyDirectory(tempUpdateDir, pendingDir);

            // Cleanup
            deleteRecursive(newDownloadDir);
            zipFile.delete();

            // Update state
            isUpdateReadyToInstall = true;
            isDownloadingUpdate = false;

            SharedPreferences.Editor editor = getPrefs().edit();
            editor.putBoolean(PREF_DOWNLOAD_IN_PROGRESS, false);
            editor.putBoolean(PREF_PENDING_UPDATE_READY, true);
            editor.putBoolean(PREF_HAS_PENDING, true);
            editor.putString(PREF_PENDING_VERSION, pendingUpdateVersion);
            editor.apply();

            Log.d(TAG, "Update ready (v" + pendingUpdateVersion + ")");

            sendSuccessOnMain(cordova, callbackContext);

        } catch (Exception e) {
            Log.e(TAG, "Save update failed: " + e.getMessage());
            isDownloadingUpdate = false;
            getPrefs().edit().putBoolean(PREF_DOWNLOAD_IN_PROGRESS, false).apply();

            String errorCode = ERROR_EXTRACTION_FAILED;
            if (e.getMessage() != null && e.getMessage().contains("www folder not found")) {
                errorCode = ERROR_WWW_NOT_FOUND;
            }
            sendErrorOnMain(cordova, callbackContext, errorCode, e.getMessage());
        }
    }

    // ============================================================
    // forceUpdate - Install update
    // ============================================================

    private void forceUpdate(CallbackContext callbackContext) {
        if (!isUpdateReadyToInstall) {
            sendError(callbackContext, ERROR_NO_UPDATE_READY, "No update ready to install");
            return;
        }

        File tempUpdateDir = new File(filesDir, DIR_TEMP_DOWNLOADED);
        File tempWwwDir = new File(tempUpdateDir, DIR_WWW);

        if (!tempWwwDir.exists()) {
            sendError(callbackContext, ERROR_UPDATE_FILES_NOT_FOUND, "Downloaded update files not found");
            return;
        }

        String versionToInstall = getPrefs().getString(PREF_PENDING_VERSION, "unknown");
        Log.d(TAG, "forceUpdate: installing v" + versionToInstall);

        try {
            // Backup current version
            backupCurrentVersion();

            // Remove current www and copy new one
            File wwwDir = new File(wwwPath);
            deleteRecursive(wwwDir);
            copyDirectory(tempWwwDir, wwwDir);

            // Update preferences
            SharedPreferences.Editor editor = getPrefs().edit();
            editor.putString(PREF_INSTALLED_VERSION, versionToInstall);
            editor.putBoolean(PREF_PENDING_UPDATE_READY, false);
            editor.putBoolean(PREF_HAS_PENDING, false);
            editor.remove(PREF_PENDING_VERSION);
            editor.remove(PREF_CANARY_VERSION);
            editor.apply();

            // Cleanup temp directories
            deleteRecursive(tempUpdateDir);
            deleteRecursive(new File(filesDir, DIR_PENDING_UPDATE));

            // Update state
            isUpdateReadyToInstall = false;
            pendingUpdateVersion = null;

            // Add to version history
            addVersionToHistory(versionToInstall);

            Log.d(TAG, "Update installed successfully");

            callbackContext.success();

            // Reload WebView with new content
            startCanaryTimer();
            reloadWebView();

        } catch (Exception e) {
            Log.e(TAG, "Install failed: " + e.getMessage());
            sendError(callbackContext, ERROR_INSTALL_FAILED, "Install failed: " + e.getMessage());
        }
    }

    // ============================================================
    // canary - Confirm successful bundle load
    // ============================================================

    private void canary(JSONArray args, CallbackContext callbackContext) {
        String canaryVersion = args.optString(0, null);

        if (canaryVersion == null || canaryVersion.isEmpty()) {
            sendError(callbackContext, ERROR_VERSION_REQUIRED, "Version is required");
            return;
        }

        // Save canary version (like iOS - accepts any version)
        getPrefs().edit().putString(PREF_CANARY_VERSION, canaryVersion).apply();

        // Stop canary timer
        if (canaryHandler != null && canaryRunnable != null) {
            canaryHandler.removeCallbacks(canaryRunnable);
            canaryRunnable = null;
            Log.d(TAG, "Canary confirmed: v" + canaryVersion);
        }

        callbackContext.success();
    }

    // ============================================================
    // Canary Timer
    // ============================================================

    private void startCanaryTimer() {
        if (canaryHandler != null && canaryRunnable != null) {
            canaryHandler.removeCallbacks(canaryRunnable);
        }

        canaryRunnable = () -> {
            Log.w(TAG, "CANARY TIMEOUT - JS did not call canary() within 20 seconds");
            canaryTimeout();
        };

        canaryHandler.postDelayed(canaryRunnable, CANARY_TIMEOUT_MS);
    }

    private void canaryTimeout() {
        String currentVersion = getPrefs().getString(PREF_INSTALLED_VERSION, null);
        String previousVersion = getPrefs().getString(PREF_PREVIOUS_VERSION, null);

        if (previousVersion == null || previousVersion.isEmpty()) {
            Log.d(TAG, "Fresh install from Store, rollback not possible");
            return;
        }

        Log.w(TAG, "Version " + currentVersion + " considered faulty, performing rollback");

        boolean rollbackSuccess = rollbackToPreviousVersion();

        if (rollbackSuccess) {
            Log.d(TAG, "Automatic rollback completed successfully");
            reloadWebView();
        } else {
            Log.e(TAG, "Automatic rollback failed");
        }
    }

    // ============================================================
    // Rollback
    // ============================================================

    private void backupCurrentVersion() {
        File wwwDir = new File(wwwPath);
        if (!wwwDir.exists()) return;

        File previousDir = new File(previousVersionPath);
        deleteRecursive(previousDir);

        try {
            copyDirectory(wwwDir, previousDir);

            String currentVersion = getPrefs().getString(PREF_INSTALLED_VERSION, appBundleVersion);
            getPrefs().edit().putString(PREF_PREVIOUS_VERSION, currentVersion).apply();
            Log.d(TAG, "Backed up version: " + currentVersion);
        } catch (IOException e) {
            Log.e(TAG, "Backup failed: " + e.getMessage());
        }
    }

    private boolean rollbackToPreviousVersion() {
        String currentVersion = getPrefs().getString(PREF_INSTALLED_VERSION, null);
        String previousVersion = getPrefs().getString(PREF_PREVIOUS_VERSION, null);

        Log.d(TAG, "Rollback: " + currentVersion + " -> " + previousVersion);

        if (previousVersion == null || previousVersion.isEmpty()) {
            Log.e(TAG, "Rollback failed: no previous version");
            return false;
        }

        File previousDir = new File(previousVersionPath);
        if (!previousDir.exists()) {
            Log.e(TAG, "Rollback failed: previous version folder not found");
            return false;
        }

        // Prevent rollback loop
        if (previousVersion.equals(currentVersion)) {
            Log.e(TAG, "Rollback failed: cannot rollback to same version");
            return false;
        }

        try {
            // Backup current to temp
            File backupDir = new File(filesDir, DIR_WWW_BACKUP);
            deleteRecursive(backupDir);

            File wwwDir = new File(wwwPath);
            if (wwwDir.exists()) {
                wwwDir.renameTo(backupDir);
            }

            // Copy previous to www
            copyDirectory(previousDir, wwwDir);

            // Update preferences
            SharedPreferences.Editor editor = getPrefs().edit();
            editor.putString(PREF_INSTALLED_VERSION, previousVersion);
            editor.remove(PREF_PREVIOUS_VERSION);
            editor.apply();

            // Cleanup backup
            deleteRecursive(backupDir);

            Log.d(TAG, "Rollback successful: " + currentVersion + " -> " + previousVersion);

            // Add failed version to ignore list
            if (currentVersion != null) {
                addVersionToIgnoreList(currentVersion);
                removeVersionFromHistory(currentVersion);
            }

            return true;

        } catch (Exception e) {
            Log.e(TAG, "Rollback failed: " + e.getMessage());
            return false;
        }
    }

    // ============================================================
    // IgnoreList Management
    // ============================================================

    private void loadIgnoreList() {
        Set<String> saved = getPrefs().getStringSet(PREF_IGNORE_LIST, null);
        ignoreList = saved != null ? new HashSet<>(saved) : new HashSet<>();
    }

    private void saveIgnoreList() {
        getPrefs().edit().putStringSet(PREF_IGNORE_LIST, ignoreList).apply();
    }

    private void addVersionToIgnoreList(String version) {
        if (version != null && !ignoreList.contains(version)) {
            ignoreList.add(version);
            saveIgnoreList();
            Log.d(TAG, "Added version " + version + " to ignore list");
        }
    }

    private void getIgnoreList(CallbackContext callbackContext) {
        try {
            JSONObject result = new JSONObject();
            JSONArray versions = new JSONArray();
            for (String v : ignoreList) {
                versions.put(v);
            }
            result.put("versions", versions);
            callbackContext.success(result);
        } catch (JSONException e) {
            callbackContext.error("Failed to get ignore list");
        }
    }

    // ============================================================
    // Version History Management
    // ============================================================

    private void loadVersionHistory() {
        String saved = getPrefs().getString(PREF_VERSION_HISTORY, null);
        versionHistory = new ArrayList<>();

        if (saved != null && !saved.isEmpty()) {
            try {
                JSONArray arr = new JSONArray(saved);
                for (int i = 0; i < arr.length(); i++) {
                    versionHistory.add(arr.getString(i));
                }
            } catch (JSONException e) {
                Log.e(TAG, "Failed to parse version history");
            }
        } else {
            // Initialize with app bundle version on first launch
            if (appBundleVersion != null) {
                versionHistory.add(appBundleVersion);
                saveVersionHistory();
                Log.d(TAG, "Initial version history created with app version: " + appBundleVersion);
            }
        }
    }

    private void saveVersionHistory() {
        JSONArray arr = new JSONArray();
        for (String v : versionHistory) {
            arr.put(v);
        }
        getPrefs().edit().putString(PREF_VERSION_HISTORY, arr.toString()).apply();
    }

    private void addVersionToHistory(String version) {
        if (version != null && !versionHistory.contains(version)) {
            versionHistory.add(version);
            saveVersionHistory();
            Log.d(TAG, "Added version " + version + " to version history");
        }
    }

    private void removeVersionFromHistory(String version) {
        if (version != null && versionHistory.contains(version)) {
            versionHistory.remove(version);
            saveVersionHistory();
            Log.d(TAG, "Removed version " + version + " from version history");
        }
    }

    private void getVersionHistory(CallbackContext callbackContext) {
        try {
            JSONObject result = new JSONObject();
            JSONArray versions = new JSONArray();
            for (String v : versionHistory) {
                versions.put(v);
            }
            result.put("versions", versions);
            callbackContext.success(result);
        } catch (JSONException e) {
            callbackContext.error("Failed to get version history");
        }
    }

    // ============================================================
    // getVersionInfo - Debug method
    // ============================================================

    private void getVersionInfo(CallbackContext callbackContext) {
        try {
            JSONObject info = new JSONObject();
            SharedPreferences prefs = getPrefs();

            info.put("appBundleVersion", appBundleVersion);

            String installedVersion = prefs.getString(PREF_INSTALLED_VERSION, null);
            String previousVersion = prefs.getString(PREF_PREVIOUS_VERSION, null);
            String canaryVersion = prefs.getString(PREF_CANARY_VERSION, null);
            String pendingVersion = prefs.getString(PREF_PENDING_VERSION, null);

            info.put("installedVersion", installedVersion != null ? installedVersion : JSONObject.NULL);
            info.put("previousVersion", previousVersion != null ? previousVersion : JSONObject.NULL);
            info.put("canaryVersion", canaryVersion != null ? canaryVersion : JSONObject.NULL);
            info.put("pendingVersion", pendingVersion != null ? pendingVersion : JSONObject.NULL);
            info.put("hasPendingUpdate", prefs.getBoolean(PREF_HAS_PENDING, false));

            JSONArray ignoreArr = new JSONArray();
            for (String v : ignoreList) {
                ignoreArr.put(v);
            }
            info.put("ignoreList", ignoreArr);

            callbackContext.success(info);
        } catch (JSONException e) {
            callbackContext.error("Failed to get version info");
        }
    }

    // ============================================================
    // WWW Folder Initialization
    // ============================================================

    private boolean checkAndInstallPendingUpdate() {
        boolean hasPending = getPrefs().getBoolean(PREF_HAS_PENDING, false);
        String pendingVersion = getPrefs().getString(PREF_PENDING_VERSION, null);

        if (!hasPending || pendingVersion == null) return false;

        Log.d(TAG, "Auto-installing pending update: " + pendingVersion);

        backupCurrentVersion();

        File pendingDir = new File(filesDir, DIR_PENDING_UPDATE);
        File pendingWww = new File(pendingDir, DIR_WWW);
        File wwwDir = new File(wwwPath);

        if (pendingWww.exists()) {
            try {
                deleteRecursive(wwwDir);
                copyDirectory(pendingWww, wwwDir);

                SharedPreferences.Editor editor = getPrefs().edit();
                editor.putString(PREF_INSTALLED_VERSION, pendingVersion);
                editor.putBoolean(PREF_HAS_PENDING, false);
                editor.remove(PREF_PENDING_VERSION);
                editor.remove(PREF_CANARY_VERSION);
                editor.apply();

                deleteRecursive(pendingDir);
                addVersionToHistory(pendingVersion);

                Log.d(TAG, "Update " + pendingVersion + " installed successfully");
                return true;

            } catch (IOException e) {
                Log.e(TAG, "Failed to install pending update: " + e.getMessage());
                SharedPreferences.Editor editor = getPrefs().edit();
                editor.putBoolean(PREF_HAS_PENDING, false);
                editor.remove(PREF_PENDING_VERSION);
                editor.apply();
                deleteRecursive(pendingDir);
            }
        }
        return false;
    }

    private void initializeWWWFolder() {
        File wwwDir = new File(wwwPath);
        if (wwwDir.exists()) return;

        Log.d(TAG, "Initializing www folder from assets...");

        try {
            Context context = cordova.getActivity().getApplicationContext();
            copyAssetsFolder(context, "www", wwwPath);
            Log.d(TAG, "Initialized www folder from bundle");
        } catch (IOException e) {
            Log.e(TAG, "Failed to copy www folder: " + e.getMessage());
        }
    }

    // ============================================================
    // WebView Reload
    // ============================================================

    private void reloadWebView() {
        cordova.getActivity().runOnUiThread(() -> {
            try {
                android.webkit.WebView androidWebView = (android.webkit.WebView) webView.getView();
                WebSettings webSettings = androidWebView.getSettings();

                // Clear cache to force fresh load from PathHandler
                androidWebView.clearCache(true);
                androidWebView.clearHistory();
                webView.clearCache(true);
                webView.clearHistory();
                webSettings.setCacheMode(WebSettings.LOAD_NO_CACHE);

                // Always use https://localhost/ - PathHandler serves from files/www
                String hostname = preferences.getString("hostname", "localhost");
                String reloadUrl = "https://" + hostname + "/" + INDEX_HTML;

                Log.d(TAG, "Reloading WebView: " + reloadUrl);
                webView.loadUrlIntoView(reloadUrl, false);

            } catch (Exception e) {
                Log.e(TAG, "Failed to reload WebView: " + e.getMessage());
            }
        });
    }
}
