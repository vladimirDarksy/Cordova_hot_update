/*!
 * @file HotUpdates.m
 * @brief Hot Updates Plugin for Cordova iOS
 * @details Provides frontend-controlled hot updates functionality for Cordova applications.
 *          Downloads and installs web content updates without requiring App Store updates.
 *
 *          Key Features:
 *          - Frontend-controlled manual updates (JS decides when to check/download/install)
 *          - Two-step update process: getUpdate() downloads, forceUpdate() installs
 *          - Automatic rollback with canary system (20-second timeout)
 *          - WebView reload approach for instant updates without app restart
 *          - IgnoreList for tracking problematic versions
 *          - Auto-install pending updates on next app launch
 *
 * @version 2.1.0
 * @date 2025-11-03
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
static NSString * const kIgnoreList = @"hot_updates_ignore_list";
static NSString * const kCanaryVersion = @"hot_updates_canary_version";
static NSString * const kDownloadInProgress = @"hot_updates_download_in_progress";

// Constants for v2.1.0
static NSString * const kPendingUpdateURL = @"hot_updates_pending_update_url";
static NSString * const kPendingUpdateReady = @"hot_updates_pending_ready";

// Directory names
static NSString * const kWWWDirName = @"www";
static NSString * const kPreviousWWWDirName = @"www_previous";
static NSString * const kBackupWWWDirName = @"www_backup";
static NSString * const kPendingUpdateDirName = @"pending_update";

// Флаг для предотвращения повторных перезагрузок при навигации внутри WebView
static BOOL hasPerformedInitialReload = NO;

@interface HotUpdates ()
{
    BOOL isDownloadingUpdate;
    NSString *pendingUpdateURL;
    NSString *pendingUpdateVersion;
    BOOL isUpdateReadyToInstall;
    NSTimer *canaryTimer;
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

    // Загрузка ignoreList
    [self loadIgnoreList];

    // Инициализация переменных
    isUpdateReadyToInstall = NO;
    pendingUpdateURL = nil;
    pendingUpdateVersion = nil;

    // Загружаем информацию о pending update если есть
    pendingUpdateURL = [[NSUserDefaults standardUserDefaults] stringForKey:kPendingUpdateURL];
    isUpdateReadyToInstall = [[NSUserDefaults standardUserDefaults] boolForKey:kPendingUpdateReady];
    if (isUpdateReadyToInstall) {
        pendingUpdateVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kPendingVersion];
        NSLog(@"[HotUpdates] Found pending update ready to install: %@", pendingUpdateVersion);
    }

    NSLog(@"[HotUpdates] Startup sequence initiated");
    NSLog(@"[HotUpdates] Bundle www path: %@", [[NSBundle mainBundle] pathForResource:kWWWDirName ofType:nil]);
    NSLog(@"[HotUpdates] Documents www path: %@", wwwPath);
    NSLog(@"[HotUpdates] Ignore list: %@", ignoreList);

    // 1. Проверяем и устанавливаем pending updates
    [self checkAndInstallPendingUpdate];

    // 2. Создаем папку www если её нет (копируем из bundle)
    [self initializeWWWFolder];

    // 3. Переключаем WebView на обновленный контент и перезагружаем
    [self switchToUpdatedContentWithReload];

    // 4. Запускаем canary timer на 20 секунд
    NSString *currentVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
    if (currentVersion) {
        NSString *canaryVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kCanaryVersion];

        // Если canary еще не был вызван для текущей версии
        if (!canaryVersion || ![canaryVersion isEqualToString:currentVersion]) {
            NSLog(@"[HotUpdates] Starting canary timer (20 seconds) for version %@", currentVersion);

            canaryTimer = [NSTimer scheduledTimerWithTimeInterval:20.0
                                                           target:self
                                                         selector:@selector(canaryTimeout)
                                                         userInfo:nil
                                                          repeats:NO];
        } else {
            NSLog(@"[HotUpdates] Canary already confirmed for version %@", currentVersion);
        }
    }

    NSLog(@"[HotUpdates] Plugin initialized.");
}

- (void)loadConfiguration {
    // Получаем версию bundle приложения
    appBundleVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    if (!appBundleVersion) {
        appBundleVersion = @"1.0.0";
    }

    NSLog(@"[HotUpdates] Configuration loaded:");
    NSLog(@"  App bundle version: %@", appBundleVersion);
}

/*!
 * @brief Check and install pending updates
 * @details Looks for pending updates and installs them to Documents/www
 */
