var exec = require('cordova/exec');

/**
 * Cordova Hot Updates Plugin
 *
 * Provides automatic over-the-air (OTA) updates for Cordova applications
 * using the WebView Reload approach for instant updates.
 *
 * Features:
 * - Automatic background update checking
 * - Seamless download and installation
 * - Version compatibility checks
 * - Configurable update intervals
 * - No App Store approval required for web content updates
 *
 * @version 1.0.0
 * @author Mustafin Vladimir
 */
var HotUpdates = {

    /**
     * Get current version information
     * Returns the currently active version (installed update or bundle version)
     *
     * @param {Function} successCallback - Success callback with version string
     * @param {Function} errorCallback - Error callback
     *
     * @example
     * HotUpdates.getCurrentVersion(
     *   function(version) {
     *     console.log('Current version:', version);
     *   },
     *   function(error) {
     *     console.error('Error getting version:', error);
     *   }
     * );
     */
    getCurrentVersion: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'HotUpdates', 'getCurrentVersion', []);
    },

    /**
     * Get pending update information
     * Returns information about downloaded updates waiting to be installed
     *
     * @param {Function} successCallback - Success callback with update info object
     * @param {Function} errorCallback - Error callback
     *
     * Success callback receives object with:
     * - hasPendingUpdate: boolean
     * - pendingVersion: string (if available)
     * - appBundleVersion: string
     * - installedVersion: string (current hot update version)
     * - message: string (human readable status)
     *
     * @example
     * HotUpdates.getPendingUpdateInfo(
     *   function(info) {
     *     if (info.hasPendingUpdate) {
     *       console.log('Update ready:', info.pendingVersion);
     *       console.log('Will install on next app restart');
     *     }
     *   },
     *   function(error) {
     *     console.error('Error getting update info:', error);
     *   }
     * );
     */
    getPendingUpdateInfo: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'HotUpdates', 'getPendingUpdateInfo', []);
    },

    /**
     * Check for updates manually
     * Triggers an immediate check for available updates on the server
     *
     * @param {Function} successCallback - Success callback with check result
     * @param {Function} errorCallback - Error callback
     *
     * Success callback receives object with:
     * - hasUpdate: boolean
     * - currentVersion: string
     * - availableVersion: string (if hasUpdate is true)
     * - downloadURL: string (if hasUpdate is true)
     *
     * @example
     * HotUpdates.checkForUpdates(
     *   function(result) {
     *     if (result.hasUpdate) {
     *       console.log('Update available:', result.availableVersion);
     *     } else {
     *       console.log('No updates available');
     *     }
     *   },
     *   function(error) {
     *     console.error('Update check failed:', error);
     *   }
     * );
     */
    checkForUpdates: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'HotUpdates', 'checkForUpdates', []);
    },

    /**
     * Download available update
     * Manually triggers download of an available update
     *
     * @param {string} downloadURL - URL to download the update from
     * @param {string} version - Version string of the update
     * @param {Function} successCallback - Success callback when download completes
     * @param {Function} errorCallback - Error callback
     * @param {Function} progressCallback - Optional progress callback with download percentage
     *
     * @example
     * HotUpdates.downloadUpdate(
     *   'https://server.com/updates/v2.0.0.zip',
     *   '2.0.0',
     *   function() {
     *     console.log('Download completed, update will install on restart');
     *   },
     *   function(error) {
     *     console.error('Download failed:', error);
     *   },
     *   function(progress) {
     *     console.log('Download progress:', progress + '%');
     *   }
     * );
     */
    downloadUpdate: function(downloadURL, version, successCallback, errorCallback, progressCallback) {
        var callbackId = successCallback ? 'HotUpdates' + Date.now() : null;

        if (progressCallback) {
            // Register progress callback if provided
            exec(progressCallback, null, 'HotUpdates', 'setProgressCallback', [callbackId]);
        }

        exec(successCallback, errorCallback, 'HotUpdates', 'downloadUpdate', [downloadURL, version, callbackId]);
    },

    /**
     * Get plugin configuration
     * Returns current plugin configuration settings
     *
     * @param {Function} successCallback - Success callback with config object
     * @param {Function} errorCallback - Error callback
     *
     * Success callback receives object with:
     * - serverURL: string (update server URL)
     * - checkInterval: number (check interval in milliseconds)
     * - appBundleVersion: string (native app version)
     * - autoDownload: boolean (automatic download enabled)
     *
     * @example
     * HotUpdates.getConfiguration(
     *   function(config) {
     *     console.log('Server URL:', config.serverURL);
     *     console.log('Check interval:', config.checkInterval + 'ms');
     *   },
     *   function(error) {
     *     console.error('Error getting config:', error);
     *   }
     * );
     */
    getConfiguration: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'HotUpdates', 'getConfiguration', []);
    },

    /**
     * Install pending update immediately (requires app restart)
     * Forces installation of a downloaded update without waiting for next app launch
     * This will restart the application!
     *
     * @param {Function} successCallback - Success callback (app will restart before this is called)
     * @param {Function} errorCallback - Error callback
     *
     * @example
     * HotUpdates.installUpdate(
     *   function() {
     *     // This callback may not be called as app restarts
     *     console.log('Update installed, app restarting...');
     *   },
     *   function(error) {
     *     console.error('Install failed:', error);
     *   }
     * );
     */
    installUpdate: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'HotUpdates', 'installUpdate', []);
    }
};

module.exports = HotUpdates;