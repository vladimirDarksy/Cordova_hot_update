/*!
 * @file HotUpdates.m
 * @brief Hot Updates Plugin for Cordova iOS
 * @details Provides automatic background hot updates functionality for Cordova applications.
 *          Downloads and installs web content updates without requiring App Store updates.
 *          
 *          Key Features:
 *          - Automatic background update checking
 *          - Seamless download and installation
 *          - wwwFolderName approach for instant updates
 *          - Configurable update intervals
 *          - Startup update checking
 *          
 * @version 2.0.0
 * @date 2025-10-30
 * @author Mustafin Vladimir
 * @copyright Copyright (c) 2025. All rights reserved.
 */

#import <Cordova/CDV.h>
#import <Cordova/CDVViewController.h>
#import "HotUpdates.h"
#import <SSZipArchive/SSZipArchive.h>

// Storage keys
static NSString * const kInstalledVersion = @"hot_updates_installed_version";
static NSString * const kPendingVersion = @"hot_updates_pending_version";
static NSString * const kHasPending = @"hot_updates_has_pending";
static NSString * const kPreviousVersion = @"hot_updates_previous_version";
static NSString * const kAutoUpdateEnabled = @"hot_updates_auto_update_enabled";
static NSString * const kFirstLaunchDone = @"hot_updates_first_launch_done";
static NSString * const kIgnoreList = @"hot_updates_ignore_list";
static NSString * const kCanaryVersion = @"hot_updates_canary_version";
static NSString * const kDownloadInProgress = @"hot_updates_download_in_progress";

// Directory names
static NSString * const kWWWDirName = @"www";
static NSString * const kPreviousWWWDirName = @"www_previous";
static NSString * const kBackupWWWDirName = @"www_backup";
static NSString * const kPendingUpdateDirName = @"pending_update";

// Добавляем протокол для перехвата URL запросов
@interface HotUpdates ()
{
    BOOL isDownloadingUpdate;
}
@end

@implementation HotUpdates

/*!
 * @brief Initialize the Hot Updates plugin
 * @details Called automatically when the plugin is loaded by Cordova.
 *          Sets up configuration, initializes www folder, and starts background processes.
 */
- (void)pluginInitialize {
    [super pluginInitialize];

    // Получаем пути к директориям
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    documentsPath = [paths objectAtIndex:0];
    wwwPath = [documentsPath stringByAppendingPathComponent:kWWWDirName];
    previousVersionPath = [documentsPath stringByAppendingPathComponent:kPreviousWWWDirName];

    // Загружаем конфигурацию
    [self loadConfiguration];

    // Загрузка настроек автообновлений
    [self loadAutoUpdateSettings];

    // Загрузка ignoreList
    [self loadIgnoreList];

    NSLog(@"[HotUpdates] === STARTUP SEQUENCE ===");
    NSLog(@"[HotUpdates] 📁 Bundle www: %@", [[NSBundle mainBundle] pathForResource:kWWWDirName ofType:nil]);
    NSLog(@"[HotUpdates] 📁 Documents www: %@", wwwPath);
    NSLog(@"[HotUpdates] Auto-update enabled: %@", autoUpdateEnabled ? @"YES" : @"NO");
    NSLog(@"[HotUpdates] First launch done: %@", firstLaunchDone ? @"YES" : @"NO");
    NSLog(@"[HotUpdates] Ignore list: %@", ignoreList);

    // 1. Проверяем и устанавливаем pending updates
    [self checkAndInstallPendingUpdate];

    // 2. Создаем папку www если её нет (копируем из bundle)
    [self initializeWWWFolder];

    // 3. Переключаем WebView на обновленный контент и перезагружаем
    [self switchToUpdatedContentWithReload];

    // 4. Запускаем фоновую проверку ТОЛЬКО если авто-обновления включены И не первый запуск
    if (autoUpdateEnabled && firstLaunchDone) {
        [self startBackgroundUpdateProcess];
    } else {
        NSLog(@"[HotUpdates] Background update process NOT started:");
        NSLog(@"  - Auto-update enabled: %@", autoUpdateEnabled ? @"YES" : @"NO");
        NSLog(@"  - First launch done: %@", firstLaunchDone ? @"YES" : @"NO");
    }

    NSLog(@"[HotUpdates] Plugin initialized.");
}

- (void)loadConfiguration {
    // Получаем все настройки из config.xml
    updateServerURL = [self.commandDelegate.settings objectForKey:@"hot_updates_server_url"];
    if (!updateServerURL) {
        updateServerURL = @"https://your-server.com/api/updates"; // URL по умолчанию
    }
    
    // Получаем версию bundle приложения
    appBundleVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    if (!appBundleVersion) {
        appBundleVersion = @"1.0.0";
    }
    
    // Дополнительные настройки из config.xml
    NSString *checkInterval = [self.commandDelegate.settings objectForKey:@"hot_updates_check_interval"];

    NSLog(@"[HotUpdates] Configuration loaded:");
    NSLog(@"  Server URL: %@", updateServerURL);
    NSLog(@"  App bundle version: %@", appBundleVersion);
    NSLog(@"  Check interval: %@ ms", checkInterval ?: @"60000");
}

/*!
 * @brief Check and install pending updates
 * @details Looks for pending updates and installs them to Documents/www
 */
- (void)checkAndInstallPendingUpdate {
    BOOL hasPendingUpdate = [[NSUserDefaults standardUserDefaults] boolForKey:kHasPending];
    NSString *pendingVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kPendingVersion];
    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];

    if (hasPendingUpdate && pendingVersion && !installedVersion) {
        NSLog(@"[HotUpdates] 🚀 Installing pending update %@ to Documents/www...", pendingVersion);

        // НОВОЕ: Создаем резервную копию текущей версии перед установкой
        [self backupCurrentVersion];

        NSString *pendingUpdatePath = [documentsPath stringByAppendingPathComponent:kPendingUpdateDirName];
        NSString *pendingWwwPath = [pendingUpdatePath stringByAppendingPathComponent:kWWWDirName];
        NSString *documentsWwwPath = [documentsPath stringByAppendingPathComponent:kWWWDirName];

        if ([[NSFileManager defaultManager] fileExistsAtPath:pendingWwwPath]) {
            // Удаляем старую Documents/www
            if ([[NSFileManager defaultManager] fileExistsAtPath:documentsWwwPath]) {
                [[NSFileManager defaultManager] removeItemAtPath:documentsWwwPath error:nil];
            }

            // Копируем pending_update/www в Documents/www
            NSError *copyError = nil;
            BOOL copySuccess = [[NSFileManager defaultManager] copyItemAtPath:pendingWwwPath toPath:documentsWwwPath error:&copyError];

            if (copySuccess) {
                // Помечаем как установленный
                [[NSUserDefaults standardUserDefaults] setObject:pendingVersion forKey:kInstalledVersion];
                [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kHasPending];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPendingVersion];
                [[NSUserDefaults standardUserDefaults] synchronize];

                // Очищаем pending_update папку
                [[NSFileManager defaultManager] removeItemAtPath:pendingUpdatePath error:nil];

                NSLog(@"[HotUpdates] ✅ Update %@ installed successfully", pendingVersion);
            } else {
                NSLog(@"[HotUpdates] ❌ Failed to install update: %@", copyError.localizedDescription);
            }
        }
    }
}

