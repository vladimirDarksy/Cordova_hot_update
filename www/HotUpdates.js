var exec = require('cordova/exec');

/**
 * Cordova Hot Updates Plugin v2.1.2
 * Frontend-controlled manual hot updates for iOS
 *
 * Provides manual over-the-air (OTA) updates for Cordova applications
 * using the WebView Reload approach. All update decisions are controlled
 * by JavaScript - the native plugin only executes commands.
 *
 * Features:
 * - Frontend-controlled manual updates (no automatic checking)
 * - Two-step update flow: getUpdate() downloads, forceUpdate() installs
 * - Automatic rollback with 20-second canary timer
 * - IgnoreList system for tracking problematic versions (information only)
 * - Auto-install pending updates on next app launch
 * - WebView reload approach for instant updates without app restart
 * - No App Store approval required for web content updates
 *
 * @version 2.1.2
 * @author Mustafin Vladimir
 */
var HotUpdates = {

    /**
     * Download update from server
     *
     * Downloads update ZIP archive from the provided URL and saves to two locations:
     * - temp_downloaded_update (for immediate installation via forceUpdate)
     * - pending_update (for auto-installation on next app launch)
     *
     * If the specified version is already downloaded, returns success without re-downloading.
     * Does NOT check ignoreList - JavaScript controls all installation decisions.
     *
     * @param {Object} options - Update options
     * @param {string} options.url - URL to download ZIP archive (required)
     * @param {string} [options.version] - Version string (optional)
     * @param {Function} callback - Callback function
     *   - Called with null on success
     *   - Called with {error: {message?: string}} on error
     *
     * @example
     * window.hotUpdate.getUpdate({
     *     url: 'https://your-server.com/updates/2.0.0.zip',
     *     version: '2.0.0'
     * }, function(error) {
     *     if (error) {
     *         console.error('Download failed:', error);
     *     } else {
     *         console.log('Update downloaded successfully');
     *         // Can now call forceUpdate() to install immediately
     *         // Or user can ignore and it will auto-install on next launch
     *     }
     * });
     */
    getUpdate: function(options, callback) {
        if (!options || !options.url) {
            if (callback) {
                callback({error: {message: 'URL is required'}});
            }
            return;
        }

        exec(
            function() {
                // Success
                if (callback) callback(null);
            },
            function(error) {
                // Error
                if (callback) callback({error: error});
            },
            'HotUpdates',
            'getUpdate',
            [options]
        );
    },

    /**
     * Install downloaded update immediately
     *
     * Installs the update that was downloaded via getUpdate().
     * This will:
     * 1. Backup current version to www_previous
     * 2. Copy downloaded update to Documents/www
     * 3. Clear WebView cache (disk, memory, Service Worker)
     * 4. Reload WebView
     * 5. Start 20-second canary timer
     *
     * IMPORTANT: JavaScript MUST call canary(version) within 20 seconds
     * after reload to confirm successful bundle load. Otherwise automatic
     * rollback will occur.
     *
     * Does NOT check ignoreList - JavaScript decides what to install.
     *
     * @param {Function} callback - Callback function
     *   - Called with null on success (before WebView reload)
     *   - Called with {error: {message?: string}} on error
     *
     * @example
     * window.hotUpdate.forceUpdate(function(error) {
     *     if (error) {
     *         console.error('Install failed:', error);
     *     } else {
     *         console.log('Update installing, WebView will reload...');
     *         // After reload, MUST call canary() within 20 seconds!
     *     }
     * });
     */
    forceUpdate: function(callback) {
        exec(
            function() {
                // Success
                if (callback) callback(null);
            },
            function(error) {
                // Error
                if (callback) callback({error: error});
            },
            'HotUpdates',
            'forceUpdate',
            []
        );
    },

    /**
     * Confirm successful bundle load (canary check)
     *
     * MUST be called within 20 seconds after forceUpdate() to confirm
     * that the new bundle loaded successfully. This stops the canary timer
     * and prevents automatic rollback.
     *
     * If not called within 20 seconds:
     * - Automatic rollback to previous version
     * - Failed version added to ignoreList
     * - WebView reloaded with previous version
     *
     * Call this immediately after your app initialization completes.
     *
     * @param {string} version - Version that loaded successfully
     * @param {Function} [callback] - Optional callback (not used, method is synchronous)
     *
     * @example
     * // Call as early as possible after app loads
     * document.addEventListener('deviceready', function() {
     *     window.hotUpdate.canary('2.0.0');
     *     console.log('Canary confirmed, update successful');
     * }, false);
     */
    canary: function(version, callback) {
        exec(
            function() {
                if (callback) callback();
            },
            function() {
                if (callback) callback();
            },
            'HotUpdates',
            'canary',
            [version]
        );
    },

    /**
     * Get list of problematic versions (information only)
     *
     * Returns array of version strings that failed to load (triggered rollback).
     * This is an INFORMATION-ONLY system - native does NOT block installation
     * of versions in this list.
     *
     * JavaScript should read this list and decide whether to skip downloading/
     * installing these versions. If JS decides to install a version from the
     * ignoreList, that's allowed (per TS requirements).
     *
     * Native automatically adds versions to this list when rollback occurs.
     * JavaScript cannot modify the list (no add/remove/clear methods per TS v2.1.0).
     *
     * @param {Function} callback - Callback function
     *   - Called with {versions: string[]} - Array of problematic version strings
     *
     * @example
     * window.hotUpdate.getIgnoreList(function(result) {
     *     console.log('Problematic versions:', result.versions);
     *     // Example: {versions: ['1.9.0', '2.0.1']}
     *
     *     // JavaScript decides what to do with this information
     *     var shouldSkip = result.versions.includes(availableVersion);
     *     if (shouldSkip) {
     *         console.log('Skipping known problematic version');
     *     } else {
     *         // Download and install
     *     }
     * });
     */
    getIgnoreList: function(callback) {
        exec(
            function(versions) {
                // Success - native returns array of version strings
                if (callback) callback({versions: versions || []});
            },
            function(error) {
                // Error - return empty list
                if (callback) callback({versions: []});
            },
            'HotUpdates',
            'getIgnoreList',
            []
        );
    }
};

module.exports = HotUpdates;
