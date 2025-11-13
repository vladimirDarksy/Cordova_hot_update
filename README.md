# Cordova Hot Updates Plugin v2.1.2

Frontend-controlled manual hot updates for Cordova iOS applications using WebView Reload approach.

[![npm version](https://badge.fury.io/js/cordova-plugin-hot-updates.svg)](https://badge.fury.io/js/cordova-plugin-hot-updates)
[![License](https://img.shields.io/badge/License-Custom%20Non--Commercial-blue.svg)](#license)

This plugin enables **manual, JavaScript-controlled** web content updates for your Cordova iOS applications without requiring App Store approval. Your frontend code decides when to check, download, and install updates.

## Features

- **Frontend Control**: JavaScript decides when to update (no automatic background checking)
- **Two-Step Updates**: Separate download (`getUpdate`) and install (`forceUpdate`) for better UX
- **Auto-Install on Launch**: If user ignores update prompt, it installs on next app launch
- **Canary System**: Automatic rollback if update fails to load (20-second timeout)
- **IgnoreList**: Tracks problematic versions (information only, does NOT block installation)
- **Instant Effect**: WebView Reload approach - no app restart needed
- **Cache Management**: Clears WKWebView cache (disk, memory, Service Worker) before reload

## Installation

```bash
# Install from npm
cordova plugin add cordova-plugin-hot-updates

# Install CocoaPods dependencies (required)
cd platforms/ios
pod install
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
- Cordova >= 7.0.0
- cordova-ios >= 4.4.0
- iOS >= 11.2
- CocoaPods (for SSZipArchive dependency)

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

```
Documents/
├── www/                    // Active version
├── www_previous/           // Previous version (rollback)
├── pending_update/         // Next launch auto-install
└── temp_downloaded_update/ // Immediate install
```

### Version Management

- **appBundleVersion** - Native app version from Info.plist
- **installedVersion** - Current hot update version
- **previousVersion** - Last working version (rollback)

## Update Server API

Your server should provide:

**Check API:**
```
GET https://your-server.com/api/check-update?version=1.0.0&platform=ios

Response:
{
  "hasUpdate": true,
  "version": "2.0.0",
  "downloadUrl": "https://your-server.com/updates/2.0.0.zip",
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
- Check Xcode console: `[HotUpdates] ...`

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

## Migration from v1.0.0

**Removed methods:**
- `getCurrentVersion()` - Manage in JS
- `getPendingUpdateInfo()` - Not needed
- `checkForUpdates()` - Frontend controls
- `downloadUpdate()` - Use `getUpdate()`
- `installUpdate()` - Use `forceUpdate()`

**New API:**
- `window.hotUpdate.getUpdate({url, version?}, callback)`
- `window.hotUpdate.forceUpdate(callback)`
- `window.hotUpdate.canary(version, callback)`
- `window.hotUpdate.getIgnoreList(callback)`

**Changes:**
- API via `window.hotUpdate` (not `window.HotUpdates`)
- Callback signature: `callback(error)` pattern
- No automatic background checking

## Changelog

### v2.1.2 (2025-11-13)

**Breaking Changes:**
- Changed API from `window.HotUpdates` to `window.hotUpdate`
- Removed automatic update checking
- Simplified to 4 methods: `getUpdate`, `forceUpdate`, `canary`, `getIgnoreList`

**New Features:**
- Frontend-controlled manual updates
- Two-step update flow
- 20-second canary timer
- IgnoreList system
- Auto-install on next launch
- WebView cache clearing

### v1.0.0

- Initial release

## License

Custom Non-Commercial License - See [LICENSE](LICENSE) file

## Author

**Mustafin Vladimir**
- GitHub: [@vladimirDarksy](https://github.com/vladimirDarksy)
- Email: outvova.gor@gmail.com

## Support

- Issues: https://github.com/vladimirDarksy/Cordova_hot_update/issues
- Repository: https://github.com/vladimirDarksy/Cordova_hot_update