/*!
 * @brief Switch WebView to updated content with reload
 * @details Changes wwwFolderName to Documents/www and reloads WebView if updates are installed
 */
- (void)switchToUpdatedContentWithReload {
    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];

    if (installedVersion) {
        NSString *documentsWwwPath = [documentsPath stringByAppendingPathComponent:kWWWDirName];
        NSString *indexPath = [documentsWwwPath stringByAppendingPathComponent:@"index.html"];

        // Проверяем, что файлы действительно существуют
        if ([[NSFileManager defaultManager] fileExistsAtPath:indexPath]) {
            NSLog(@"[HotUpdates] 🎯 WEBVIEW RELOAD APPROACH!");
            NSLog(@"[HotUpdates] Found installed update version: %@", installedVersion);

            // Устанавливаем новый путь
            ((CDVViewController *)self.viewController).wwwFolderName = documentsWwwPath;
            NSLog(@"[HotUpdates] ✅ Changed wwwFolderName to: %@", documentsWwwPath);

            // Принудительно перезагружаем WebView для применения нового пути
            [self reloadWebView];

            NSLog(@"[HotUpdates] 📱 WebView reloaded with updated content (version: %@)", installedVersion);
        } else {
            NSLog(@"[HotUpdates] ❌ Documents/www/index.html not found, keeping bundle www");
        }
    } else {
        NSLog(@"[HotUpdates] No installed updates, using bundle www");
    }
}

/*!
 * @brief Force reload the WebView
 * @details Uses WKWebView loadFileURL with proper sandbox permissions
 */
- (void)clearWebViewCache {
    NSLog(@"[HotUpdates] 🗑️ Clearing WebView cache...");

    NSSet *websiteDataTypes = [NSSet setWithArray:@[
        WKWebsiteDataTypeDiskCache,
        WKWebsiteDataTypeMemoryCache,
        WKWebsiteDataTypeOfflineWebApplicationCache,
        WKWebsiteDataTypeServiceWorkerRegistrations
    ]];

    NSDate *dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
    [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:websiteDataTypes
                                               modifiedSince:dateFrom
                                           completionHandler:^{
        NSLog(@"[HotUpdates] ✅ WebView cache cleared");
    }];
}

- (void)reloadWebView {
    // Приводим к типу CDVViewController для доступа к webViewEngine
    if ([self.viewController isKindOfClass:[CDVViewController class]]) {
        CDVViewController *cdvViewController = (CDVViewController *)self.viewController;

        // Строим новый URL для обновленного контента
        NSString *documentsWwwPath = [documentsPath stringByAppendingPathComponent:kWWWDirName];
        NSString *indexPath = [documentsWwwPath stringByAppendingPathComponent:@"index.html"];
        NSURL *fileURL = [NSURL fileURLWithPath:indexPath];
        NSURL *allowReadAccessToURL = [NSURL fileURLWithPath:documentsWwwPath];

        NSLog(@"[HotUpdates] 🔄 Loading WebView with new URL: %@", fileURL.absoluteString);

        id webViewEngine = cdvViewController.webViewEngine;
        if (webViewEngine && [webViewEngine respondsToSelector:@selector(engineWebView)]) {
            // Получаем WKWebView
            WKWebView *webView = [webViewEngine performSelector:@selector(engineWebView)];

            if (webView && [webView isKindOfClass:[WKWebView class]]) {
                // Используем loadFileURL:allowingReadAccessToURL: для правильных sandbox permissions
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Этот метод правильно настраивает sandbox для локальных файлов
                    [webView loadFileURL:fileURL allowingReadAccessToURL:allowReadAccessToURL];
                    NSLog(@"[HotUpdates] ✅ WebView loadFileURL executed with sandbox permissions");
                });
            } else {
                NSLog(@"[HotUpdates] ❌ Could not access WKWebView for reload");
            }
        } else {
            NSLog(@"[HotUpdates] ❌ WebView engine not available for reload");
        }
    } else {
        NSLog(@"[HotUpdates] ❌ ViewController is not CDVViewController type");
    }
}


- (void)initializeWWWFolder {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Проверяем, существует ли папка www в Documents
    if (![fileManager fileExistsAtPath:wwwPath]) {
        NSLog(@"[HotUpdates] WWW folder not found in Documents. Creating and copying from bundle...");
        
        // Копируем содержимое www из bundle в Documents
        NSString *bundleWWWPath = [[NSBundle mainBundle] pathForResource:@"www" ofType:nil];
        if (bundleWWWPath) {
            NSError *error;
            [fileManager copyItemAtPath:bundleWWWPath toPath:wwwPath error:&error];
            if (error) {
                NSLog(@"[HotUpdates] ❌ Error copying www folder: %@", error.localizedDescription);
            } else {
                NSLog(@"[HotUpdates] WWW folder copied successfully to Documents");
            }
        } else {
            NSLog(@"[HotUpdates] ❌ Error: Bundle www folder not found");
        }
    } else {
        NSLog(@"[HotUpdates] WWW folder already exists in Documents");
    }
}


- (void)getCurrentVersion:(CDVInvokedUrlCommand*)command {
    // Возвращаем актуальную версию (установленное обновление или bundle версию)
    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
    NSString *actualVersion = installedVersion ?: appBundleVersion;

    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:actualVersion];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}



