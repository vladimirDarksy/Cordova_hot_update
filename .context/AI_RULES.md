# AI Development Rules - Cordova Hot Updates Plugin

> **Главный файл правил для работы с проектом**
> Версия: 1.0
> Последнее обновление: 2025-10-27

---

## ⚡ Быстрый старт (TL;DR)

### 🤖 Для AI ассистента (в начале каждой сессии):

1. **Прочитать** `.context/AI_RULES.md` (этот файл)
2. **Найти и прочитать** соответствующий `CONTEXT_{Module}.md` для задачи
3. **Проверить** `git status`
4. **Начать работу** по правилам

### 📝 Для создания нового контекстного файла:

1. **Скопировать** `.context/CONTEXT_TEMPLATE.md`
2. **Переименовать** в `CONTEXT_{Module}_{Feature}.md`
3. **Заполнить** все разделы
4. **Поместить** в `.context/`

---

## 📋 Обязательный Workflow

### 🎯 Начало каждой сессии

**ВСЕГДА выполняйте следующие шаги:**

1. **Прочитать этот файл** (`.context/AI_RULES.md`)
2. **Найти и прочитать соответствующий контекстный файл модуля** из `.context/`
3. **Проверить текущее состояние:**
   ```bash
   git status
   git log -5 --oneline
   ```
4. **Понять текущую задачу** - уточнить у пользователя если неясно

### 🔨 Во время работы

1. **Следовать архитектурным паттернам проекта** (см. раздел Архитектура)
2. **Документировать нетривиальные решения** в коде
3. **Обновлять контекстные файлы** при значительных изменениях
4. **НЕ делать предположений** - спрашивать при неясностях
5. **Тестировать локально** с помощью `npm pack` перед публикацией

### ✅ После завершения задачи

1. **Обновить контекстный файл модуля:**
   - Добавить запись в раздел "История изменений"
   - Обновить описание, если изменилась архитектура
   - Обновить список Known Issues

2. **НЕ публиковать в npm автоматически** (только если пользователь попросил явно)

3. **НЕ создавать коммиты автоматически** (только если пользователь попросил явно)

4. **НЕ создавать Pull Request автоматически** (только если пользователь попросил явно)

---

## 🏗️ Архитектура Проекта

### Платформа и Технологии

- **Платформа:** Cordova Plugin (iOS only в v1.0.0)
- **Языки:** JavaScript (API), Objective-C (Native iOS)
- **iOS Support:** iOS 11.0+
- **Dependencies:** SSZipArchive (via CocoaPods)
- **Distribution:** npm registry

### Структура Проекта

```
Cordova_hot_update/
├── .context/                     # Контекстные файлы для AI
│   ├── AI_RULES.md              # Этот файл
│   ├── CONTEXT_TEMPLATE.md      # Шаблон для контекстных файлов
│   └── CONTEXT_{Module}.md      # Модульные контексты
│
├── www/                          # JavaScript API
│   └── HotUpdates.js            # Cordova exec interface
│
├── src/                          # Native implementations
│   └── ios/
│       ├── HotUpdates.h         # Plugin header
│       └── HotUpdates.m         # Main implementation
│
├── scripts/                      # Cordova hooks
│   ├── beforeInstall.js
│   └── afterInstall.js
│
├── plugin.xml                    # Cordova plugin configuration
├── package.json                  # npm package metadata
├── README.md                     # Documentation
└── LICENSE                       # Custom Non-Commercial License
```

### How It Works (WebView Reload Approach)

```
App Launch
  ↓
Check pending_update/ folder
  ↓
[If exists] → Install to Documents/www → Backup old → Clean pending
  ↓
Load WebView from Documents/www (not bundle)
  ↓
[Background] Check for updates every N minutes
  ↓
[If available] → Download to pending_update/
  ↓
[Next Launch] → Repeat cycle
```

---

## 🎨 Code Style & Conventions

### JavaScript (www/HotUpdates.js)

