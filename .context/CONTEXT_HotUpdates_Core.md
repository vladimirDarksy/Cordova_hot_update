# CONTEXT_HotUpdates_Core

> iOS native implementation для автоматических OTA обновлений через WebView Reload
> Обновлено: 2025-10-27

---

## Назначение

Cordova plugin для iOS, обеспечивающий автоматическое скачивание и установку web content обновлений без обновления через App Store. Использует WebView Reload подход: загружает обновлённый контент из Documents/www вместо bundle.

---

## Ключевые файлы

| Файл | Строки | Назначение |
|------|--------|-----------|
| `src/ios/HotUpdates.h` | 1-182 | Header с объявлениями методов и properties |
| `src/ios/HotUpdates.m` | 1-1000+ | Основная реализация iOS плагина |
| `www/HotUpdates.js` | 1-192 | JavaScript API для Cordova exec |
| `plugin.xml` | 1-83 | Cordova plugin configuration, CocoaPods deps |

---

## Архитектура

```
HotUpdates Plugin
├── Plugin Lifecycle
│   ├── pluginInitialize (48-79)
│   ├── loadConfiguration (81-107)
│   └── initializeWWWFolder (109-149)
│
├── Update Installation
│   ├── checkAndInstallPendingUpdate (151-232)
│   ├── installPendingUpdate (234-317)
│   └── switchToUpdatedContentWithReload (319-408)
│
├── Background Process
│   ├── startBackgroundUpdateProcess (410-432)
│   ├── performAutomaticUpdateCheck (434-511)
│   └── downloadUpdateAutomatically (513-616)
│
├── JavaScript API
│   ├── getCurrentVersion (618-642)
│   ├── getPendingUpdateInfo (644-722)
│   ├── checkForUpdates (724-823)
│   ├── downloadUpdate (825-962)
│   └── getConfiguration (964-997)
│
└── Utilities
    ├── compareVersion (999-1039)
    ├── unzipFile (1041-1075)
    └── NSFileManager helpers
```

---

## Data Models

### Configuration (NSString properties)
```objc
documentsPath: NSString*      // NSDocumentDirectory path
wwwPath: NSString*            // documentsPath/www
updateServerURL: NSString*    // Server endpoint URL
appBundleVersion: NSString*   // CFBundleShortVersionString
checkInterval: NSTimeInterval // Seconds between checks
```

### UserDefaults Keys
```
hot_updates_installed_version: NSString  // Currently installed update version
hot_updates_pending_version: NSString    // Downloaded, awaiting install
hot_updates_has_pending: BOOL            // Pending update flag
```

### Server Response Format
```json
{
  "hasUpdate": true,
  "version": "1.2.0",
  "downloadURL": "https://server.com/updates/v1.2.0.zip",
  "minAppVersion": "1.0.0"
}
```

---

## Data Flow

### Startup Sequence (pluginInitialize)

```
App Launch → pluginInitialize (48-79)
  ↓
loadConfiguration (81-107) → Read config.xml settings
  ↓
checkAndInstallPendingUpdate (151-232)
  ↓
[If pending_update/ exists]
  → unzip to www_backup (backup current)
  → move pending_update/www to Documents/www
  → update UserDefaults
  ↓
initializeWWWFolder (109-149)
  ↓
[If Documents/www doesn't exist]
  → copy Bundle/www → Documents/www
  ↓
switchToUpdatedContentWithReload (319-408)
  ↓
Update CDVViewController.wwwFolderName = Documents/www
  → reloadWebView
  ↓
startBackgroundUpdateProcess (410-432)
  → NSTimer every checkInterval
```

**Files:** `HotUpdates.m:48-432`

### Background Update Check

```
NSTimer fires → performAutomaticUpdateCheck (434-511)
  ↓
GET updateServerURL?version=X&platform=ios
  ↓
Server responds → JSON {hasUpdate, version, downloadURL}
  ↓
[If hasUpdate && version > installedVersion]
  → downloadUpdateAutomatically (513-616)
  ↓
Download ZIP to temp location
  ↓
prepareUpdateForNextLaunch (unzip to pending_update/)
  ↓
Save pending_version to UserDefaults
  ↓
[Next App Launch] → checkAndInstallPendingUpdate
```

**Files:** `HotUpdates.m:434-616`

### Manual Download (from JS)