- (BOOL)unzipFile:(NSString*)zipPath toDestination:(NSString*)destination {
    NSLog(@"[HotUpdates] 📦 Unzipping %@ to %@", zipPath, destination);
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    
    // Создаем папку назначения если её нет
    if (![fileManager fileExistsAtPath:destination]) {
        [fileManager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"[HotUpdates] ❌ Error creating destination directory: %@", error.localizedDescription);
            return NO;
        }
    }
    
    // 🚀 РАСПАКОВКА ZIP АРХИВА с SSZipArchive
    NSLog(@"[HotUpdates] 📦 Extracting ZIP archive using SSZipArchive library...");
    
    // Простая проверка файла
    if (![[NSFileManager defaultManager] fileExistsAtPath:zipPath]) {
        NSLog(@"[HotUpdates] ❌ ZIP file does not exist: %@", zipPath);
        return NO;
    }
    
    // Создаем временную папку для распаковки
    NSString *tempExtractPath = [destination stringByAppendingPathComponent:@"temp_extract"];
    
    // Удаляем существующую временную папку
    if ([[NSFileManager defaultManager] fileExistsAtPath:tempExtractPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:tempExtractPath error:nil];
    }
    
    // Создаем временную папку
    if (![[NSFileManager defaultManager] createDirectoryAtPath:tempExtractPath withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"[HotUpdates] ❌ Failed to create temp extraction folder: %@", error.localizedDescription);
        return NO;
    }
    
    NSLog(@"[HotUpdates] 📦 Extracting to temp location: %@", tempExtractPath);
    
    // Распаковываем ZIP архив
    BOOL extractSuccess = [SSZipArchive unzipFileAtPath:zipPath toDestination:tempExtractPath];
    
    if (extractSuccess) {
        NSLog(@"[HotUpdates] ✅ ZIP extraction successful!");
        
        // Проверяем содержимое распакованного архива
        NSArray *extractedContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tempExtractPath error:nil];
        NSLog(@"[HotUpdates] 📂 Extracted contents: %@", extractedContents);
        
        // Ищем папку www в распакованном содержимом
        NSString *wwwSourcePath = nil;
        for (NSString *item in extractedContents) {
            NSString *itemPath = [tempExtractPath stringByAppendingPathComponent:item];
            BOOL isDirectory;
            if ([[NSFileManager defaultManager] fileExistsAtPath:itemPath isDirectory:&isDirectory] && isDirectory) {
                if ([item isEqualToString:@"www"]) {
                    wwwSourcePath = itemPath;
                    break;
                }
                // Проверяем, есть ли www внутри папки
                NSString *nestedWwwPath = [itemPath stringByAppendingPathComponent:@"www"];
                if ([[NSFileManager defaultManager] fileExistsAtPath:nestedWwwPath]) {
                    wwwSourcePath = nestedWwwPath;
                    break;
                }
            }
        }
        
        if (wwwSourcePath) {
            NSLog(@"[HotUpdates] 📁 Found www folder at: %@", wwwSourcePath);
            
            // Копируем www папку в финальное место
            NSString *finalWwwPath = [destination stringByAppendingPathComponent:@"www"];
            
            // Удаляем существующую папку www если есть
            if ([[NSFileManager defaultManager] fileExistsAtPath:finalWwwPath]) {
                [[NSFileManager defaultManager] removeItemAtPath:finalWwwPath error:nil];
            }
            
            // Копируем новую www папку
            NSError *copyError = nil;
            BOOL copySuccess = [[NSFileManager defaultManager] copyItemAtPath:wwwSourcePath toPath:finalWwwPath error:&copyError];
            
            if (copySuccess) {
                NSLog(@"[HotUpdates] ✅ www folder copied successfully to: %@", finalWwwPath);
                
                // Очищаем временную папку
                [[NSFileManager defaultManager] removeItemAtPath:tempExtractPath error:nil];
                
                NSLog(@"[HotUpdates] 🎉 ZIP extraction completed successfully!");
                return YES;
            } else {
                NSLog(@"[HotUpdates] ❌ Error copying www folder: %@", copyError.localizedDescription);
            }
        } else {
            NSLog(@"[HotUpdates] ❌ www folder not found in ZIP archive");
            NSLog(@"[HotUpdates] Available contents: %@", extractedContents);
        }
        
        // Очищаем временную папку при ошибке
        [[NSFileManager defaultManager] removeItemAtPath:tempExtractPath error:nil];
    } else {
        NSLog(@"[HotUpdates] ❌ Failed to extract ZIP archive");
        // Очищаем временную папку при ошибке
        [[NSFileManager defaultManager] removeItemAtPath:tempExtractPath error:nil];
    }
    
    NSLog(@"[HotUpdates] ❌ ZIP extraction failed");
    return NO;
}


- (void)getPendingUpdateInfo:(CDVInvokedUrlCommand*)command {
    BOOL hasPending = [[NSUserDefaults standardUserDefaults] boolForKey:kHasPending];

    if (hasPending) {
        NSString *pendingVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kPendingVersion];
        NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
        
        NSDictionary *result = @{
            @"hasPendingUpdate": @YES,
            @"pendingVersion": pendingVersion ?: @"unknown",
            @"appBundleVersion": appBundleVersion,
            @"installedVersion": installedVersion ?: appBundleVersion,
            @"message": @"Update ready for next app launch"
        };
        
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    } else {
        NSDictionary *result = @{
            @"hasPendingUpdate": @NO,
            @"appBundleVersion": appBundleVersion,
            @"message": @"No pending updates"
        };
        
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

#pragma mark - Settings Management

- (void)loadAutoUpdateSettings {
    // По умолчанию автообновления ВЫКЛЮЧЕНЫ
    if (![[NSUserDefaults standardUserDefaults] objectForKey:kAutoUpdateEnabled]) {
        autoUpdateEnabled = NO;
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kAutoUpdateEnabled];
    } else {
        autoUpdateEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kAutoUpdateEnabled];
    }

    firstLaunchDone = [[NSUserDefaults standardUserDefaults] boolForKey:kFirstLaunchDone];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)isAutoUpdateEnabled {
    return autoUpdateEnabled;
}

- (void)setAutoUpdateEnabledInternal:(BOOL)enabled {
    autoUpdateEnabled = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kAutoUpdateEnabled];
    [[NSUserDefaults standardUserDefaults] synchronize];

    if (enabled && !updateCheckTimer) {
        [self startBackgroundUpdateProcess];
    } else if (!enabled && updateCheckTimer) {
        [updateCheckTimer invalidate];
        updateCheckTimer = nil;
    }
}

- (BOOL)isFirstLaunch {
    return !firstLaunchDone;
}

- (void)markFirstLaunchComplete {
    firstLaunchDone = YES;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kFirstLaunchDone];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// JS API
- (void)setAutoUpdateEnabled:(CDVInvokedUrlCommand*)command {
    BOOL enabled = [[command.arguments objectAtIndex:0] boolValue];

    [self setAutoUpdateEnabledInternal:enabled];

    NSDictionary *result = @{
        @"success": @YES,
        @"autoUpdateEnabled": @(enabled)
    };

    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                  messageAsDictionary:result];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)loadIgnoreList {
    NSArray *savedList = [[NSUserDefaults standardUserDefaults] arrayForKey:kIgnoreList];
    ignoreList = savedList ? [savedList mutableCopy] : [NSMutableArray array];
}

