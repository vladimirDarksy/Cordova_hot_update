# Cordova Hot Updates Plugin v2.3.0

Frontend-controlled manual hot updates for Cordova **iOS and Android** applications using WebView Reload approach.

[![npm version](https://badge.fury.io/js/cordova-plugin-hot-updates.svg)](https://badge.fury.io/js/cordova-plugin-hot-updates)
[![License](https://img.shields.io/badge/License-Custom%20Non--Commercial-blue.svg)](#license)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20Android-lightgrey.svg)](#platform-support)

This plugin enables **manual, JavaScript-controlled** web content updates for your Cordova applications without requiring App Store/Google Play approval. Your frontend code decides when to check, download, and install updates.

## Platform Support

| Platform | Version | Status | Notes |
|----------|---------|--------|-------|
| iOS | 2.1.2+ | Stable | Requires CocoaPods for SSZipArchive |
| Android | 2.3.0+ | Stable | Built-in ZIP support, no external dependencies |

Both platforms provide 100% API compatibility. The same JavaScript code works on both iOS and Android.

## Features

- **Cross-Platform** - Full support for iOS and Android with 100% API compatibility
- **Frontend Control** - JavaScript decides when to update (no automatic background checking)
- **Two-Step Updates** - Separate download and install methods for better UX control
- **Auto-Install on Launch** - If user ignores update prompt, it installs on next app launch
- **Canary System** - Automatic rollback if update fails to load (20-second timeout)
- **IgnoreList** - Tracks problematic versions (information only, does not block installation)
- **Version History** - Tracks successful versions for progressive data migrations
- **Instant Effect** - WebView Reload approach, no app restart required
- **Cache Management** - iOS clears WKWebView cache; Android uses LOAD_NO_CACHE mode
- **Security** - ZIP magic bytes validation on both platforms

## Installation

```bash
# Install from npm
cordova plugin add cordova-plugin-hot-updates

# For iOS: Install CocoaPods dependencies (required)
cd platforms/ios
pod install
cd ../..

# For Android: No additional dependencies needed!
```

Or install from local directory:

```bash
cordova plugin add /path/to/cordova-plugin-hot-updates
```

Or install from GitHub:

```bash
cordova plugin add https://github.com/vladimirDarksy/Cordova_hot_update.git
```

**Requirements:**

**iOS:**
- Cordova >= 7.0.0
- cordova-ios >= 4.4.0
- iOS >= 12.0
- CocoaPods (for SSZipArchive dependency)

**Android:**
- Cordova >= 7.0.0
- cordova-android >= 9.0.0
- Android >= 7.0 (API 24)
- No external dependencies (uses built-in `java.util.zip`)

**Automatic Configuration:**

The plugin automatically configures required settings during installation:
- iOS: NSAppTransportSecurity for HTTP connections
- Android: file scheme, AndroidInsecureFileModeEnabled, LoadUrlTimeoutValue

## Quick Start

### 1. Minimal Integration

```javascript
document.addEventListener('deviceready', function() {
    // CRITICAL: Confirm successful bundle load within 20 seconds
    var currentVersion = localStorage.getItem('app_version') || '1.0.0';
    window.hotUpdate.canary(currentVersion);

    // Check for updates
    checkForUpdates();
}, false);

function checkForUpdates() {
    fetch('https://your-server.com/api/check-update?version=1.0.0')
        .then(response => response.json())
        .then(data => {
            if (data.hasUpdate) {
                downloadAndInstall(data.downloadUrl, data.version);
            }
        });
}

function downloadAndInstall(url, version) {
    window.hotUpdate.getUpdate({url: url, version: version}, function(error) {
        if (!error) {
            if (confirm('Update available. Install now?')) {
                localStorage.setItem('app_version', version);
                window.hotUpdate.forceUpdate(function(error) {
                    // WebView will reload, canary() will be called in deviceready
                });
            }
            // If user declines, update auto-installs on next launch
        }
    });
}
```

## Error Handling

All errors are returned in a unified format for programmatic handling:

```javascript
// Error format
callback({
  error: {
    code: "ERROR_CODE",        // Code for programmatic handling
    message: "Detailed message" // Detailed message for logs
  }
})

// Success result
callback(null)
```

### Error Codes

#### getUpdate() errors:
- `UPDATE_DATA_REQUIRED` - Missing updateData parameter
- `URL_REQUIRED` - Missing url parameter
- `DOWNLOAD_IN_PROGRESS` - Download already in progress
- `DOWNLOAD_FAILED` - Network download error (message contains details)
- `HTTP_ERROR` - HTTP status != 200 (message contains status code)
- `TEMP_DIR_ERROR` - Error creating temporary directory
- `EXTRACTION_FAILED` - Error extracting ZIP archive
- `WWW_NOT_FOUND` - www folder not found in archive

#### forceUpdate() errors:
- `NO_UPDATE_READY` - getUpdate() not called first
- `UPDATE_FILES_NOT_FOUND` - Downloaded update files not found
- `INSTALL_FAILED` - Error copying files (message contains details)

#### canary() errors:
- `VERSION_REQUIRED` - Missing version parameter

### Error Handling Example

```javascript
window.hotUpdate.getUpdate({url: 'http://...'}, function(result) {
  if (result && result.error) {
    console.error('[HotUpdates]', result.error.code, ':', result.error.message);

    switch(result.error.code) {
      case 'HTTP_ERROR':
        // Handle HTTP errors
        break;
      case 'DOWNLOAD_FAILED':
        // Handle network errors
        break;
      default:
        console.error('Unknown error:', result.error);
    }
  } else {
    console.log('Update downloaded successfully');
  }
});
```

## API Reference

All API methods are available via `window.hotUpdate` after the `deviceready` event.

### window.hotUpdate.getUpdate(options, callback)

Downloads update from server.

Downloads ZIP from provided URL and saves to two locations:
- `temp_downloaded_update` (for immediate installation via `forceUpdate()`)
- `pending_update` (for auto-installation on next app launch)

If version already downloaded, returns success without re-downloading.

**Does NOT check ignoreList** - JavaScript controls all installation decisions.

**Parameters:**
- `options` (Object):
  - `url` (string, required) - URL to download ZIP archive
  - `version` (string, optional) - Version string
- `callback` (Function) - `callback(error)`
  - `null` on success
  - `{error: {message?: string}}` on error

**Example:**
```javascript
window.hotUpdate.getUpdate({
    url: 'https://your-server.com/updates/2.0.0.zip',
    version: '2.0.0'
}, function(error) {
    if (error) {
        console.error('Download failed:', error);
    } else {
        console.log('Update downloaded successfully');
    }
});
```

---

### window.hotUpdate.forceUpdate(callback)

Installs downloaded update immediately and reloads WebView.

**Process:**
1. Backup current version to `www_previous`
2. Copy downloaded update to `Documents/www`
3. Clear WebView cache (disk, memory, Service Worker)
4. Reload WebView
5. Start 20-second canary timer

**IMPORTANT:** JavaScript MUST call `canary(version)` within 20 seconds after reload to confirm successful bundle load. Otherwise automatic rollback occurs.

**Does NOT check ignoreList** - JavaScript decides what to install.

**Parameters:**
- `callback` (Function) - `callback(error)`
  - `null` on success (before WebView reload)
  - `{error: {message?: string}}` on error

**Example:**
```javascript
window.hotUpdate.forceUpdate(function(error) {
    if (error) {
        console.error('Install failed:', error);
    } else {
        console.log('Update installing, WebView will reload...');
    }
});
```

---

### window.hotUpdate.canary(version, callback)

Confirms successful bundle load after update.

**MUST be called within 20 seconds** after `forceUpdate()` to stop canary timer and prevent automatic rollback.

**If not called within 20 seconds:**
- Automatic rollback to previous version
- Failed version added to ignoreList
- WebView reloaded with previous version

**Parameters:**
- `version` (string) - Version that loaded successfully
- `callback` (Function, optional) - Not used, method is synchronous

**Example:**
```javascript
document.addEventListener('deviceready', function() {
    var version = localStorage.getItem('app_version') || '1.0.0';
    window.hotUpdate.canary(version);
}, false);
```

---

### window.hotUpdate.getIgnoreList(callback)

Returns list of problematic versions (information only).

**This is an INFORMATION-ONLY system** - native does NOT block installation. JavaScript should read this list and decide whether to skip these versions.

Native automatically adds versions to this list when rollback occurs.

**Parameters:**
- `callback` (Function) - `callback(result)`
  - `result`: `{versions: string[]}` - Array of problematic version strings

**Example:**
```javascript
window.hotUpdate.getIgnoreList(function(result) {
    console.log('Problematic versions:', result.versions);

    if (result.versions.includes(newVersion)) {
        console.log('Skipping known problematic version');
    }
});
```

---

### window.hotUpdate.getVersionHistory(callback)

Returns list of all successfully installed versions (excluding rolled back ones).

**New in v2.2.3** - Enables progressive data migrations.

When internal data structure changes, you may need to run migrations. This method returns the version history so your app can determine which migrations to run.

**Key behaviors:**
- **Automatically initialized** with `appBundleVersion` on first launch
- **Added to history** when update is successfully installed
- **Removed from history** when version is rolled back (failed canary)
- **Excludes ignoreList** - only contains successful versions

**Parameters:**
- `callback` (Function) - `callback(result)`
  - `result`: `{versions: string[]}` - Array of successful version strings

**Example:**
```javascript
window.hotUpdate.getVersionHistory(function(result) {
    console.log('Version history:', result.versions);
    // Example: ["2.7.7", "2.7.8", "2.7.9"]

    // Run migrations based on version progression
    result.versions.forEach((version, index) => {
        if (index > 0) {
            const from = result.versions[index - 1];
            const to = version;
            runMigration(from, to);
        }
    });
});
```

**Use Case:**
```javascript
// Check for missed critical versions
window.hotUpdate.getVersionHistory(function(result) {
    const criticalVersions = ['2.8.0', '3.0.0']; // Versions with important migrations
    const missed = criticalVersions.filter(v => !result.versions.includes(v));

    if (missed.length > 0) {
        console.warn('User skipped critical versions:', missed);
        // Run all missed critical migrations
        missed.forEach(v => runCriticalMigration(v));
    }
});
```

---

### window.hotUpdate.getVersionInfo(callback)

Returns version information (debug method).

**Parameters:**
- `callback` (Function) - `callback(info)`
  - `info.appBundleVersion` (string) - Native app version from Info.plist
  - `info.installedVersion` (string|null) - Current hot update version
  - `info.previousVersion` (string|null) - Last working version (for rollback)
  - `info.canaryVersion` (string|null) - Version confirmed by canary
  - `info.pendingVersion` (string|null) - Version pending installation
  - `info.hasPendingUpdate` (boolean) - Whether pending update exists
  - `info.ignoreList` (string[]) - Array of problematic versions

**Example:**
```javascript
window.hotUpdate.getVersionInfo(function(info) {
    console.log('App version:', info.appBundleVersion);
    console.log('Installed:', info.installedVersion);
    console.log('Previous:', info.previousVersion);
    console.log('Pending:', info.hasPendingUpdate ? info.pendingVersion : 'none');
});
```

---

## Complete Update Flow

```javascript
// Step 1: Check for updates on your server
function checkForUpdates() {
    var currentVersion = localStorage.getItem('app_version') || '1.0.0';

    fetch('https://your-server.com/api/check-update?version=' + currentVersion)
        .then(response => response.json())
        .then(data => {
            if (data.hasUpdate) {
                // Step 2: Check ignoreList
                window.hotUpdate.getIgnoreList(function(ignoreList) {
                    if (ignoreList.versions.includes(data.version)) {
                        console.log('Skipping problematic version');
                        return;
                    }

                    // Step 3: Download
                    window.hotUpdate.getUpdate({
                        url: data.downloadUrl,
                        version: data.version
                    }, function(error) {
                        if (!error) {
                            // Step 4: Prompt user
                            if (confirm('Update available. Install now?')) {
                                // Save version for canary check
                                localStorage.setItem('app_version', data.version);

                                // Step 5: Install
                                window.hotUpdate.forceUpdate(function(error) {
                                    // WebView will reload
                                });
                            }
                            // If declined, auto-installs on next launch
                        }
                    });
                });
            }
        });
}

// Step 6: After reload, confirm success
document.addEventListener('deviceready', function() {
    var version = localStorage.getItem('app_version') || '1.0.0';
    window.hotUpdate.canary(version); // Must call within 20 seconds!

    initApp();
}, false);
```

## How It Works

### Update Flow

1. **Download** (`getUpdate()`):
   - Downloads ZIP from URL
   - Validates `www` folder structure
   - Saves to TWO locations:
     - `temp_downloaded_update` (for immediate install)
     - `pending_update` (for auto-install on next launch)

2. **Installation Options**:
   - **Immediate**: User clicks "Update" → `forceUpdate()` installs now
   - **Deferred**: User ignores → Auto-installs on next app launch

3. **Rollback Protection**:
   - Previous version backed up before installation
   - 20-second canary timer starts after reload
   - If `canary()` not called → automatic rollback
   - Failed version added to ignoreList

4. **IgnoreList System**:
   - Native tracks failed versions
   - JavaScript reads via `getIgnoreList()`
   - **Does NOT block** - JS decides what to install

### Storage Structure

**iOS:**
```
~/Library/Application Support/[Bundle ID]/Documents/
├── www/                    // Active version
├── www_previous/           // Previous version (rollback)
├── pending_update/         // Next launch auto-install
└── temp_downloaded_update/ // Immediate install
```

**Android:**
```
/data/data/[package.name]/files/
├── www/                    // Active version
├── www_previous/           // Previous version (rollback)
├── pending_update/         // Next launch auto-install
└── temp_downloaded_update/ // Immediate install
```

### Version Management

- **appBundleVersion** - Native app version (Info.plist / build.gradle)
- **installedVersion** - Current hot update version
- **previousVersion** - Last working version (rollback)

## Update Server API

Your server should provide:

**Check API:**
```
GET https://your-server.com/api/check-update?version=1.0.0&platform=ios
GET https://your-server.com/api/check-update?version=1.0.0&platform=android

Response:
{
  "hasUpdate": true,
  "version": "2.0.0",
  "downloadUrl": "https://your-server.com/updates/ios/2.0.0.zip",
  "minAppVersion": "2.7.0",
  "releaseNotes": "Bug fixes"
}
```

**Update ZIP Structure:**
```
update.zip
└── www/
    ├── index.html
    ├── js/
    ├── css/
    └── ...
```

## Best Practices

### 1. Always Call Canary

```javascript
document.addEventListener('deviceready', function() {
    var version = localStorage.getItem('app_version');
    window.hotUpdate.canary(version); // Within 20 seconds!
}, false);
```

### 2. Check IgnoreList

```javascript
window.hotUpdate.getIgnoreList(function(result) {
    if (result.versions.includes(newVersion)) {
        console.log('Known problematic version');
    }
});
```

### 3. Handle Errors

```javascript
window.hotUpdate.getUpdate(options, function(error) {
    if (error) {
        analytics.track('update_failed', {error: error.message});
        showUserMessage('Update failed');
    }
});
```

### 4. Store Version

```javascript
// Before forceUpdate
localStorage.setItem('app_version', newVersion);

// After reload
var version = localStorage.getItem('app_version');
window.hotUpdate.canary(version);
```

## Troubleshooting

### Update doesn't install

- Check ZIP structure (must have `www/` folder)
- Check URL accessibility
- Check logs:
  - iOS: Xcode console `[HotUpdates] ...`
  - Android: `adb logcat -s HotUpdates:*`

### Automatic rollback

**Cause:** `canary()` not called within 20 seconds

**Solution:** Call immediately in `deviceready`:
```javascript
document.addEventListener('deviceready', function() {
    window.hotUpdate.canary(version); // First thing!
}, false);
```

### window.hotUpdate is undefined

**Cause:** Called before `deviceready`

**Solution:**
```javascript
document.addEventListener('deviceready', function() {
    console.log(window.hotUpdate); // Now available
}, false);
```

## Platform-Specific Notes

### iOS

**Technologies:**
- `NSUserDefaults` for metadata storage
- `NSTimer` for canary timer (20 seconds)
- `SSZipArchive` (CocoaPods) for ZIP extraction
- `WKWebView` with `loadFileURL()`

**Specifics:**
- Always loads from `file://` scheme
- ZIP magic bytes validation
- Cache clearing: disk, memory, Service Worker

### Android

**Technologies:**
- `SharedPreferences` for metadata storage
- `Handler + Runnable` for canary timer (20 seconds)
- `java.util.zip` (built-in) for ZIP extraction
- `CordovaWebView` with `loadUrlIntoView()`

**Specifics:**
- Starts from `https://localhost/`, switches to `file://` after update
- ZIP magic bytes validation
- Cache management: `LOAD_NO_CACHE` mode
- WebView file access automatically configured

**Code Structure:**
- `HotUpdates.java` - Main plugin class (700 lines)
- `HotUpdatesHelpers.java` - Utility methods (350 lines)
- `HotUpdatesConstants.java` - Constants (100 lines)

## Testing

### iOS Testing (Safari Web Inspector)

```bash
# On device: Settings → Safari → Advanced → Web Inspector (ON)
# On Mac: Safari → Develop → [Device Name] → [App Name]

# In console:
hotUpdate.getVersionInfo(console.log)
hotUpdate.canary('1.0.0', console.log)
```

### Android Testing (Chrome DevTools)

```bash
# 1. Connect device/emulator
adb devices

# 2. Open Chrome: chrome://inspect

# 3. Find WebView and click "inspect"

# 4. In console:
hotUpdate.getVersionInfo(console.log)
hotUpdate.canary('1.0.0', console.log)

# 5. View logs:
adb logcat -s HotUpdates:* -v time
```

## What's New in 2.3.0

### Android Support

Version 2.3.0 adds full Android platform support with the following features:

- Complete Android implementation with 100% iOS API compatibility
- Same JavaScript interface works on both platforms
- No external dependencies (uses built-in java.util.zip)
- Automatic configuration of file scheme and preferences
- ZIP magic bytes validation for security
- WebView cache management (LOAD_NO_CACHE mode)

For complete version history, see [CHANGELOG.md](CHANGELOG.md).

## License

Custom Non-Commercial License - See [LICENSE](LICENSE) file

## Author

**Mustafin Vladimir**
- GitHub: [@vladimirDarksy](https://github.com/vladimirDarksy)
- Email: outvova.gor@gmail.com

## Support

- Issues: https://github.com/vladimirDarksy/Cordova_hot_update/issues
- Repository: https://github.com/vladimirDarksy/Cordova_hot_update