- (void)checkAndInstallPendingUpdate {
    BOOL hasPendingUpdate = [[NSUserDefaults standardUserDefaults] boolForKey:kHasPending];
    NSString *pendingVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kPendingVersion];
    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];

    // ТЗ п.7: Если пользователь проигнорировал попап, обновление устанавливается автоматически при следующем запуске
    if (hasPendingUpdate && pendingVersion) {
        // ВАЖНО (ТЗ): НЕ проверяем ignoreList - JS сам решил загрузить эту версию
        // Если версия скачана (через getUpdate), значит JS одобрил её установку

        NSLog(@"[HotUpdates] Installing pending update %@ to Documents/www (auto-install on launch)", pendingVersion);

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
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCanaryVersion]; // Сбрасываем canary для новой версии
                [[NSUserDefaults standardUserDefaults] synchronize];

                // Очищаем pending_update папку
                [[NSFileManager defaultManager] removeItemAtPath:pendingUpdatePath error:nil];

                NSLog(@"[HotUpdates] Update %@ installed successfully (canary timer will start)", pendingVersion);
            } else {
                NSLog(@"[HotUpdates] Failed to install update: %@", copyError.localizedDescription);
            }
        }
    }
}

/*!
 * @brief Switch WebView to updated content with reload
 * @details Changes wwwFolderName to Documents/www and reloads WebView if updates are installed
 *          Uses static flag to prevent reload on every page navigation (only once per app launch)
 */
- (void)switchToUpdatedContentWithReload {
    // Предотвращаем повторные перезагрузки при навигации между страницами (например, admin → index.html)
    if (hasPerformedInitialReload) {
        NSLog(@"[HotUpdates] Initial reload already performed, skipping");
        return;
    }

    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];

    if (installedVersion) {
        NSString *documentsWwwPath = [documentsPath stringByAppendingPathComponent:kWWWDirName];
        NSString *indexPath = [documentsWwwPath stringByAppendingPathComponent:@"index.html"];

        // Проверяем, что файлы действительно существуют
        if ([[NSFileManager defaultManager] fileExistsAtPath:indexPath]) {
            NSLog(@"[HotUpdates] Using WebView reload approach");
            NSLog(@"[HotUpdates] Found installed update version: %@", installedVersion);

            // Устанавливаем новый путь
            ((CDVViewController *)self.viewController).wwwFolderName = documentsWwwPath;
            NSLog(@"[HotUpdates] Changed wwwFolderName to: %@", documentsWwwPath);

            // Принудительно перезагружаем WebView для применения нового пути
            [self reloadWebView];

            // Устанавливаем флаг, чтобы больше не перезагружать при навигации
            hasPerformedInitialReload = YES;

            NSLog(@"[HotUpdates] WebView reloaded with updated content (version: %@)", installedVersion);
        } else {
            NSLog(@"[HotUpdates] Documents/www/index.html not found, keeping bundle www");
        }
    } else {
        NSLog(@"[HotUpdates] No installed updates, using bundle www");
        // Устанавливаем флаг даже если нет обновлений, чтобы не проверять постоянно
        hasPerformedInitialReload = YES;
    }
}

/*!
 * @brief Force reload the WebView
 * @details Uses WKWebView loadFileURL with proper sandbox permissions
 */