- (NSArray*)getIgnoreList {
    return [ignoreList copy];
}

- (void)saveIgnoreList {
    [[NSUserDefaults standardUserDefaults] setObject:ignoreList forKey:kIgnoreList];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)addVersionToIgnoreList:(NSString*)version {
    if (version && ![ignoreList containsObject:version]) {
        [ignoreList addObject:version];
        [self saveIgnoreList];
        NSLog(@"[HotUpdates] Added version %@ to ignore list", version);
    }
}

- (void)removeVersionFromIgnoreList:(NSString*)version {
    if (version && [ignoreList containsObject:version]) {
        [ignoreList removeObject:version];
        [self saveIgnoreList];
        NSLog(@"[HotUpdates] Removed version %@ from ignore list", version);
    }
}

- (BOOL)isVersionIgnored:(NSString*)version {
    return [ignoreList containsObject:version];
}

// JS API
- (void)addToIgnoreList:(CDVInvokedUrlCommand*)command {
    NSString *version = [command.arguments objectAtIndex:0];

    if (!version || version.length == 0) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                    messageAsString:@"Version required"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    [self addVersionToIgnoreList:version];

    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                             messageAsDictionary:@{
        @"success": @YES,
        @"version": version,
        @"ignoreList": [self getIgnoreList]
    }];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)removeFromIgnoreList:(CDVInvokedUrlCommand*)command {
    NSString *version = [command.arguments objectAtIndex:0];
    [self removeVersionFromIgnoreList:version];

    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                             messageAsDictionary:@{
        @"success": @YES,
        @"ignoreList": [self getIgnoreList]
    }];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)clearIgnoreList:(CDVInvokedUrlCommand*)command {
    [ignoreList removeAllObjects];
    [self saveIgnoreList];

    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                             messageAsDictionary:@{
        @"success": @YES
    }];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)getIgnoreListJS:(CDVInvokedUrlCommand*)command {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                               messageAsArray:[self getIgnoreList]];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

#pragma mark - Rollback Mechanism

- (void)savePreviousVersion:(NSString*)version {
    if (!version) return;

    [[NSUserDefaults standardUserDefaults] setObject:version forKey:kPreviousVersion];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSLog(@"[HotUpdates] Saved previous version: %@", version);
}

- (NSString*)getPreviousVersion {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kPreviousVersion];
}

- (void)backupCurrentVersion {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // Если текущая www папка существует
    if ([fileManager fileExistsAtPath:wwwPath]) {
        // Удаляем старую резервную копию
        if ([fileManager fileExistsAtPath:previousVersionPath]) {
            [fileManager removeItemAtPath:previousVersionPath error:nil];
        }

        // Копируем текущую www в www_previous
        NSError *error = nil;
        BOOL success = [fileManager copyItemAtPath:wwwPath
                                            toPath:previousVersionPath
                                             error:&error];

        if (success) {
            NSString *currentVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
            [self savePreviousVersion:currentVersion ?: appBundleVersion];
            NSLog(@"[HotUpdates] ✅ Backed up version: %@", currentVersion ?: appBundleVersion);
        } else {
            NSLog(@"[HotUpdates] ❌ Backup failed: %@", error.localizedDescription);
        }
    }
}

- (BOOL)rollbackToPreviousVersion {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *currentVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
    NSString *previousVersion = [self getPreviousVersion];

    NSLog(@"[HotUpdates] 🔄 Rollback: %@ → %@", currentVersion ?: @"bundle", previousVersion ?: @"nil");

    // Проверка: нет previousVersion
    if (!previousVersion || previousVersion.length == 0) {
        NSLog(@"[HotUpdates] ❌ Rollback failed: no previous version");
        return NO;
    }

    // Проверка: папка не существует
    if (![fileManager fileExistsAtPath:previousVersionPath]) {
        NSLog(@"[HotUpdates] ❌ Rollback failed: previous version folder not found");
        return NO;
    }

    // Проверка: previous = current (защита от цикла)
    NSString *effectiveCurrentVersion = currentVersion ?: appBundleVersion;
    if ([previousVersion isEqualToString:effectiveCurrentVersion]) {
        NSLog(@"[HotUpdates] ❌ Rollback failed: cannot rollback to same version");
        return NO;
    }

    // Создаем временную резервную копию текущей
    NSString *tempBackupPath = [documentsPath stringByAppendingPathComponent:kBackupWWWDirName];
    if ([fileManager fileExistsAtPath:tempBackupPath]) {
        [fileManager removeItemAtPath:tempBackupPath error:nil];
    }

    NSError *error = nil;

    // Бэкапим текущую версию
    if ([fileManager fileExistsAtPath:wwwPath]) {
        [fileManager moveItemAtPath:wwwPath toPath:tempBackupPath error:&error];
        if (error) {
            NSLog(@"[HotUpdates] ❌ Rollback failed: cannot backup current version");
            return NO;
        }
    }

    // Копируем предыдущую версию
    BOOL success = [fileManager copyItemAtPath:previousVersionPath
                                        toPath:wwwPath
                                         error:&error];

    if (success) {
        // Обновляем метаданные (previousVersion очищается для предотвращения циклов)
        [[NSUserDefaults standardUserDefaults] setObject:previousVersion forKey:kInstalledVersion];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPreviousVersion];
        [[NSUserDefaults standardUserDefaults] synchronize];

        // Очищаем временный бэкап
        [fileManager removeItemAtPath:tempBackupPath error:nil];

        NSLog(@"[HotUpdates] ✅ Rollback successful: %@ → %@", currentVersion, previousVersion);

        // Добавляем проблемную версию в ignoreList
        if (currentVersion) {
            [self addVersionToIgnoreList:currentVersion];
        }

        return YES;
    } else {
        NSLog(@"[HotUpdates] ❌ Rollback failed: %@", error.localizedDescription);

        // Восстанавливаем текущую версию
        if ([fileManager fileExistsAtPath:tempBackupPath]) {
            [fileManager moveItemAtPath:tempBackupPath toPath:wwwPath error:nil];
        }

        return NO;
    }
}