```
JS: HotUpdates.downloadUpdate(url, version, callbacks)
  ↓
Cordova exec → downloadUpdate:command (825-962)
  ↓
[self.commandDelegate runInBackground:]
  ↓
NSURLSession downloadTask → url
  ↓
Progress callbacks via setProgressCallback (progressCallbacks dict)
  ↓
Download complete → prepareUpdateForNextLaunch
  ↓
CDVPluginResult OK → JavaScript success callback
```

**Files:** `www/HotUpdates.js:129-138`, `HotUpdates.m:825-962`

---

## Ключевые методы

### `pluginInitialize`
`HotUpdates.m:48-79`
- Entry point, вызывается автоматически при загрузке плагина
- Последовательность: config → pending install → init www → switch webview → start timer
- НЕ требует вызова из JavaScript

### `checkAndInstallPendingUpdate`
`HotUpdates.m:151-232`
- Проверяет `Documents/pending_update/` на наличие скачанных обновлений
- Алгоритм:
  1. Backup current www → www_backup
  2. Move pending_update/www → Documents/www
  3. Cleanup pending_update/
  4. Update UserDefaults
- Вызывается на каждом app launch

### `switchToUpdatedContentWithReload`
`HotUpdates.m:319-408`
- Ключевой метод WebView Reload approach
- Логика:
  1. Проверяет `Documents/www/index.html` existence
  2. Получает CDVViewController
  3. Устанавливает `wwwFolderName` = full path to Documents/www
  4. Вызывает `reloadWebView`
- WebView начинает загружать из Documents вместо Bundle

### `compareVersion:withVersion:`
`HotUpdates.m:999-1039`
- Semantic version comparison (X.Y.Z)
- Split по `.`, поэлементное числовое сравнение
- Return: NSOrderedAscending | NSOrderedSame | NSOrderedDescending

### `unzipFile:toDestination:`
`HotUpdates.m:1041-1075`
- Wrapper для SSZipArchive
- Проверка www/ folder в корне ZIP
- Return: BOOL (success/failure)

---

## Thread Safety / Concurrency

**Правила:**
- ВСЕГДА: `[self.commandDelegate runInBackground:]` для async операций
- НИКОГДА: file operations на main thread

**Pattern для JS-вызываемых методов:**
```objc
- (void)methodName:(CDVInvokedUrlCommand*)command {
    [self.commandDelegate runInBackground:^{
        // Async work
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}
```

**NSURLSession:**
```objc
NSURLSession *session = [NSURLSession sharedSession];
NSURLSessionDownloadTask *task = [session downloadTaskWithURL:url
    completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        // Already on background thread
    }];
[task resume];
```

---

## File System Layout

### iOS Documents Structure

```
Documents/
├── www/                         # Active (loaded by WebView)
│   ├── index.html
│   ├── js/
│   ├── css/
│   └── ...
│
├── pending_update/              # Downloaded, awaiting install
│   └── www/
│       └── [new content]
│
└── www_backup/                  # Previous version (rollback support)
    └── www/
        └── [old content]
```

### WebView wwwFolderName

- **Default:** `nil` → loads from `Bundle/www`
- **After update:** `Documents/www` (full path) → loads from Documents

---

## Known Issues

### SSZipArchive CocoaPods Dependency
- Требуется `pod install` после установки плагина
- Может конфликтовать если проект использует другую версию SSZipArchive
- File: `plugin.xml:49-56`

### WebView Reload Timing
- `reloadWebView` вызывается асинхронно
- Может быть race condition если JS выполнится до завершения reload
- Решение: Cordova wait for deviceready

### Version String Format
- Ожидается X.Y.Z (semantic versioning)
- Некорректный формат → сравнение может быть неправильным
- File: `HotUpdates.m:999-1039`

### Background NSTimer Invalidation
- Timer может не invalidate при деинициализации plugin
- Потенциальный memory leak
- Решение: добавить dealloc method

---

## История изменений

### 2025-10-27
- Плагин опубликован в npm registry (версия 1.0.0)
- Создан контекстный файл CONTEXT_HotUpdates_Core.md
- Задокументирована архитектура и key flows

### 2025-09-22 (Создание)
- Initial plugin implementation
- iOS support only
- WebView Reload approach implemented
- Files: `HotUpdates.h`, `HotUpdates.m`, `HotUpdates.js`

---

*Версия 1.0 | Обновлён: 2025-10-27*
