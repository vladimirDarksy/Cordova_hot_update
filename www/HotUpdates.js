var exec = require('cordova/exec');

/**
 * Cordova Hot Updates Plugin v2.2.1
 * Frontend-controlled manual hot updates for iOS
 *
 * @version 2.2.1
 * @author Mustafin Vladimir
 */

/**
 * Error codes returned by the plugin
 * @readonly
 * @enum {string}
 */
var ErrorCodes = {
    // getUpdate errors
    UPDATE_DATA_REQUIRED: 'UPDATE_DATA_REQUIRED',
    URL_REQUIRED: 'URL_REQUIRED',
    DOWNLOAD_IN_PROGRESS: 'DOWNLOAD_IN_PROGRESS',
    DOWNLOAD_FAILED: 'DOWNLOAD_FAILED',
    HTTP_ERROR: 'HTTP_ERROR',
    TEMP_DIR_ERROR: 'TEMP_DIR_ERROR',
    EXTRACTION_FAILED: 'EXTRACTION_FAILED',
    WWW_NOT_FOUND: 'WWW_NOT_FOUND',
    // forceUpdate errors
    NO_UPDATE_READY: 'NO_UPDATE_READY',
    UPDATE_FILES_NOT_FOUND: 'UPDATE_FILES_NOT_FOUND',
    INSTALL_FAILED: 'INSTALL_FAILED',
    // canary errors
    VERSION_REQUIRED: 'VERSION_REQUIRED'
};

var HotUpdates = {

    /**
     * Error codes enum
     * @type {Object}
     */
    ErrorCodes: ErrorCodes,

    /**
     * Download update from server
     *
     * @param {Object} options - Update options
     * @param {string} options.url - URL to download ZIP archive (required)
     * @param {string} [options.version] - Version string (optional)
     * @param {Function} callback - Callback(error)
     *   - null on success
     *   - {error: {code: string, message: string}} on error
     *
     * @example
     * hotUpdate.getUpdate({url: 'https://server.com/update.zip', version: '2.0.0'}, function(err) {
     *     if (err) console.error(err.error.code, err.error.message);
     *     else console.log('Downloaded');
     * });
     */
    getUpdate: function(options, callback) {
        if (!options) {
            if (callback) {
                callback({error: {code: ErrorCodes.UPDATE_DATA_REQUIRED, message: 'Update data required'}});
            }
            return;
        }

        if (!options.url) {
            if (callback) {
                callback({error: {code: ErrorCodes.URL_REQUIRED, message: 'URL is required'}});
            }
            return;
        }

        exec(
            function() {
                if (callback) callback(null);
            },
            function(error) {
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
     * @param {Function} callback - Callback(error)
     *   - null on success (WebView will reload)
     *   - {error: {code: string, message: string}} on error
     *
     * @example
     * hotUpdate.forceUpdate(function(err) {
     *     if (err) console.error(err.error.code);
     *     // WebView reloads, call canary() within 20 sec
     * });
     */
    forceUpdate: function(callback) {
        exec(
            function() {
                if (callback) callback(null);
            },
            function(error) {
                if (callback) callback({error: error});
            },
            'HotUpdates',
            'forceUpdate',
            []
        );
    },

    /**
     * Confirm successful bundle load (MUST call within 20 sec after forceUpdate)
     *
     * @param {string} version - Current version
     * @param {Function} [callback] - Optional callback
     *
     * @example
     * document.addEventListener('deviceready', function() {
     *     hotUpdate.canary('2.0.0');
     * });
     */
    canary: function(version, callback) {
        if (!version) {
            if (callback) {
                callback({error: {code: ErrorCodes.VERSION_REQUIRED, message: 'Version is required'}});
            }
            return;
        }

        exec(
            function() {
                if (callback) callback(null);
            },
            function(error) {
                if (callback) callback({error: error});
            },
            'HotUpdates',
            'canary',
            [version]
        );
    },

    /**
     * Get list of problematic versions
     *
     * @param {Function} callback - Callback({versions: string[]})
     *
     * @example
     * hotUpdate.getIgnoreList(function(result) {
     *     if (result.versions.includes(newVersion)) {
     *         console.log('Version is blacklisted');
     *     }
     * });
     */
    getIgnoreList: function(callback) {
        exec(
            function(result) {
                if (callback) callback(result || {versions: []});
            },
            function() {
                if (callback) callback({versions: []});
            },
            'HotUpdates',
            'getIgnoreList',
            []
        );
    },

    /**
     * Get version info (debug method)
     *
     * @param {Function} callback - Callback with version info
     *   {
     *     appBundleVersion: string,
     *     installedVersion: string|null,
     *     previousVersion: string|null,
     *     canaryVersion: string|null,
     *     pendingVersion: string|null,
     *     hasPendingUpdate: boolean,
     *     ignoreList: string[]
     *   }
     *
     * @example
     * hotUpdate.getVersionInfo(function(info) {
     *     console.log('Current:', info.installedVersion || info.appBundleVersion);
     * });
     */
    getVersionInfo: function(callback) {
        exec(
            function(info) {
                if (callback) callback(info);
            },
            function(error) {
                if (callback) callback({error: error});
            },
            'HotUpdates',
            'getVersionInfo',
            []
        );
    }
};

module.exports = HotUpdates;
