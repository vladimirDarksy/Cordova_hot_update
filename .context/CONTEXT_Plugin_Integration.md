# CONTEXT_Plugin_Integration

> Интеграция с Cordova, npm publication, plugin.xml configuration
> Обновлено: 2025-10-27

---

## Назначение

Описание интеграции плагина с Cordova CLI, npm registry, CocoaPods dependencies, и конфигурации через plugin.xml. Включает процесс публикации и установки.

---

## Ключевые файлы

| Файл | Строки | Назначение |
|------|--------|-----------|
| `plugin.xml` | 1-83 | Cordova plugin specification и dependencies |
| `package.json` | 1-60 | npm package metadata и scripts |
| `scripts/beforeInstall.js` | 1-20 | Pre-install hook |
| `scripts/afterInstall.js` | 1-30 | Post-install hook (CocoaPods reminder) |
| `.npmignore` | 1-70 | Exclude files from npm package |
| `PUBLISHING.md` | 1-250 | Publishing guide |

---

## Архитектура

```
npm Registry (cordova-plugin-hot-updates@1.0.0)
  ↓
cordova plugin add cordova-plugin-hot-updates
  ↓
Cordova CLI reads plugin.xml
  ↓
├── Copy files (www/, src/, scripts/)
├── Update config.xml with <feature>
├── Run hooks (beforeInstall.js, afterInstall.js)
└── CocoaPods podspec processing
    ↓
    cd platforms/ios && pod install
    ↓
    SSZipArchive installed
    ↓
    Ready to build
```

---

## plugin.xml Structure

### Main Configuration (1-22)

```xml
<plugin id="cordova-plugin-hot-updates" version="1.0.0">
    <name>Cordova Hot Updates Plugin</name>
    <description>OTA hot updates using WebView Reload</description>
    <license>Custom Non-Commercial</license>

    <engines>
        <engine name="cordova" version=">=7.0.0" />
        <engine name="cordova-ios" version=">=4.4.0" />
    </engines>
</plugin>
```

### JavaScript Interface (24-27)

```xml
<js-module src="www/HotUpdates.js" name="HotUpdates">
    <clobbers target="HotUpdates" />
</js-module>
```
- Регистрирует `window.HotUpdates` глобально
- Cordova exec bridge

### iOS Platform Configuration (29-71)

**Feature registration (32-37):**
```xml
<config-file target="config.xml" parent="/*">
    <feature name="HotUpdates">
        <param name="ios-package" value="HotUpdates" />
        <param name="onload" value="true" />
    </feature>
</config-file>
```
- `onload="true"` → pluginInitialize вызывается автоматически

**Source files (39-41):**
```xml
<source-file src="src/ios/HotUpdates.h" />
<source-file src="src/ios/HotUpdates.m" />
```

**Frameworks (43-46):**
```xml
<framework src="Foundation.framework" />
<framework src="UIKit.framework" />
<framework src="WebKit.framework" />
```

**CocoaPods (48-56):**
```xml
<podspec>
    <config>
        <source url="https://github.com/CocoaPods/Specs.git"/>
    </config>
    <pods use-frameworks="true">
        <pod name="SSZipArchive" spec="~> 2.4.0"/>
    </pods>
</podspec>
```
- Cordova auto-generates Podfile
- SSZipArchive для unzipping обновлений

**Info.plist (58-64):**
```xml
<edit-config file="*-Info.plist" mode="merge" target="NSAppTransportSecurity">
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</edit-config>
```
- Разрешает HTTP для dev серверов (production должен использовать HTTPS)

**Preferences (66-70):**
```xml
<preference name="hot_updates_server_url" default="https://your-server.com/api/updates" />
<preference name="hot_updates_check_interval" default="300000" />
<preference name="hot_updates_auto_download" default="true" />
<preference name="hot_updates_auto_install" default="true" />
```

### Hooks (79-81)

```xml
<hook type="before_plugin_install" src="scripts/beforeInstall.js" />
<hook type="after_plugin_install" src="scripts/afterInstall.js" />
```

---

## package.json Structure

### Metadata (2-31)

```json
{
  "name": "cordova-plugin-hot-updates",
  "version": "1.0.0",
  "description": "Cordova plugin for automatic OTA hot updates...",
  "license": "SEE LICENSE IN LICENSE",
  "author": {
    "name": "Mustafin Vladimir",
    "email": "outvova.gor@gmail.com"
  }
}
```

### npm Scripts (6-13)

```json
"scripts": {
  "verify": "node -e \"/* verify required files */\"",
  "pack-test": "npm pack && echo 'Test install with: cordova plugin add ./...'",
  "prepublishOnly": "npm run verify"
}
```
- `verify`: Проверка наличия критичных файлов
- `pack-test`: Локальное тестирование
- `prepublishOnly`: Auto-check перед npm publish

### Cordova Metadata (39-43)

```json
"cordova": {
  "id": "cordova-plugin-hot-updates",
  "platforms": ["ios"]
}
```

### Files whitelist (52-59)

