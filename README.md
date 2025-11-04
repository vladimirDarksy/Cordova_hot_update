# Cordova Hot Updates Plugin

🔥 **Frontend-controlled over-the-air (OTA) hot updates for Cordova iOS applications**

[![npm version](https://badge.fury.io/js/cordova-plugin-hot-updates.svg)](https://badge.fury.io/js/cordova-plugin-hot-updates)
[![License](https://img.shields.io/badge/License-Custom%20Non--Commercial-blue.svg)](#license)

This plugin enables **manual, JavaScript-controlled** web content updates for your Cordova iOS applications without requiring App Store approval. Your frontend code decides when to check, download, and install updates.

## ✨ What's New in v2.1.0

- ✅ **Smart Download**: `getUpdate()` won't re-download already installed versions
- ✅ **Cleaner Native Code**: Removed debug logs and emojis for production
- ✅ **Better Documentation**: Complete API docs in `docs/` folder
- ✅ **Bug Fixes**: Fixed duplicate download issues and code cleanup

[See full changelog](CHANGELOG.md)

## 🎯 Key Features

- **🎮 Frontend Control**: Your JavaScript decides when to update (no automatic background checks)
- **⚡ Two-Step Updates**: Separate download and install for better UX
- **🔄 Auto-Install**: If user ignores popup, update installs on next app launch
- **🐦 Canary System**: Automatic rollback if update fails to load (20-second timeout)
- **📋 IgnoreList**: Tracks problematic versions (informational only)
- **🚀 Instant Effect**: WebView Reload approach - no app restart needed

## 📦 Installation

```bash
# Install from npm
cordova plugin add cordova-plugin-hot-updates

# Install CocoaPods dependencies (required)
cd platforms/ios
pod install
```

**Requirements:**
- Cordova >= 7.0.0
- cordova-ios >= 4.4.0
- iOS >= 11.0
- CocoaPods (for SSZipArchive dependency)

## 🚀 Quick Start

### 1. Minimal Integration

```javascript
document.addEventListener('deviceready', function() {
    // STEP 1: Confirm app loaded successfully (REQUIRED on every start!)
    cordova.exec(
        function(info) {
            const currentVersion = info.installedVersion || info.appBundleVersion;

            // This MUST be called within 20 seconds or automatic rollback occurs
            window.HotUpdates.canary(currentVersion, function() {
                console.log('✅ Canary confirmed');
            });

            // STEP 2: Check for updates on YOUR server
            fetch('https://your-api.com/updates/check?version=' + currentVersion)
                .then(r => r.json())
                .then(data => {
                    if (data.hasUpdate) {
                        // STEP 3: Download update
                        window.HotUpdates.getUpdate({
                            url: data.downloadURL,
                            version: data.newVersion
                        }, function(error) {
                            if (error) {
                                console.error('Download failed:', error.error.message);
                                return;
                            }

                            // STEP 4: Show popup
                            if (confirm('Update to ' + data.newVersion + '?')) {
                                // STEP 5: Install immediately
                                window.HotUpdates.forceUpdate(function(error) {
                                    if (error) {
                                        console.error('Install failed:', error.error.message);
                                    }
                                    // WebView reloads automatically
                                });
                            }
                            // If user cancels: update installs automatically on next launch
                        });
                    }
                });
        },
        function(error) {
            console.error('Failed to get version:', error);
        },
        'HotUpdates',
        'getVersionInfo',
        []
    );
});
```

## 📚 API Reference

### Core Methods (v2.1.0)

#### 1. `getUpdate({url, version?}, callback)`

Downloads update in background. **Does NOT install!**

```javascript
window.HotUpdates.getUpdate({
    url: 'https://server.com/updates/2.7.8.zip',
    version: '2.7.8'  // Optional
}, function(error) {
    if (error) {
        console.error('Download failed:', error.error.message);
    } else {
        console.log('✅ Download complete');
    }
});
```

**Features:**
- Returns success if version already installed (won't re-download)
- Saves to two locations: immediate install + auto-install on next launch
- Callback format: `null` on success, `{error: {message}}` on error

#### 2. `forceUpdate(callback)`

Installs downloaded update and reloads WebView. **No parameters needed!**

```javascript
window.HotUpdates.forceUpdate(function(error) {
    if (error) {
        console.error('Install failed:', error.error.message);
    } else {
        console.log('✅ Installed, reloading...');
    }
});
```

**Important:**
- Must call `getUpdate()` first
- WebView reloads automatically after ~1 second
- Call `canary()` after reload to confirm success

#### 3. `canary(version, callback)`

Confirms bundle loaded successfully. **REQUIRED on every app start!**

```javascript
window.HotUpdates.canary('2.7.8', function() {
    console.log('✅ Canary confirmed');
});
```

**Critical:**
- Must be called within 20 seconds after app start
- If not called: automatic rollback to previous version
- Failed version is added to ignore list

#### 4. `getIgnoreList(callback)`

Returns list of versions that caused problems.

```javascript
window.HotUpdates.getIgnoreList(function(result) {
    const badVersions = result.versions; // ["2.7.5", "2.7.6"]

    // Check before downloading
    if (!badVersions.includes(newVersion)) {
        // Safe to download
    }
});
```

**Note:** IgnoreList is informational only - you decide whether to skip versions.

## 🖥️ Server Requirements

Your server should provide:

### Check Endpoint

**GET** `/api/updates/check?version={current}&platform=ios`

```json
{
  "hasUpdate": true,
  "newVersion": "2.7.8",
  "downloadURL": "https://server.com/updates/2.7.8.zip",
  "minAppVersion": "2.7.0"
}
```

### Update Package

ZIP file containing `www` folder:

```
update.zip
└── www/
    ├── index.html
    ├── js/
    ├── css/
    └── ...
```

## 🔧 How It Works

### Two-Step Update Flow

```
1. JS checks YOUR server for updates
2. getUpdate() downloads ZIP in background
3. Show popup to user
4. User clicks "Update": forceUpdate() installs immediately
5. User ignores: update auto-installs on next app launch
6. WebView reloads with new content
7. JS calls canary() to confirm success
```

### Rollback Protection

- 20-second canary timer starts after update
- If `canary()` not called → automatic rollback
- Failed version added to ignore list
- App continues working on previous version

### File Structure

```
Documents/
├── www/                     # Active version
├── www_previous/            # Backup (for rollback)
├── pending_update/          # Next launch auto-install
└── temp_downloaded_update/  # Immediate install
```

## 📖 Full Documentation

- **[docs/README.md](docs/README.md)** - Quick start guide
- **[docs/API.md](docs/API.md)** - Complete API reference
- **[docs/hot-updates-admin.html](docs/hot-updates-admin.html)** - Testing interface
- **[CHANGELOG.md](CHANGELOG.md)** - Version history

## 🐛 Troubleshooting

### Common Issues

**Updates not working**
- Check `canary()` is called on every app start
- Verify server URL returns correct JSON
- Check iOS device logs for errors

**Duplicate downloads**
- ✅ Fixed in v2.1.0! `getUpdate()` now checks installed version

**WebView shows old content**
- ✅ Fixed in v2.1.0! Cache is cleared before reload

**CocoaPods errors**
```bash
cd platforms/ios
pod install
cordova clean ios && cordova build ios
```

### Debug Logs

All plugin actions are logged with `[HotUpdates]` prefix:

```bash
# iOS Simulator
cordova run ios --debug

# iOS Device
# Use Xcode console or Safari Web Inspector
```

## ⚠️ Important Notes

- **iOS Only**: Currently supports iOS platform only
- **Manual Updates Only**: No automatic background checking (you control everything)
- **App Store Compliance**: Only update web content, not native code
- **HTTPS Required**: Update server should use HTTPS in production
- **Testing**: Test rollback mechanism thoroughly

## 🤝 Contributing

Contributions are welcome! Please submit a Pull Request.

## 📝 License

This project is licensed under the Custom Non-Commercial License - see the [LICENSE](LICENSE) file for details.

**⚠️ Commercial use is strictly prohibited without explicit written permission from the copyright holder.**

For commercial licensing inquiries, please contact: **Mustafin Vladimir** <outvova.gor@gmail.com>

## 🙋‍♂️ Support

- **Issues**: [GitHub Issues](https://github.com/vladimirDarksy/Cordova_hot_update/issues)
- **npm**: [cordova-plugin-hot-updates](https://www.npmjs.com/package/cordova-plugin-hot-updates)

---

**Made with ❤️ by [Mustafin Vladimir](https://github.com/vladimirDarksy)**

**Version:** 2.1.1 | **Last Updated:** 2025-11-04