- (void)clearWebViewCache {
    NSLog(@"[HotUpdates] Clearing WebView cache");

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
        NSLog(@"[HotUpdates] WebView cache cleared");
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

        NSLog(@"[HotUpdates] Loading WebView with new URL: %@", fileURL.absoluteString);

        id webViewEngine = cdvViewController.webViewEngine;
        if (webViewEngine && [webViewEngine respondsToSelector:@selector(engineWebView)]) {
            // Получаем WKWebView
            WKWebView *webView = [webViewEngine performSelector:@selector(engineWebView)];

            if (webView && [webView isKindOfClass:[WKWebView class]]) {
                // Используем loadFileURL:allowingReadAccessToURL: для правильных sandbox permissions
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Этот метод правильно настраивает sandbox для локальных файлов
                    [webView loadFileURL:fileURL allowingReadAccessToURL:allowReadAccessToURL];
                    NSLog(@"[HotUpdates] WebView loadFileURL executed with sandbox permissions");
                });
            } else {
                NSLog(@"[HotUpdates] Could not access WKWebView for reload");
            }
        } else {
            NSLog(@"[HotUpdates] WebView engine not available for reload");
        }
    } else {
        NSLog(@"[HotUpdates] ViewController is not CDVViewController type");
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
                NSLog(@"[HotUpdates] Error copying www folder: %@", error.localizedDescription);
            } else {
                NSLog(@"[HotUpdates] WWW folder copied successfully to Documents");
            }
        } else {
            NSLog(@"[HotUpdates] Error: Bundle www folder not found");
        }
    } else {
        NSLog(@"[HotUpdates] WWW folder already exists in Documents");
    }
}

- (BOOL)unzipFile:(NSString*)zipPath toDestination:(NSString*)destination {
    NSLog(@"[HotUpdates] Unzipping %@ to %@", zipPath, destination);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;

    // Создаем папку назначения если её нет
    if (![fileManager fileExistsAtPath:destination]) {
        [fileManager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"[HotUpdates] Error creating destination directory: %@", error.localizedDescription);
            return NO;
        }
    }

    // Распаковка ZIP архива с SSZipArchive
    NSLog(@"[HotUpdates] Extracting ZIP archive using SSZipArchive library");

    // Простая проверка файла
    if (![[NSFileManager defaultManager] fileExistsAtPath:zipPath]) {
        NSLog(@"[HotUpdates] ZIP file does not exist: %@", zipPath);
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
        NSLog(@"[HotUpdates] Failed to create temp extraction folder: %@", error.localizedDescription);
        return NO;
    }

    NSLog(@"[HotUpdates] Extracting to temp location: %@", tempExtractPath);

    // Распаковываем ZIP архив
    BOOL extractSuccess = [SSZipArchive unzipFileAtPath:zipPath toDestination:tempExtractPath];

    if (extractSuccess) {
        NSLog(@"[HotUpdates] ZIP extraction successful");

        // Проверяем содержимое распакованного архива
        NSArray *extractedContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tempExtractPath error:nil];
        NSLog(@"[HotUpdates] Extracted contents: %@", extractedContents);
        
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
            NSLog(@"[HotUpdates] Found www folder at: %@", wwwSourcePath);

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
                NSLog(@"[HotUpdates] www folder copied successfully to: %@", finalWwwPath);

                // Очищаем временную папку
                [[NSFileManager defaultManager] removeItemAtPath:tempExtractPath error:nil];

                NSLog(@"[HotUpdates] ZIP extraction completed successfully");
                return YES;
            } else {
                NSLog(@"[HotUpdates] Error copying www folder: %@", copyError.localizedDescription);
            }
        } else {
            NSLog(@"[HotUpdates] www folder not found in ZIP archive");
            NSLog(@"[HotUpdates] Available contents: %@", extractedContents);
        }

        // Очищаем временную папку при ошибке
        [[NSFileManager defaultManager] removeItemAtPath:tempExtractPath error:nil];
    } else {
        NSLog(@"[HotUpdates] Failed to extract ZIP archive");
        // Очищаем временную папку при ошибке
        [[NSFileManager defaultManager] removeItemAtPath:tempExtractPath error:nil];
    }

    NSLog(@"[HotUpdates] ZIP extraction failed");
    return NO;
}