```json
"files": [
  "www/",
  "src/",
  "scripts/",
  "plugin.xml",
  "README.md",
  "LICENSE"
]
```
- Контролирует что включается в npm package
- `.npmignore` дополнительно фильтрует

---

## Installation Flow

### Standard Installation

```bash
cordova plugin add cordova-plugin-hot-updates
```

**Steps:**
1. Cordova CLI → npm registry → download package
2. Extract to `plugins/cordova-plugin-hot-updates/`
3. Run `beforeInstall.js` hook
4. Copy files according to `plugin.xml`:
   - `www/HotUpdates.js` → `platforms/ios/www/plugins/...`
   - `src/ios/*` → `platforms/ios/{ProjectName}/Plugins/`
5. Update `config.xml` → add `<feature name="HotUpdates">`
6. Process CocoaPods → update Podfile
7. Run `afterInstall.js` hook → print reminder: "Run: cd platforms/ios && pod install"

### pnpm Project Installation

**Issue:** pnpm hoisting → Cordova CLI не находит plugin

**Solution:** Add to project's `.npmrc`:
```
public-hoist-pattern[]=cordova-plugin-*
shamefully-hoist=true
auto-install-peers=true
```

---

## npm Publication Process

### Publishing (from PUBLISHING.md)

```bash
# 1. Login
npm login

# 2. Verify
npm run verify

# 3. Test
npm publish --dry-run

# 4. Publish
npm publish
```

**Published to:**
- Registry: https://registry.npmjs.org/cordova-plugin-hot-updates
- Page: https://www.npmjs.com/package/cordova-plugin-hot-updates

### Version Update

```bash
# Update version
npm version patch   # 1.0.0 -> 1.0.1
npm version minor   # 1.0.0 -> 1.1.0
npm version major   # 1.0.0 -> 2.0.0

# Publish new version
npm publish
```

---

## Configuration via config.xml

### User Configuration

Add to Cordova project's `config.xml`:

```xml
<widget id="com.example.app" version="1.0.0">
    <!-- Hot Updates Configuration -->
    <preference name="hot_updates_server_url" value="https://updates.myapp.com/api/check" />
    <preference name="hot_updates_check_interval" value="600000" />
    <preference name="hot_updates_auto_download" value="true" />
    <preference name="hot_updates_auto_install" value="true" />
</widget>
```

### Access in Native Code

```objc
// HotUpdates.m:81-107
- (void)loadConfiguration {
    updateServerURL = [self.commandDelegate.settings objectForKey:@"hot_updates_server_url"];
    if (!updateServerURL) {
        updateServerURL = @"https://your-server.com/api/updates"; // Default
    }
    // ...
}
```

---

## Known Issues

### CocoaPods Manual Step Required
- После `cordova plugin add` нужно вручную: `cd platforms/ios && pod install`
- Cordova не выполняет это автоматически
- File: `scripts/afterInstall.js` выводит reminder

### pnpm Hoisting Conflicts
- pnpm по умолчанию не хоистит node_modules
- Cordova CLI ожидает flat structure
- Решение: `.npmrc` в проекте пользователя

### NSAppTransportSecurity (ATS)
- `plugin.xml:58-64` отключает ATS (`NSAllowsArbitraryLoads=true`)
- Security risk для production
- Рекомендация: использовать HTTPS server + убрать эту настройку

### Version Conflicts
- Если плагин обновлён в npm, но не удалён из проекта:
  ```bash
  cordova plugin remove cordova-plugin-hot-updates
  cordova plugin add cordova-plugin-hot-updates
  ```

---

## Testing Checklist

### Pre-Publish Testing

1. **Local package test:**
   ```bash
   npm run pack-test
   cordova plugin add ./cordova-plugin-hot-updates-*.tgz
   ```

2. **iOS build test:**
   ```bash
   cordova build ios
   ```

3. **Device test:**
   ```bash
   cordova run ios --device
   ```

4. **Verify auto-initialization:**
   - Check Xcode console logs: `[HotUpdates] Plugin initialized`

### Post-Publish Testing

1. **Fresh install:**
   ```bash
   cordova plugin add cordova-plugin-hot-updates
   cordova plugin list
   # Should show: cordova-plugin-hot-updates 1.0.0 "Cordova Hot Updates Plugin"
   ```

2. **pnpm project test:**
   - Create `.npmrc`
   - Install plugin
   - Verify `node_modules/cordova-plugin-hot-updates` exists

---

## История изменений

### 2025-10-27
- Плагин опубликован в npm registry (версия 1.0.0)
- Maintainer: muvir
- npm page: https://www.npmjs.com/package/cordova-plugin-hot-updates
- Решена проблема с pnpm + Cordova совместимостью (документирована)
- Создан контекстный файл CONTEXT_Plugin_Integration.md

### 2025-09-22 (Создание)
- Initial plugin.xml configuration
- CocoaPods integration (SSZipArchive)
- npm package structure
- Installation hooks

---

*Версия 1.0 | Обновлён: 2025-10-27*