// JS API
- (void)rollback:(CDVInvokedUrlCommand*)command {
    BOOL success = [self rollbackToPreviousVersion];

    if (success) {
        // ВАЖНО: Очищаем кэш WebView перед reload
        [self clearWebViewCache];

        // Перезагружаем WebView с откаченной версией
        [self reloadWebView];

        NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                 messageAsDictionary:@{
            @"success": @YES,
            @"version": installedVersion ?: appBundleVersion,
            @"message": @"Rollback successful, WebView reloaded",
            @"canRollbackAgain": @NO  // После rollback previousVersion очищен
        }];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    } else {
        // ========== ДЕТАЛЬНЫЕ ОШИБКИ ДЛЯ JAVASCRIPT ==========
        NSString *currentVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
        NSString *previousVersion = [self getPreviousVersion];
        NSString *effectiveCurrentVersion = currentVersion ?: appBundleVersion;
        NSString *errorReason = @"Unknown error";
        NSString *errorCode = @"rollback_failed";

        // Определяем причину ошибки
        if (!previousVersion || previousVersion.length == 0) {
            errorReason = @"No previous version available";
            errorCode = @"no_previous_version";
        } else if (![[NSFileManager defaultManager] fileExistsAtPath:previousVersionPath]) {
            errorReason = @"Previous version files not found";
            errorCode = @"previous_files_missing";
        } else if ([previousVersion isEqualToString:effectiveCurrentVersion]) {
            errorReason = @"Cannot rollback to the same version";
            errorCode = @"same_version";
        } else {
            errorReason = @"File operation failed during rollback";
            errorCode = @"file_operation_failed";
        }

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"success": @NO,
            @"error": errorCode,
            @"message": errorReason,
            @"currentVersion": effectiveCurrentVersion,
            @"previousVersion": previousVersion ?: [NSNull null],
            @"canRollback": @([[NSFileManager defaultManager] fileExistsAtPath:previousVersionPath]),
            @"hasPreviousMetadata": @(previousVersion != nil && previousVersion.length > 0)
        }];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }
}

#pragma mark - Force Update

- (void)forceUpdate:(CDVInvokedUrlCommand*)command {
    NSDictionary *updateData = [command.arguments objectAtIndex:0];

    if (!updateData) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                    messageAsString:@"Update data required"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    NSString *downloadURL = [updateData objectForKey:@"url"];
    NSString *newVersion = [updateData objectForKey:@"version"];
    NSString *minAppVersion = [updateData objectForKey:@"minAppVersion"];

    if (!downloadURL || !newVersion) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                    messageAsString:@"URL and version required"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    NSLog(@"[HotUpdates] 🚀 Force update requested: %@", newVersion);

    // Проверка: версия уже установлена
    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
    NSString *currentVersion = installedVersion ?: appBundleVersion;

    if ([newVersion isEqualToString:currentVersion]) {
        NSLog(@"[HotUpdates] ⚠️ Version %@ is already installed, skipping", newVersion);

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"status": @"error",
            @"error": @"version_already_installed",
            @"message": [NSString stringWithFormat:@"Version %@ is already installed", newVersion],
            @"currentVersion": currentVersion,
            @"requestedVersion": newVersion
        }];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    // Проверяем ignoreList
    if ([self isVersionIgnored:newVersion]) {
        NSLog(@"[HotUpdates] ⚠️ Version %@ is in ignore list, skipping", newVersion);
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"error": @"version_ignored",
            @"message": [NSString stringWithFormat:@"Version %@ is in ignore list", newVersion],
            @"version": newVersion
        }];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    // Проверяем minAppVersion если указан
    if (minAppVersion) {
        NSComparisonResult comparison = [self compareVersion:appBundleVersion withVersion:minAppVersion];
        if (comparison == NSOrderedAscending) {
            NSString *errorMsg = [NSString stringWithFormat:
                @"Update requires app version %@ but current is %@", minAppVersion, appBundleVersion];
            NSLog(@"[HotUpdates] ❌ %@", errorMsg);

            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                     messageAsDictionary:@{
                @"error": @"version_incompatible",
                @"message": errorMsg,
                @"requiredVersion": minAppVersion,
                @"currentVersion": appBundleVersion
            }];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            return;
        }
    }

    // Проверяем, не скачивается ли уже обновление
    if (isDownloadingUpdate) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                    messageAsString:@"Download already in progress"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    // Запускаем загрузку с callback
    [self downloadUpdateWithCallback:downloadURL
                            version:newVersion
                         callbackId:command.callbackId];
}

- (void)downloadUpdateWithCallback:(NSString*)downloadURL
                           version:(NSString*)newVersion
                        callbackId:(NSString*)callbackId {

    isDownloadingUpdate = YES;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kDownloadInProgress];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSLog(@"[HotUpdates] 📥 Starting force update download for version %@", newVersion);
    NSLog(@"[HotUpdates] Download URL: %@", downloadURL);

    // Отправляем промежуточный результат о начале загрузки
    CDVPluginResult* progressResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                     messageAsDictionary:@{
        @"status": @"downloading",
        @"version": newVersion,
        @"message": @"Download started"
    }];
    [progressResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:progressResult callbackId:callbackId];

    NSURL *url = [NSURL URLWithString:downloadURL];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 60.0;
    config.timeoutIntervalForResource = 300.0;

    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:url
                                                        completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        self->isDownloadingUpdate = NO;
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kDownloadInProgress];
        [[NSUserDefaults standardUserDefaults] synchronize];

        if (error) {
            NSLog(@"[HotUpdates] ❌ Force update download failed: %@", error.localizedDescription);

            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                     messageAsDictionary:@{
                @"status": @"error",
                @"error": @"download_failed",
                @"message": error.localizedDescription
            }];
            [self.commandDelegate sendPluginResult:result callbackId:callbackId];
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSLog(@"[HotUpdates] ❌ Force update download failed: HTTP %ld", (long)httpResponse.statusCode);

            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                     messageAsDictionary:@{
                @"status": @"error",
                @"error": @"http_error",
                @"message": [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]
            }];
            [self.commandDelegate sendPluginResult:result callbackId:callbackId];
            return;
        }

        NSLog(@"[HotUpdates] ✅ Force update download completed");

        // Отправляем статус об окончании загрузки
        CDVPluginResult* downloadedResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                         messageAsDictionary:@{
            @"status": @"downloaded",
            @"version": newVersion,
            @"message": @"Download completed, installing..."
        }];
        [downloadedResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:downloadedResult callbackId:callbackId];

        // Устанавливаем обновление немедленно
        [self installUpdateImmediately:location
                              version:newVersion
                           callbackId:callbackId];
    }];

    [downloadTask resume];
}