#pragma mark - Settings Management

- (void)loadIgnoreList {
    NSArray *savedList = [[NSUserDefaults standardUserDefaults] arrayForKey:kIgnoreList];
    ignoreList = savedList ? [savedList mutableCopy] : [NSMutableArray array];
}

- (NSArray*)getIgnoreListInternal {
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

- (void)getIgnoreList:(CDVInvokedUrlCommand*)command {
    NSArray *ignoreList = [self getIgnoreListInternal];

    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                             messageAsDictionary:@{
        @"versions": ignoreList
    }];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

#pragma mark - Canary Timeout Handler

- (void)canaryTimeout {
    NSLog(@"[HotUpdates] CANARY TIMEOUT - JS did not call canary() within 20 seconds");

    NSString *currentVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
    NSString *previousVersion = [self getPreviousVersion];

    // Если некуда откатываться (свежая установка из Store) - ничего не делаем
    if (!previousVersion || previousVersion.length == 0) {
        NSLog(@"[HotUpdates] Fresh install from Store, rollback not possible");
        return;
    }

    NSLog(@"[HotUpdates] Version %@ considered faulty, performing rollback", currentVersion);

    // Добавляем в ignoreList
    if (currentVersion) {
        [self addVersionToIgnoreList:currentVersion];
    }

    // Выполняем rollback
    BOOL rollbackSuccess = [self rollbackToPreviousVersion];

    if (rollbackSuccess) {
        NSLog(@"[HotUpdates] Automatic rollback completed successfully");

        // Сбрасываем флаг для разрешения перезагрузки после rollback
        hasPerformedInitialReload = NO;

        // Очищаем кэш и перезагружаем WebView
        [self clearWebViewCache];
        [self reloadWebView];
    } else {
        NSLog(@"[HotUpdates] Automatic rollback failed");
    }
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
            NSLog(@"[HotUpdates] Backed up version: %@", currentVersion ?: appBundleVersion);
        } else {
            NSLog(@"[HotUpdates] Backup failed: %@", error.localizedDescription);
        }
    }
}

- (BOOL)rollbackToPreviousVersion {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *currentVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
    NSString *previousVersion = [self getPreviousVersion];

    NSLog(@"[HotUpdates] Rollback: %@ -> %@", currentVersion ?: @"bundle", previousVersion ?: @"nil");

    // Проверка: нет previousVersion
    if (!previousVersion || previousVersion.length == 0) {
        NSLog(@"[HotUpdates] Rollback failed: no previous version");
        return NO;
    }

    // Проверка: папка не существует
    if (![fileManager fileExistsAtPath:previousVersionPath]) {
        NSLog(@"[HotUpdates] Rollback failed: previous version folder not found");
        return NO;
    }

    // Проверка: previous = current (защита от цикла)
    NSString *effectiveCurrentVersion = currentVersion ?: appBundleVersion;
    if ([previousVersion isEqualToString:effectiveCurrentVersion]) {
        NSLog(@"[HotUpdates] Rollback failed: cannot rollback to same version");
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
            NSLog(@"[HotUpdates] Rollback failed: cannot backup current version");
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

        NSLog(@"[HotUpdates] Rollback successful: %@ -> %@", currentVersion, previousVersion);

        // Добавляем проблемную версию в ignoreList
        if (currentVersion) {
            [self addVersionToIgnoreList:currentVersion];
        }

        return YES;
    } else {
        NSLog(@"[HotUpdates] Rollback failed: %@", error.localizedDescription);

        // Восстанавливаем текущую версию
        if ([fileManager fileExistsAtPath:tempBackupPath]) {
            [fileManager moveItemAtPath:tempBackupPath toPath:wwwPath error:nil];
        }

        return NO;
    }
}

#pragma mark - Get Update (Download Only)