```javascript
// Cordova style
var exec = require('cordova/exec');

var HotUpdates = {
    methodName: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'HotUpdates', 'methodName', []);
    }
};

module.exports = HotUpdates;
```

### Objective-C (src/ios/)

**Header (.h):**
```objc
#import <Cordova/CDVPlugin.h>

@interface HotUpdates : CDVPlugin {
    NSString *documentsPath;
    NSString *wwwPath;
}

- (void)getCurrentVersion:(CDVInvokedUrlCommand*)command;
// ... other methods
@end
```

**Implementation (.m):**
```objc
- (void)getCurrentVersion:(CDVInvokedUrlCommand*)command {
    [self.commandDelegate runInBackground:^{
        NSString *version = [self getInstalledVersion];

        CDVPluginResult *pluginResult = [CDVPluginResult
            resultWithStatus:CDVCommandStatus_OK
            messageAsString:version];

        [self.commandDelegate sendPluginResult:pluginResult
            callbackId:command.callbackId];
    }];
}
```

**Logging:**
```objc
NSLog(@"[HotUpdates] Info message");
NSLog(@"[HotUpdates] ❌ Error: %@", error.localizedDescription);
NSLog(@"[HotUpdates] ✅ Success: %@", message);
```

### Именование Файлов

- **Контекстные файлы:** `CONTEXT_{Module}_{OptionalFeature}.md`
- **JavaScript files:** `{FeatureName}.js`
- **Objective-C header:** `{PluginName}.h`
- **Objective-C implementation:** `{PluginName}.m`

---

## 📁 File System Layout

### iOS Documents Directory Structure

```
Documents/
├── www/                        # Active updated content (loaded by WebView)
│   ├── index.html
│   ├── js/
│   ├── css/
│   └── ...
│
├── pending_update/             # Downloaded update waiting for installation
│   └── www/                   # New content (will be installed on next launch)
│
└── www_backup/                # Backup of previous version (for rollback)
    └── www/
```

### Bundle vs Documents

- **Bundle www:** `[[NSBundle mainBundle] pathForResource:@"www"]` - Original content
- **Documents www:** `NSDocumentDirectory/www` - Updated content
- **WebView loads from:** Documents www (if exists), fallback to bundle

---

## 🔐 Security & Best Practices

### НИКОГДА:

❌ Не изменять native code структуры без понимания Cordova lifecycle
❌ Не выполнять file operations на main thread (используй `runInBackground`)
❌ Не забывать освобождать resources (NSData, NSFileHandle)
❌ Не логировать sensitive data (server URLs с токенами)
❌ Не использовать force unwrap без проверки

### ВСЕГДА:

✅ Используй `[self.commandDelegate runInBackground:]` для async операций
✅ Проверяй file existence (`[[NSFileManager defaultManager] fileExistsAtPath:]`)
✅ Обрабатывай ошибки (`NSError **error`)
✅ Логируй важные этапы (`NSLog(@"[HotUpdates] ...")`)
✅ Отправляй proper CDVPluginResult (OK, ERROR, KeepCallback)

### Thread Safety

```objc
// ПРАВИЛЬНО: async operations in background
[self.commandDelegate runInBackground:^{
    // File operations, network requests, etc.
}];

// НЕПРАВИЛЬНО: blocking main thread
NSData *data = [NSData dataWithContentsOfURL:url];
```

---

## 📝 Контекстные Файлы

### Принципы Написания Контекстных Файлов

**ГЛАВНОЕ ПРАВИЛО: Краткость и конкретность**

Контекстные файлы должны быть:
- ✅ **Максимально краткими** - только факты и конкретика
- ✅ **Достаточно понятными** - AI должен понять архитектуру и flow
- ❌ **БЕЗ решений, выводов, рекомендаций** - только описание того что ЕСТЬ
- ❌ **БЕЗ подробных объяснений "почему"** - только "что" и "как"
- ❌ **БЕЗ избыточного контекста** - только необходимый минимум

