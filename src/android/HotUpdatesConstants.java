/**
 * HotUpdatesConstants.java
 * Constants for Hot Updates Plugin
 *
 * @version 2.2.2
 * @author Mustafin Vladimir
 */
package com.getmeback.hotupdates;

/**
 * Contains all constants used by the Hot Updates plugin.
 * Includes error codes, SharedPreferences keys, and directory names.
 */
public final class HotUpdatesConstants {

    private HotUpdatesConstants() {
        // Prevent instantiation
    }

    // ============================================================
    // Error Codes (matching iOS implementation)
    // ============================================================

    // getUpdate() errors
    public static final String ERROR_UPDATE_DATA_REQUIRED = "UPDATE_DATA_REQUIRED";
    public static final String ERROR_URL_REQUIRED = "URL_REQUIRED";
    public static final String ERROR_DOWNLOAD_IN_PROGRESS = "DOWNLOAD_IN_PROGRESS";
    public static final String ERROR_DOWNLOAD_FAILED = "DOWNLOAD_FAILED";
    public static final String ERROR_HTTP_ERROR = "HTTP_ERROR";
    public static final String ERROR_TEMP_DIR_ERROR = "TEMP_DIR_ERROR";
    public static final String ERROR_EXTRACTION_FAILED = "EXTRACTION_FAILED";
    public static final String ERROR_WWW_NOT_FOUND = "WWW_NOT_FOUND";

    // forceUpdate() errors
    public static final String ERROR_NO_UPDATE_READY = "NO_UPDATE_READY";
    public static final String ERROR_UPDATE_FILES_NOT_FOUND = "UPDATE_FILES_NOT_FOUND";
    public static final String ERROR_INSTALL_FAILED = "INSTALL_FAILED";

    // canary() errors
    public static final String ERROR_VERSION_REQUIRED = "VERSION_REQUIRED";

    // ============================================================
    // SharedPreferences Keys
    // ============================================================

    public static final String PREFS_NAME = "HotUpdatesPrefs";

    public static final String PREF_INSTALLED_VERSION = "hot_updates_installed_version";
    public static final String PREF_PENDING_VERSION = "hot_updates_pending_version";
    public static final String PREF_HAS_PENDING = "hot_updates_has_pending";
    public static final String PREF_PREVIOUS_VERSION = "hot_updates_previous_version";
    public static final String PREF_IGNORE_LIST = "hot_updates_ignore_list";
    public static final String PREF_VERSION_HISTORY = "hot_updates_version_history";
    public static final String PREF_CANARY_VERSION = "hot_updates_canary_version";
    public static final String PREF_DOWNLOAD_IN_PROGRESS = "hot_updates_download_in_progress";
    public static final String PREF_PENDING_UPDATE_URL = "hot_updates_pending_update_url";
    public static final String PREF_PENDING_UPDATE_READY = "hot_updates_pending_ready";

    // ============================================================
    // Directory Names
    // ============================================================

    public static final String DIR_WWW = "www";
    public static final String DIR_WWW_PREVIOUS = "www_previous";
    public static final String DIR_WWW_BACKUP = "www_backup";
    public static final String DIR_PENDING_UPDATE = "pending_update";
    public static final String DIR_TEMP_DOWNLOADED = "temp_downloaded_update";
    public static final String DIR_TEMP_NEW_DOWNLOAD = "temp_new_download";

    // ============================================================
    // Timing Constants
    // ============================================================

    /** Canary timeout in milliseconds (20 seconds) */
    public static final long CANARY_TIMEOUT_MS = 20000;

    /** HTTP connection timeout in milliseconds (30 seconds) */
    public static final int HTTP_CONNECT_TIMEOUT_MS = 30000;

    /** HTTP read timeout in milliseconds (60 seconds) */
    public static final int HTTP_READ_TIMEOUT_MS = 60000;

    // ============================================================
    // File Constants
    // ============================================================

    public static final String INDEX_HTML = "index.html";
    public static final String ZIP_EXTENSION = ".zip";

    // ZIP magic bytes (PK\x03\x04)
    public static final byte[] ZIP_MAGIC = {0x50, 0x4B, 0x03, 0x04};

    // ============================================================
    // Log Tag
    // ============================================================

    public static final String TAG = "HotUpdates";
}