- (void)getUpdate:(CDVInvokedUrlCommand*)command {
    NSDictionary *updateData = [command.arguments objectAtIndex:0];

    if (!updateData) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"error": @{
                @"message": @"Update data required"
            }
        }];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    NSString *downloadURL = [updateData objectForKey:@"url"];

    if (!downloadURL) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"error": @{
                @"message": @"URL required"
            }
        }];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    // Опциональная версия (для автоустановки при следующем запуске)
    NSString *updateVersion = [updateData objectForKey:@"version"];
    if (!updateVersion) {
        updateVersion = @"pending";
    }

    NSLog(@"[HotUpdates] getUpdate() called - downloading update from: %@", downloadURL);
    NSLog(@"[HotUpdates] Version: %@", updateVersion);

    // ВАЖНО (ТЗ): НЕ проверяем ignoreList - JS сам контролирует что загружать

    // 1. Проверяем, не установлена ли уже эта версия
    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
    if (installedVersion && [installedVersion isEqualToString:updateVersion]) {
        NSLog(@"[HotUpdates] Version %@ already installed, skipping download", updateVersion);
        // Возвращаем SUCCESS - версия уже установлена
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    // 2. Проверяем, не скачана ли уже эта версия (hasPending + та же версия)
    BOOL hasPending = [[NSUserDefaults standardUserDefaults] boolForKey:kHasPending];
    NSString *existingPendingVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kPendingVersion];

    if (hasPending && existingPendingVersion && [existingPendingVersion isEqualToString:updateVersion]) {
        NSLog(@"[HotUpdates] Version %@ already downloaded, skipping re-download", updateVersion);
        // Возвращаем SUCCESS - версия уже скачана, повторная загрузка не нужна
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    // 3. Проверяем, не скачивается ли уже обновление
    if (isDownloadingUpdate) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"error": @{
                @"message": @"Download already in progress"
            }
        }];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    // Сохраняем URL и версию для последующей установки и автоустановки
    pendingUpdateURL = downloadURL;
    pendingUpdateVersion = updateVersion;
    [[NSUserDefaults standardUserDefaults] setObject:downloadURL forKey:kPendingUpdateURL];
    [[NSUserDefaults standardUserDefaults] setObject:updateVersion forKey:kPendingVersion];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // Запускаем загрузку
    [self downloadUpdateOnly:downloadURL callbackId:command.callbackId];
}

- (void)downloadUpdateOnly:(NSString*)downloadURL callbackId:(NSString*)callbackId {
    isDownloadingUpdate = YES;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kDownloadInProgress];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSLog(@"[HotUpdates] Starting download");

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
            NSLog(@"[HotUpdates] Download failed: %@", error.localizedDescription);

            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                     messageAsDictionary:@{
                @"error": @{
                    @"message": error.localizedDescription
                }
            }];
            [self.commandDelegate sendPluginResult:result callbackId:callbackId];
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSLog(@"[HotUpdates] Download failed: HTTP %ld", (long)httpResponse.statusCode);

            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                     messageAsDictionary:@{
                @"error": @{
                    @"message": [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]
                }
            }];
            [self.commandDelegate sendPluginResult:result callbackId:callbackId];
            return;
        }

        NSLog(@"[HotUpdates] Download completed successfully");

        // Сохраняем скачанное обновление во временную папку
        [self saveDownloadedUpdate:location callbackId:callbackId];
    }];

    [downloadTask resume];
}