**Формат:**
- Списки вместо абзацев
- ASCII схемы вместо длинных описаний
- Номера строк для быстрого перехода к коду
- Конкретные названия файлов и методов

### Когда Обновлять Контекстный Файл

**ОБЯЗАТЕЛЬНО обновляй при:**
- Изменении архитектуры модуля
- Добавлении/удалении ключевых методов
- Исправлении значительного бага
- Изменении data flow
- Добавлении нового Known Issue

---

## 🚫 Запреты и Ограничения

### Автоматические Действия

**БЕЗ явного запроса пользователя НЕ делай:**

1. ❌ `npm publish`
2. ❌ `npm version`
3. ❌ `git commit`
4. ❌ `git push`
5. ❌ Создание Pull Request
6. ❌ Изменение `plugin.xml` версии
7. ❌ Изменение CocoaPods dependencies

### Создание Файлов

**НЕ создавай файлы без необходимости:**

- ❌ `TODO.md`, `CHANGELOG.md` (если пользователь не попросил)
- ❌ Новые native files без явного разрешения
- ❌ Конфигурационные файлы (`.env`, `config.json`)

**ВСЕГДА предпочитай редактирование существующих файлов созданию новых**

---

## 🧪 Testing & Verification

### Pre-Publish Checklist

```bash
# 1. Verify package structure
npm run verify

# 2. Create test package
npm run pack-test

# 3. Test installation locally
cordova plugin add ./cordova-plugin-hot-updates-*.tgz

# 4. Verify plugin in Cordova
cordova plugin list

# 5. Test on real device (iOS)
cordova run ios --device
```

### Testing with pnpm Projects

If testing in projects that use pnpm:

1. Create `.npmrc` in test project:
   ```
   public-hoist-pattern[]=cordova-plugin-*
   shamefully-hoist=true
   ```

2. Install and test
3. Verify plugin is accessible

---

## 🤔 Workflow: Неясности и Вопросы

### Когда Спрашивать

Если возникают следующие ситуации, **ОСТАНАВЛИВАЙСЯ и спрашивай у пользователя:**

1. **Множественные подходы** - есть несколько валидных решений
2. **Breaking changes** - изменения могут сломать существующий API
3. **Неясные требования** - непонятно что именно нужно сделать
4. **Добавление новых dependencies** - нужна новая библиотека
5. **Изменение публичного API** - методы в HotUpdates.js
6. **iOS версия support** - изменение минимальной версии iOS

---

## 📚 Полезные Ресурсы

### Документация

- **Cordova Plugin Development:** https://cordova.apache.org/docs/en/latest/guide/hybrid/plugins/
- **Cordova iOS Platform:** https://cordova.apache.org/docs/en/latest/guide/platforms/ios/
- **npm Publishing:** https://docs.npmjs.com/cli/v10/commands/npm-publish
- **CocoaPods:** https://cocoapods.org/

### Внутренние Ресурсы

- **Контекстные файлы:** `.context/CONTEXT_*.md`
- **Publishing guide:** `PUBLISHING.md`
- **npm registration:** `NPM_REGISTRATION_GUIDE.md`

---

## 🆘 Troubleshooting Guide

### Plugin Installation Issues

**Problem:** Plugin not found by Cordova CLI
```bash
# Solution: Verify plugin is published to npm
npm view cordova-plugin-hot-updates
```

**Problem:** pnpm + Cordova compatibility
```bash
# Solution: Add to project's .npmrc
public-hoist-pattern[]=cordova-plugin-*
shamefully-hoist=true
```

### iOS Build Issues

**Problem:** CocoaPods not installed
```bash
# Solution: Run pod install
cd platforms/ios
pod install
```

**Problem:** SSZipArchive not found
```bash
# Solution: Check Podfile includes SSZipArchive
# Or run: pod install --repo-update
```

---

**Последнее напоминение:**
Это живой документ. Обновляй его при изменении правил или появлении новых паттернов в проекте.

---

*Версия 1.0 | Создан: 2025-10-27 | Автор: AI Development Team*