- (void)installUpdateImmediately:(NSURL*)updateLocation
                         version:(NSString*)newVersion
                      callbackId:(NSString*)callbackId {

    NSLog(@"[HotUpdates] 🔧 Installing force update %@ immediately...", newVersion);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;

    // Создаем временную папку для распаковки
    NSString *tempUpdatePath = [documentsPath stringByAppendingPathComponent:@"temp_force_update"];

    // Удаляем старую временную папку
    if ([fileManager fileExistsAtPath:tempUpdatePath]) {
        [fileManager removeItemAtPath:tempUpdatePath error:nil];
    }

    // Создаем новую временную папку
    [fileManager createDirectoryAtPath:tempUpdatePath
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:&error];

    if (error) {
        NSLog(@"[HotUpdates] ❌ Error creating temp directory: %@", error);
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"status": @"error",
            @"error": @"install_failed",
            @"message": @"Cannot create temp directory"
        }];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }

    // Распаковываем обновление
    BOOL unzipSuccess = [self unzipFile:updateLocation.path toDestination:tempUpdatePath];

    if (!unzipSuccess) {
        NSLog(@"[HotUpdates] ❌ Failed to unzip update");
        [fileManager removeItemAtPath:tempUpdatePath error:nil];

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"status": @"error",
            @"error": @"unzip_failed",
            @"message": @"Failed to extract update package"
        }];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }

    // Проверяем наличие www папки
    NSString *tempWwwPath = [tempUpdatePath stringByAppendingPathComponent:kWWWDirName];
    if (![fileManager fileExistsAtPath:tempWwwPath]) {
        NSLog(@"[HotUpdates] ❌ www folder not found in update package");
        [fileManager removeItemAtPath:tempUpdatePath error:nil];

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"status": @"error",
            @"error": @"invalid_package",
            @"message": @"www folder not found in package"
        }];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }

    // ВАЖНО: Создаем резервную копию текущей версии
    [self backupCurrentVersion];

    // Удаляем текущую www
    if ([fileManager fileExistsAtPath:wwwPath]) {
        [fileManager removeItemAtPath:wwwPath error:nil];
    }

    // Перемещаем новую версию
    BOOL moveSuccess = [fileManager moveItemAtPath:tempWwwPath
                                            toPath:wwwPath
                                             error:&error];

    if (!moveSuccess) {
        NSLog(@"[HotUpdates] ❌ Failed to install update: %@", error);
        [fileManager removeItemAtPath:tempUpdatePath error:nil];

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"status": @"error",
            @"error": @"install_failed",
            @"message": error.localizedDescription
        }];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }

    // Обновляем метаданные
    [[NSUserDefaults standardUserDefaults] setObject:newVersion forKey:kInstalledVersion];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // Очищаем временную папку
    [fileManager removeItemAtPath:tempUpdatePath error:nil];

    NSLog(@"[HotUpdates] ✅ Force update %@ installed successfully!", newVersion);

    // Отправляем финальный результат ПЕРЕД перезагрузкой
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                             messageAsDictionary:@{
        @"status": @"installed",
        @"version": newVersion,
        @"message": @"Update installed successfully, WebView reloading"
    }];
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];

    // Перезагружаем WebView с новым контентом
    [self reloadWebView];
}

#pragma mark - Canary

- (void)canary:(CDVInvokedUrlCommand*)command {
    NSString *canaryVersion = [command.arguments objectAtIndex:0];

    if (!canaryVersion || canaryVersion.length == 0) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                    messageAsString:@"Version required"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    NSLog(@"[HotUpdates] 🐦 Canary called for version: %@", canaryVersion);

    // Сохраняем canary версию
    [[NSUserDefaults standardUserDefaults] setObject:canaryVersion forKey:kCanaryVersion];
    [[NSUserDefaults standardUserDefaults] synchronize];

    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                             messageAsDictionary:@{
        @"success": @YES,
        @"canaryVersion": canaryVersion,
        @"message": @"Canary version confirmed"
    }];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

#pragma mark - Information Methods

- (void)getVersionInfo:(CDVInvokedUrlCommand*)command {
    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
    NSString *previousVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kPreviousVersion];
    NSString *pendingVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kPendingVersion];
    NSString *canaryVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kCanaryVersion];
    BOOL hasPending = [[NSUserDefaults standardUserDefaults] boolForKey:kHasPending];
    BOOL downloadInProgress = [[NSUserDefaults standardUserDefaults] boolForKey:kDownloadInProgress];

    // Проверяем возможность rollback (папка + metadata + разные версии)
    BOOL previousFolderExists = [[NSFileManager defaultManager] fileExistsAtPath:previousVersionPath];
    BOOL hasPreviousMetadata = (previousVersion != nil && previousVersion.length > 0);
    NSString *currentVersion = installedVersion ?: appBundleVersion;
    BOOL versionsAreDifferent = (previousVersion && ![previousVersion isEqualToString:currentVersion]);
    BOOL canActuallyRollback = previousFolderExists && hasPreviousMetadata && versionsAreDifferent;

    NSDictionary *versionInfo = @{
        @"appBundleVersion": appBundleVersion,
        @"installedVersion": installedVersion ?: appBundleVersion,
        @"previousVersion": previousVersion ?: [NSNull null],
        @"pendingVersion": hasPending ? (pendingVersion ?: @"unknown") : [NSNull null],
        @"canaryVersion": canaryVersion ?: [NSNull null],
        @"hasPendingUpdate": @(hasPending),
        @"downloadInProgress": @(downloadInProgress),
        @"autoUpdateEnabled": @(autoUpdateEnabled),
        @"firstLaunchDone": @(firstLaunchDone),
        @"ignoreList": [self getIgnoreList],
        @"canRollback": @(canActuallyRollback),  // 🔑 УЛУЧШЕННАЯ ПРОВЕРКА
        @"rollbackAvailable": @(previousFolderExists),
        @"rollbackReady": @(canActuallyRollback)
    };

    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                             messageAsDictionary:versionInfo];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)checkForUpdates:(CDVInvokedUrlCommand*)command {
    if (isDownloadingUpdate) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                    messageAsString:@"Download already in progress"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
    NSString *checkVersion = installedVersion ?: appBundleVersion;

    NSString *checkURL = [NSString stringWithFormat:@"%@/check?version=%@&platform=ios",
                         updateServerURL, checkVersion];
    NSURL *url = [NSURL URLWithString:checkURL];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                     messageAsDictionary:@{
                @"error": @"network_error",
                @"message": error.localizedDescription
            }];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            return;
        }

        if (data) {
            NSError *jsonError;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

            if (jsonError) {
                CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                         messageAsDictionary:@{
                    @"error": @"json_error",
                    @"message": jsonError.localizedDescription
                }];
                [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
                return;
            }

            BOOL hasUpdate = [[responseDict objectForKey:@"hasUpdate"] boolValue];

            if (hasUpdate) {
                NSString *newVersion = [responseDict objectForKey:@"version"];

                // Проверяем ignoreList
                if ([self isVersionIgnored:newVersion]) {
                    NSDictionary *result = @{
                        @"hasUpdate": @NO,
                        @"currentVersion": checkVersion,
                        @"message": [NSString stringWithFormat:@"Version %@ is ignored", newVersion]
                    };
                    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                  messageAsDictionary:result];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                    return;
                }

                NSDictionary *result = @{
                    @"hasUpdate": @YES,
                    @"currentVersion": checkVersion,
                    @"newVersion": newVersion,
                    @"downloadURL": [responseDict objectForKey:@"downloadURL"] ?: @"",
                    @"minAppVersion": [responseDict objectForKey:@"minAppVersion"] ?: [NSNull null],
                    @"releaseNotes": [responseDict objectForKey:@"releaseNotes"] ?: @""
                };

                CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                              messageAsDictionary:result];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            } else {
                NSDictionary *result = @{
                    @"hasUpdate": @NO,
                    @"currentVersion": checkVersion,
                    @"message": @"No updates available"
                };

                CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                              messageAsDictionary:result];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            }
        }
    }];

    [task resume];
}