- (void)saveDownloadedUpdate:(NSURL*)updateLocation callbackId:(NSString*)callbackId {
    NSLog(@"[HotUpdates] Saving downloaded update");

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;

    // Создаем временную папку для распаковки
    NSString *tempUpdatePath = [documentsPath stringByAppendingPathComponent:@"temp_downloaded_update"];

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
        NSLog(@"[HotUpdates] Error creating temp directory: %@", error);
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"error": @{
                @"message": @"Cannot create temp directory"
            }
        }];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }

    // Распаковываем обновление
    BOOL unzipSuccess = [self unzipFile:updateLocation.path toDestination:tempUpdatePath];

    if (!unzipSuccess) {
        NSLog(@"[HotUpdates] Failed to unzip update");
        [fileManager removeItemAtPath:tempUpdatePath error:nil];

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"error": @{
                @"message": @"Failed to extract update package"
            }
        }];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }

    // Проверяем наличие www папки
    NSString *tempWwwPath = [tempUpdatePath stringByAppendingPathComponent:kWWWDirName];
    if (![fileManager fileExistsAtPath:tempWwwPath]) {
        NSLog(@"[HotUpdates] www folder not found in update package");
        [fileManager removeItemAtPath:tempUpdatePath error:nil];

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"error": @{
                @"message": @"www folder not found in package"
            }
        }];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }

    // Копируем также в pending_update для автоустановки при следующем запуске (ТЗ п.7)
    NSString *pendingPath = [documentsPath stringByAppendingPathComponent:kPendingUpdateDirName];

    // Удаляем старую pending_update папку
    if ([fileManager fileExistsAtPath:pendingPath]) {
        [fileManager removeItemAtPath:pendingPath error:nil];
    }

    // Копируем temp_downloaded_update → pending_update
    BOOL copySuccess = [fileManager copyItemAtPath:tempUpdatePath
                                            toPath:pendingPath
                                             error:&error];

    if (!copySuccess) {
        NSLog(@"[HotUpdates] Failed to copy to pending_update: %@", error);
        // Не критично - forceUpdate всё равно сработает из temp_downloaded_update
    } else {
        NSLog(@"[HotUpdates] Copied to pending_update for auto-install on next launch");
    }

    // Помечаем обновление как готовое к установке (для forceUpdate)
    isUpdateReadyToInstall = YES;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPendingUpdateReady];

    // Устанавливаем флаг для автоустановки при следующем запуске (ТЗ п.7)
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kHasPending];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSLog(@"[HotUpdates] Update downloaded and ready to install");
    NSLog(@"[HotUpdates] If user ignores popup, update will install automatically on next launch");

    // Возвращаем успех (callback без ошибки) - ТЗ: возвращаем null при успехе
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
}

#pragma mark - Force Update (Install Only)

- (void)forceUpdate:(CDVInvokedUrlCommand*)command {
    NSLog(@"[HotUpdates] forceUpdate() called - installing downloaded update");

    // ВАЖНО: Не проверяем ignoreList - это контролирует JS

    // Проверяем, что обновление было скачано
    if (!isUpdateReadyToInstall) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"error": @{
                @"message": @"No update ready to install. Call getUpdate() first."
            }
        }];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    NSString *tempUpdatePath = [documentsPath stringByAppendingPathComponent:@"temp_downloaded_update"];
    NSString *tempWwwPath = [tempUpdatePath stringByAppendingPathComponent:kWWWDirName];

    // Проверяем наличие скачанных файлов
    if (![[NSFileManager defaultManager] fileExistsAtPath:tempWwwPath]) {
        NSLog(@"[HotUpdates] Downloaded update files not found");

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"error": @{
                @"message": @"Downloaded update files not found"
            }
        }];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    // Устанавливаем обновление
    [self installDownloadedUpdate:tempWwwPath callbackId:command.callbackId];
}

