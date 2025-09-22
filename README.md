# Cordova Hot Updates Plugin

🔥 **Automatic over-the-air (OTA) hot updates for Cordova applications using WebView Reload approach**

[![npm version](https://badge.fury.io/js/cordova-plugin-hot-updates.svg)](https://badge.fury.io/js/cordova-plugin-hot-updates)
[![License](https://img.shields.io/badge/License-Custom%20Non--Commercial-blue.svg)](#license)

This plugin enables seamless web content updates for your Cordova iOS applications without requiring App Store approval. Updates are downloaded in the background and applied automatically on the next app launch.

## 🚀 Key Features

- **🔄 Automatic Background Updates**: Continuously checks for and downloads updates
- **⚡ Instant Application**: WebView Reload approach for immediate effect
- **📦 Semantic Versioning**: Smart version comparison and compatibility checks
- **🛡️ Rollback Support**: Automatic fallback on corrupted updates
- **⚙️ Configurable**: Customizable server URLs and check intervals
- **🎯 Zero Configuration**: Works out of the box with sensible defaults

## 📋 Table of Contents

- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Configuration](#-configuration)
- [API Reference](#-api-reference)
- [Server Implementation](#-server-implementation)
- [How It Works](#-how-it-works)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)
- [License](#-license)

## 📦 Installation

```bash
# Install the plugin
cordova plugin add cordova-plugin-hot-updates

# Or install from GitHub
cordova plugin add https://github.com/vladimirDarksy/Cordova_hot_update.git

# Install CocoaPods dependencies (iOS)
cd platforms/ios
pod install
```

## 🚀 Quick Start

### 1. Configure Your Server URL

Add to your `config.xml`:

```xml
<preference name="hot_updates_server_url" value="https://your-server.com/api/updates" />
<preference name="hot_updates_check_interval" value="300000" />
```

### 2. Basic Usage

```javascript
// Check current version
HotUpdates.getCurrentVersion(
  function(version) {
    console.log('Current version:', version);
  },
  function(error) {
    console.error('Error:', error);
  }
);

// Check for pending updates
HotUpdates.getPendingUpdateInfo(
  function(info) {
    if (info.hasPendingUpdate) {
      console.log('Update ready:', info.pendingVersion);
      alert('New update will be applied on next app restart');
    }
  },
  function(error) {
    console.error('Error:', error);
  }
);

// Manually check for updates
HotUpdates.checkForUpdates(
  function(result) {
    if (result.hasUpdate) {
      console.log('Update available:', result.availableVersion);
      // Optionally download manually
      HotUpdates.downloadUpdate(
        result.downloadURL,
        result.availableVersion,
        function() {
          console.log('Download completed');
        },
        function(error) {
          console.error('Download failed:', error);
        }
      );
    }
  },
  function(error) {
    console.error('Check failed:', error);
  }
);
```

## ⚙️ Configuration

### config.xml Preferences

| Preference | Default | Description |
|------------|---------|-------------|
| `hot_updates_server_url` | `https://your-server.com/api/updates` | Update server endpoint |
| `hot_updates_check_interval` | `300000` | Check interval in milliseconds (5 minutes) |
| `hot_updates_auto_download` | `true` | Enable automatic download |
| `hot_updates_auto_install` | `true` | Enable automatic installation on restart |

### Example Configuration

```xml
<widget id="com.yourcompany.yourapp" version="1.0.0">
  <!-- Hot Updates Configuration -->
  <preference name="hot_updates_server_url" value="https://updates.yourapp.com/api/check" />
  <preference name="hot_updates_check_interval" value="600000" />
  <preference name="hot_updates_auto_download" value="true" />
  <preference name="hot_updates_auto_install" value="true" />

  <!-- Your other configurations... -->
</widget>
```

## 📚 API Reference

### Methods

#### `getCurrentVersion(successCallback, errorCallback)`

Gets the currently active version string.

```javascript
HotUpdates.getCurrentVersion(
  function(version) {
    console.log('Current version:', version); // "1.2.3"
  },
  function(error) {
    console.error('Error getting version:', error);
  }
);
```

#### `getPendingUpdateInfo(successCallback, errorCallback)`

Gets information about downloaded updates waiting to be installed.

```javascript
HotUpdates.getPendingUpdateInfo(
  function(info) {
    // info object contains:
    // - hasPendingUpdate: boolean
    // - pendingVersion: string
    // - appBundleVersion: string
    // - installedVersion: string
    // - message: string
  },
  function(error) {
    console.error('Error getting update info:', error);
  }
);
```

#### `checkForUpdates(successCallback, errorCallback)`

Manually triggers an update check.

```javascript
HotUpdates.checkForUpdates(
  function(result) {
    // result object contains:
    // - hasUpdate: boolean
    // - currentVersion: string
    // - availableVersion: string (if hasUpdate is true)
    // - downloadURL: string (if hasUpdate is true)
    // - minAppVersion: string (if specified)
  },
  function(error) {
    console.error('Update check failed:', error);
  }
);
```

#### `downloadUpdate(downloadURL, version, successCallback, errorCallback, progressCallback)`

Manually downloads a specific update.

```javascript
HotUpdates.downloadUpdate(
  'https://server.com/updates/v2.0.0.zip',
  '2.0.0',
  function() {
    console.log('Download completed');
  },
  function(error) {
    console.error('Download failed:', error);
  },
  function(progress) {
    console.log('Download progress:', progress + '%');
  }
);
```

#### `getConfiguration(successCallback, errorCallback)`

Gets the current plugin configuration.

```javascript
HotUpdates.getConfiguration(
  function(config) {
    // config object contains:
    // - serverURL: string
    // - checkInterval: number (milliseconds)
    // - appBundleVersion: string
    // - autoDownload: boolean
  },
  function(error) {
    console.error('Error getting config:', error);
  }
);
```

## 🖥️ Server Implementation

Your update server should implement the following API:

### Check for Updates Endpoint

**GET** `/check?version={currentVersion}&platform=ios`

**Response** (when update available):
```json
{
  "hasUpdate": true,
  "version": "1.2.0",
  "downloadURL": "https://yourserver.com/updates/v1.2.0.zip",
  "minAppVersion": "1.0.0",
  "releaseNotes": "Bug fixes and improvements"
}
```

**Response** (when no update available):
```json
{
  "hasUpdate": false,
  "message": "No updates available"
}
```

### Update Package Format

Your update ZIP file should contain a `www` folder with your web content:

```
update.zip
└── www/
    ├── index.html
    ├── js/
    ├── css/
    ├── img/
    └── ...
```

### Example Server Implementation (Node.js)

```javascript
const express = require('express');
const app = express();

app.get('/api/updates/check', (req, res) => {
  const { version, platform } = req.query;
  const currentVersion = version || '1.0.0';
  const latestVersion = '1.2.0'; // Your latest version

  if (compareVersions(currentVersion, latestVersion) < 0) {
    res.json({
      hasUpdate: true,
      version: latestVersion,
      downloadURL: `https://yourserver.com/updates/v${latestVersion}.zip`,
      minAppVersion: '1.0.0',
      releaseNotes: 'Bug fixes and improvements'
    });
  } else {
    res.json({
      hasUpdate: false,
      message: 'No updates available'
    });
  }
});

function compareVersions(version1, version2) {
  const v1parts = version1.split('.').map(Number);
  const v2parts = version2.split('.').map(Number);

  for (let i = 0; i < Math.max(v1parts.length, v2parts.length); i++) {
    const v1part = v1parts[i] || 0;
    const v2part = v2parts[i] || 0;

    if (v1part < v2part) return -1;
    if (v1part > v2part) return 1;
  }

  return 0;
}

app.listen(3000, () => {
  console.log('Update server running on port 3000');
});
```

## 🔧 How It Works

### WebView Reload Approach

1. **Startup Check**: On app launch, the plugin checks for pending updates
2. **Installation**: If found, updates are installed to `Documents/www`
3. **WebView Switch**: The WebView is configured to load from `Documents/www` instead of bundle
4. **Background Process**: Automatic checking and downloading runs in background
5. **Next Launch**: New updates are applied on next app restart

### File Structure

```
Documents/
├── www/                     # Updated web content (active)
├── pending_update/          # Downloaded update waiting for installation
│   └── www/                 # New web content
└── www_backup/              # Backup of previous version (for rollback)
```

### Update Lifecycle

```
[Bundle] -> [Check] -> [Download] -> [Prepare] -> [Install] -> [Reload]
   ↑                                                             ↓
   └─────────────────── [Next App Launch] ←──────────────────────┘
```

## 🐛 Troubleshooting

### Common Issues

**Updates not downloading**
- Check your server URL in config.xml
- Verify server is returning correct JSON format
- Check device network connectivity
- Enable debugging with `cordova run ios --device --debug`

**WebView not reloading updated content**
- Ensure `Documents/www/index.html` exists
- Check iOS device logs for WebView errors
- Verify ZIP package contains `www` folder

**CocoaPods issues**
- Run `pod install` in `platforms/ios` directory
- Update CocoaPods: `sudo gem install cocoapods`
- Clean and rebuild: `cordova clean ios && cordova build ios`

### Debug Logging

The plugin provides extensive console logging. To view:

```bash
# iOS Simulator
cordova run ios --debug

# iOS Device
# Use Xcode console or Safari Web Inspector
```

### Reset Plugin State

```javascript
// Clear all plugin data (for testing)
localStorage.removeItem('hot_updates_installed_version');
localStorage.removeItem('hot_updates_pending_version');
localStorage.removeItem('hot_updates_has_pending');
```

## ⚠️ Important Notes

- **iOS Only**: Currently supports iOS platform only
- **HTTPS Required**: Update server should use HTTPS in production
- **App Store Compliance**: Only update web content, not native code
- **Testing**: Test thoroughly on real devices before production
- **Rollback**: Keep ability to rollback via App Store if needed

## 📄 Requirements

- **Cordova**: >= 7.0.0
- **cordova-ios**: >= 4.4.0
- **iOS**: >= 11.0
- **CocoaPods**: For SSZipArchive dependency

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the Custom Non-Commercial License - see the [LICENSE](LICENSE) file for details.

**⚠️ Commercial use is strictly prohibited without explicit written permission from the copyright holder.**

For commercial licensing inquiries, please contact: **Mustafin Vladimir**

## 🙋‍♂️ Support

- **Issues**: [GitHub Issues](https://github.com/vladimirDarksy/Cordova_hot_update/issues)
- **Documentation**: This README and inline code documentation
- **Discussions**: [GitHub Discussions](https://github.com/vladimirDarksy/Cordova_hot_update/discussions)

---

**Made with ❤️ by [Mustafin Vladimir](https://github.com/vladimirDarksy)**