#pragma mark - Background Update Methods


- (void)installPendingUpdate:(NSString*)newVersion {
    NSLog(@"[HotUpdates] 🚀 INSTALLING UPDATE %@ AUTOMATICALLY...", newVersion);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;

    NSString *pendingUpdatePath = [documentsPath stringByAppendingPathComponent:kPendingUpdateDirName];
    NSString *pendingWWWPath = [pendingUpdatePath stringByAppendingPathComponent:kWWWDirName];
    
    // Проверяем, что готовое обновление существует
    if (![fileManager fileExistsAtPath:pendingWWWPath]) {
        NSLog(@"[HotUpdates] ❌ Error: Pending update not found at %@", pendingWWWPath);
        return;
    }
    
    NSLog(@"[HotUpdates] 📂 Installing update to Documents/www: %@", wwwPath);

    // Создаем резервную копию текущей www папки
    NSString *backupPath = [documentsPath stringByAppendingPathComponent:kBackupWWWDirName];
    if ([fileManager fileExistsAtPath:backupPath]) {
        [fileManager removeItemAtPath:backupPath error:nil];
    }
    
    // Делаем бэкап только если www папка существует
    if ([fileManager fileExistsAtPath:wwwPath]) {
        [fileManager moveItemAtPath:wwwPath toPath:backupPath error:&error];
        if (error) {
            NSLog(@"[HotUpdates] ⚠️ Warning: Could not create backup: %@", error.localizedDescription);
        } else {
            NSLog(@"[HotUpdates] Backup created successfully");
        }
    }
    
    NSLog(@"[HotUpdates] Installing new version...");
    
    // Перемещаем новую версию
    [fileManager moveItemAtPath:pendingWWWPath toPath:wwwPath error:&error];
    
    if (error) {
        NSLog(@"[HotUpdates] ❌ ERROR installing update: %@", error.localizedDescription);
        
        // Восстанавливаем из резервной копии
        if ([fileManager fileExistsAtPath:backupPath]) {
            NSLog(@"[HotUpdates] Restoring from backup...");
            [fileManager moveItemAtPath:backupPath toPath:wwwPath error:nil];
        }
        
        // Удаляем поврежденное обновление
        [fileManager removeItemAtPath:pendingUpdatePath error:nil];
        return;
    }
    
    // Сохраняем информацию о новой установленной версии
    [[NSUserDefaults standardUserDefaults] setObject:newVersion forKey:kInstalledVersion];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPendingVersion];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kHasPending];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // Очищаем временные файлы
    [fileManager removeItemAtPath:pendingUpdatePath error:nil];
    [fileManager removeItemAtPath:backupPath error:nil];
    
    NSLog(@"[HotUpdates] ✅ UPDATE INSTALLED SUCCESSFULLY!");
    NSLog(@"[HotUpdates] 🎉 App updated from bundle version to %@", newVersion);
    NSLog(@"[HotUpdates] 📂 Files updated in Documents/www - WebView will load via URL interception");
}

- (void)startBackgroundUpdateProcess {
    NSString *checkIntervalStr = [self.commandDelegate.settings objectForKey:@"hot_updates_check_interval"];
    NSTimeInterval checkInterval = checkIntervalStr ? [checkIntervalStr doubleValue] / 1000.0 : 300.0; // По умолчанию 5 минут
    
    NSLog(@"[HotUpdates] Starting AUTOMATIC background update process:");
    NSLog(@"  - Check interval: %.0f seconds", checkInterval);
    NSLog(@"  - Auto-download: YES");
    NSLog(@"  - Auto-install on next launch: YES");
    
    // Запускаем первую проверку через 30 секунд после запуска (чтобы приложение успело загрузиться)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"[HotUpdates] Starting initial background check...");
        [self performAutomaticUpdateCheck];
    });
    
    // Настраиваем периодическую автоматическую проверку
    updateCheckTimer = [NSTimer scheduledTimerWithTimeInterval:checkInterval
                                                        target:self
                                                      selector:@selector(performAutomaticUpdateCheck)
                                                      userInfo:nil
                                                       repeats:YES];
}

/*!
 * @brief Perform automatic update check
 * @details Checks the server for available updates and downloads them automatically.
 *          Called on startup and periodically in the background.
 */
- (void)performAutomaticUpdateCheck {
    if (isDownloadingUpdate) {
        NSLog(@"[HotUpdates] Automatic check skipped - already downloading update");
        return;
    }

    // Проверяем, есть ли уже готовое обновление
    BOOL hasPending = [[NSUserDefaults standardUserDefaults] boolForKey:kHasPending];
    if (hasPending) {
        NSString *pendingVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kPendingVersion];
        NSLog(@"[HotUpdates] Automatic check skipped - update %@ already downloaded and ready", pendingVersion);
        return;
    }
    
    NSLog(@"[HotUpdates] Performing AUTOMATIC update check...");

    // Получаем текущую установленную версию (может отличаться от bundle версии)
    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
    NSString *checkVersion = installedVersion ?: appBundleVersion;
    
    // Создаем URL для проверки обновлений
    NSString *checkURL = [NSString stringWithFormat:@"%@/check?version=%@&platform=ios", updateServerURL, checkVersion];
    NSURL *url = [NSURL URLWithString:checkURL];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[HotUpdates] Automatic check failed: %@", error.localizedDescription);
            return;
        }
        
        if (data) {
            NSError *jsonError;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                NSLog(@"[HotUpdates] Automatic check JSON error: %@", jsonError.localizedDescription);
                return;
            }
            
            BOOL hasUpdate = [[responseDict objectForKey:@"hasUpdate"] boolValue];
            if (hasUpdate) {
                NSString *newVersion = [responseDict objectForKey:@"version"];
                NSString *downloadURL = [responseDict objectForKey:@"downloadURL"];
                NSString *minAppVersion = [responseDict objectForKey:@"minAppVersion"];

                NSLog(@"[HotUpdates] 🎯 AUTOMATIC UPDATE FOUND: %@ -> %@", checkVersion, newVersion);

                // Проверяем minAppVersion если указан
                if (minAppVersion) {
                    NSComparisonResult comparison = [self compareVersion: checkVersion withVersion:minAppVersion];
                    if (comparison == NSOrderedAscending) {
                        NSLog(@"[HotUpdates] ❌ Update skipped: requires app version %@ but current is %@", minAppVersion, checkVersion);
                        return;
                    } else {
                        NSLog(@"[HotUpdates] ✅ App version %@ meets minimum requirement %@", checkVersion, minAppVersion);
                    }
                } else {
                    NSLog(@"[HotUpdates] No minAppVersion requirement specified");
                }

                NSLog(@"[HotUpdates] Starting automatic download...");

                // Автоматически начинаем загрузку
                [self downloadUpdateAutomatically:downloadURL version:newVersion];
            } else {
                NSLog(@"[HotUpdates] Automatic check: no updates available (current: %@)", checkVersion);
            }
        }
    }];
    
    [task resume];
}