- (void)installDownloadedUpdate:(NSString*)tempWwwPath callbackId:(NSString*)callbackId {
    NSLog(@"[HotUpdates] Installing update");

    // Определяем версию ДО установки
    NSString *versionToInstall = [[NSUserDefaults standardUserDefaults] stringForKey:kPendingVersion];
    if (!versionToInstall) {
        versionToInstall = @"unknown";
    }

    // ВАЖНО (ТЗ): НЕ проверяем ignoreList - JS сам контролирует что устанавливать

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;

    // ВАЖНО: Создаем резервную копию текущей версии
    [self backupCurrentVersion];

    // Удаляем текущую www
    if ([fileManager fileExistsAtPath:wwwPath]) {
        [fileManager removeItemAtPath:wwwPath error:nil];
    }

    // Копируем новую версию
    BOOL copySuccess = [fileManager copyItemAtPath:tempWwwPath
                                            toPath:wwwPath
                                             error:&error];

    if (!copySuccess) {
        NSLog(@"[HotUpdates] Failed to install update: %@", error);

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:@{
            @"error": @{
                @"message": error.localizedDescription
            }
        }];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }

    // Используем версию определенную ранее
    NSString *newVersion = versionToInstall;

    // Обновляем метаданные
    [[NSUserDefaults standardUserDefaults] setObject:newVersion forKey:kInstalledVersion];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kPendingUpdateReady];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kHasPending]; // Очищаем флаг автоустановки
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPendingUpdateURL];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPendingVersion];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCanaryVersion]; // Сбрасываем canary
    [[NSUserDefaults standardUserDefaults] synchronize];

    // Очищаем временные папки
    NSString *tempUpdatePath = [documentsPath stringByAppendingPathComponent:@"temp_downloaded_update"];
    NSString *pendingPath = [documentsPath stringByAppendingPathComponent:kPendingUpdateDirName];
    [fileManager removeItemAtPath:tempUpdatePath error:nil];
    [fileManager removeItemAtPath:pendingPath error:nil];

    // Сбрасываем флаги
    isUpdateReadyToInstall = NO;
    pendingUpdateURL = nil;

    NSLog(@"[HotUpdates] Update installed successfully");

    // Возвращаем успех ПЕРЕД перезагрузкой - ТЗ: возвращаем null при успехе
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];

    // КРИТИЧЕСКИ ВАЖНО: Запускаем canary timer ПЕРЕД перезагрузкой
    // После reloadWebView pluginInitialize НЕ вызывается, поэтому таймер нужно запустить вручную
    NSLog(@"[HotUpdates] Starting canary timer (20 seconds) for version %@", newVersion);

    // Останавливаем предыдущий таймер если был
    if (canaryTimer && [canaryTimer isValid]) {
        [canaryTimer invalidate];
    }

    // Запускаем новый таймер на 20 секунд
    canaryTimer = [NSTimer scheduledTimerWithTimeInterval:20.0
                                                   target:self
                                                 selector:@selector(canaryTimeout)
                                                 userInfo:nil
                                                  repeats:NO];

    // Сбрасываем флаг для разрешения перезагрузки после установки обновления
    hasPerformedInitialReload = NO;

    // КРИТИЧЕСКИ ВАЖНО: Очищаем кэш WebView перед перезагрузкой
    // Без этого может загрузиться старая закэшированная версия
    [self clearWebViewCache];

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

    NSLog(@"[HotUpdates] Canary called for version: %@", canaryVersion);

    // Сохраняем canary версию
    [[NSUserDefaults standardUserDefaults] setObject:canaryVersion forKey:kCanaryVersion];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // Останавливаем canary таймер если он запущен
    if (canaryTimer && [canaryTimer isValid]) {
        [canaryTimer invalidate];
        canaryTimer = nil;
        NSLog(@"[HotUpdates] Canary timer stopped - JS confirmed bundle is working");
    }

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
    NSString *canaryVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kCanaryVersion];
    NSString *pendingVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kPendingVersion];
    BOOL hasPendingUpdate = [[NSUserDefaults standardUserDefaults] boolForKey:kHasPending];

    NSDictionary *info = @{
        @"appBundleVersion": appBundleVersion ?: @"unknown",
        @"installedVersion": installedVersion ?: [NSNull null],
        @"previousVersion": previousVersion ?: [NSNull null],
        @"canaryVersion": canaryVersion ?: [NSNull null],
        @"pendingVersion": pendingVersion ?: [NSNull null],
        @"hasPendingUpdate": @(hasPendingUpdate),
        @"ignoreList": [self getIgnoreListInternal]
    };

    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                 messageAsDictionary:info];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)checkForUpdates:(CDVInvokedUrlCommand*)command {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                             messageAsDictionary:@{
        @"error": @{
            @"message": @"checkForUpdates() removed in v2.1.0. Use fetch() in JS to check your server for updates, then call getUpdate({url}) to download."
        }
    }];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

@end