- (void)downloadUpdateAutomatically:(NSString*)downloadURL version:(NSString*)newVersion {
    if (isDownloadingUpdate) {
        NSLog(@"[HotUpdates] Automatic download already in progress");
        return;
    }
    
    isDownloadingUpdate = YES;
    NSLog(@"[HotUpdates] 📥 AUTOMATIC DOWNLOAD STARTED for version %@", newVersion);
    NSLog(@"[HotUpdates] Download URL: %@", downloadURL);
    
    NSURL *url = [NSURL URLWithString:downloadURL];
    
    // Создаем конфигурацию сессии для фоновой загрузки
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 60.0;
    config.timeoutIntervalForResource = 300.0; // 5 минут на загрузку
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:url
                                                        completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        self->isDownloadingUpdate = NO;
        
        if (error) {
            NSLog(@"[HotUpdates] ❌ AUTOMATIC DOWNLOAD FAILED: %@", error.localizedDescription);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSLog(@"[HotUpdates] ❌ AUTOMATIC DOWNLOAD FAILED: HTTP %ld", (long)httpResponse.statusCode);
            return;
        }
        
        NSLog(@"[HotUpdates] ✅ AUTOMATIC DOWNLOAD COMPLETED successfully");
        NSLog(@"[HotUpdates] Preparing update for next app launch...");
        
        [self prepareUpdateForNextLaunch:location version:newVersion];
    }];
    
    [downloadTask resume];
    NSLog(@"[HotUpdates] Download task started in background...");
}

- (void)prepareUpdateForNextLaunch:(NSURL*)updateLocation version:(NSString*)newVersion {
    NSLog(@"[HotUpdates] 🔧 PREPARING UPDATE %@ for next app launch...", newVersion);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;

    // Создаем папку для готового обновления
    NSString *pendingUpdatePath = [documentsPath stringByAppendingPathComponent:kPendingUpdateDirName];
    
    // Удаляем старое готовое обновление если есть
    if ([fileManager fileExistsAtPath:pendingUpdatePath]) {
        NSLog(@"[HotUpdates] Removing old pending update...");
        [fileManager removeItemAtPath:pendingUpdatePath error:nil];
    }
    
    // Создаем папку для нового обновления
    [fileManager createDirectoryAtPath:pendingUpdatePath withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
        NSLog(@"[HotUpdates] ❌ Error creating pending update directory: %@", error.localizedDescription);
        return;
    }
    
    NSLog(@"[HotUpdates] Extracting update package...");
    
    // Распаковываем обновление
    BOOL success = [self unzipFile:updateLocation.path toDestination:pendingUpdatePath];
    if (!success) {
        NSLog(@"[HotUpdates] ❌ Error extracting update package");
        [fileManager removeItemAtPath:pendingUpdatePath error:nil];
        return;
    }
    
    // Проверяем, что www папка создалась
    NSString *pendingWWWPath = [pendingUpdatePath stringByAppendingPathComponent:kWWWDirName];
    if (![fileManager fileExistsAtPath:pendingWWWPath]) {
        NSLog(@"[HotUpdates] ❌ Error: www folder not found in update package");
        [fileManager removeItemAtPath:pendingUpdatePath error:nil];
        return;
    }

    // Сохраняем информацию о версии
    NSString *versionPath = [pendingUpdatePath stringByAppendingPathComponent:@"version.txt"];
    [newVersion writeToFile:versionPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    // Сохраняем информацию о готовом обновлении в UserDefaults
    [[NSUserDefaults standardUserDefaults] setObject:newVersion forKey:kPendingVersion];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kHasPending];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    NSLog(@"[HotUpdates] ✅ UPDATE %@ PREPARED SUCCESSFULLY!", newVersion);
    NSLog(@"[HotUpdates] 📱 Update will be AUTOMATICALLY INSTALLED on next app launch");
    NSLog(@"[HotUpdates] Bundle version: %@, Pending version: %@", appBundleVersion, newVersion);
}

- (void)dealloc {
    if (updateCheckTimer) {
        [updateCheckTimer invalidate];
        updateCheckTimer = nil;
    }
}

#pragma mark - Version Comparison Utilities

/*!
 * @brief Compare two semantic version strings
 * @param version1 First version string (e.g., "2.7.7")
 * @param version2 Second version string (e.g., "2.8.0")
 * @return NSComparisonResult indicating the relationship between the versions
 */
- (NSComparisonResult)compareVersion:(NSString*)version1 withVersion:(NSString*)version2 {
    if (!version1 || !version2) {
        if (!version1 && !version2) return NSOrderedSame;
        return version1 ? NSOrderedDescending : NSOrderedAscending;
    }

    // Разбиваем версии на компоненты
    NSArray *components1 = [version1 componentsSeparatedByString:@"."];
    NSArray *components2 = [version2 componentsSeparatedByString:@"."];

    // Находим максимальное количество компонентов
    NSUInteger maxComponents = MAX(components1.count, components2.count);

    for (NSUInteger i = 0; i < maxComponents; i++) {
        // Получаем компонент или 0 если компонента нет
        NSInteger component1 = (i < components1.count) ? [components1[i] integerValue] : 0;
        NSInteger component2 = (i < components2.count) ? [components2[i] integerValue] : 0;

        if (component1 < component2) {
            return NSOrderedAscending;
        } else if (component1 > component2) {
            return NSOrderedDescending;
        }
        // Если равны, продолжаем к следующему компоненту
    }

    // Все компоненты равны
    return NSOrderedSame;
}

@end
