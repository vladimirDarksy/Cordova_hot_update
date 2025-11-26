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
 * @version 2.1.2
 * @date 2025-11-26
 * @author Mustafin Vladimir
 * @copyright Copyright (c) 2025. All rights reserved.
 */

#import <Cordova/CDV.h>
#import <Cordova/CDVViewController.h>
#import "HotUpdates.h"
#import "HotUpdates+Helpers.h"
#import "HotUpdatesConstants.h"
#import <SSZipArchive/SSZipArchive.h>

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

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    documentsPath = [paths objectAtIndex:0];
    wwwPath = [documentsPath stringByAppendingPathComponent:kWWWDirName];
    previousVersionPath = [documentsPath stringByAppendingPathComponent:kPreviousWWWDirName];

    [self loadConfiguration];
    [self loadIgnoreList];

    // Сбрасываем флаг загрузки (если приложение было убито во время загрузки)
    isDownloadingUpdate = NO;
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kDownloadInProgress];

    isUpdateReadyToInstall = NO;
    pendingUpdateURL = nil;
    pendingUpdateVersion = nil;

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

    [self checkAndInstallPendingUpdate];
    [self initializeWWWFolder];
    [self switchToUpdatedContentWithReload];

    NSString *currentVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
    if (currentVersion) {
        NSString *canaryVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kCanaryVersion];

        if (!canaryVersion || ![canaryVersion isEqualToString:currentVersion]) {
            NSLog(@"[HotUpdates] Starting canary timer (20 seconds) for version %@", currentVersion);

            [self startCanaryTimer];
        } else {
            NSLog(@"[HotUpdates] Canary already confirmed for version %@", currentVersion);
        }
    }

    NSLog(@"[HotUpdates] Plugin initialized.");
}

- (void)loadConfiguration {
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

    if (hasPendingUpdate && pendingVersion) {
        NSLog(@"[HotUpdates] Installing pending update %@ to Documents/www (auto-install on launch)", pendingVersion);

        [self backupCurrentVersion];

        NSString *pendingUpdatePath = [documentsPath stringByAppendingPathComponent:kPendingUpdateDirName];
        NSString *pendingWwwPath = [pendingUpdatePath stringByAppendingPathComponent:kWWWDirName];
        NSString *documentsWwwPath = [documentsPath stringByAppendingPathComponent:kWWWDirName];

        if ([[NSFileManager defaultManager] fileExistsAtPath:pendingWwwPath]) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:documentsWwwPath]) {
                [[NSFileManager defaultManager] removeItemAtPath:documentsWwwPath error:nil];
            }

            NSError *copyError = nil;
            BOOL copySuccess = [[NSFileManager defaultManager] copyItemAtPath:pendingWwwPath toPath:documentsWwwPath error:&copyError];

            if (copySuccess) {
                [[NSUserDefaults standardUserDefaults] setObject:pendingVersion forKey:kInstalledVersion];
                [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kHasPending];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPendingVersion];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCanaryVersion];
                [[NSUserDefaults standardUserDefaults] synchronize];

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
    // Предотвращаем повторные перезагрузки при навигации между страницами
    if (hasPerformedInitialReload) {
        NSLog(@"[HotUpdates] Initial reload already performed, skipping");
        return;
    }

    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];

    if (installedVersion) {
        NSString *documentsWwwPath = [documentsPath stringByAppendingPathComponent:kWWWDirName];
        NSString *indexPath = [documentsWwwPath stringByAppendingPathComponent:@"index.html"];

        if ([[NSFileManager defaultManager] fileExistsAtPath:indexPath]) {
            NSLog(@"[HotUpdates] Using WebView reload approach");
            NSLog(@"[HotUpdates] Found installed update version: %@", installedVersion);

            ((CDVViewController *)self.viewController).wwwFolderName = documentsWwwPath;
            NSLog(@"[HotUpdates] Changed wwwFolderName to: %@", documentsWwwPath);

            hasPerformedInitialReload = YES;

            // Очищаем кэш перед перезагрузкой, иначе может загрузиться старая версия
            [self clearWebViewCacheWithCompletion:^{
                [self reloadWebView];
                NSLog(@"[HotUpdates] WebView reloaded with updated content (version: %@)", installedVersion);
            }];
        } else {
            NSLog(@"[HotUpdates] Documents/www/index.html not found, keeping bundle www");
        }
    } else {
        NSLog(@"[HotUpdates] No installed updates, using bundle www");
        hasPerformedInitialReload = YES;
    }
}

/*!
 * @brief Clear WebView cache
 * @details Clears disk cache, memory cache, offline storage and service workers
 */
- (void)clearWebViewCache {
    [self clearWebViewCacheWithCompletion:nil];
}

/*!
 * @brief Clear WebView cache with completion handler
 * @param completion Block called after cache is cleared (on main thread)
 */
- (void)clearWebViewCacheWithCompletion:(void (^)(void))completion {
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
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }
    }];
}

- (void)reloadWebView {
    if ([self.viewController isKindOfClass:[CDVViewController class]]) {
        CDVViewController *cdvViewController = (CDVViewController *)self.viewController;

        NSString *documentsWwwPath = [documentsPath stringByAppendingPathComponent:kWWWDirName];
        NSString *indexPath = [documentsWwwPath stringByAppendingPathComponent:@"index.html"];
        NSURL *fileURL = [NSURL fileURLWithPath:indexPath];
        NSURL *allowReadAccessToURL = [NSURL fileURLWithPath:documentsWwwPath];

        NSLog(@"[HotUpdates] Loading WebView with new URL: %@", fileURL.absoluteString);

        id webViewEngine = cdvViewController.webViewEngine;
        if (webViewEngine && [webViewEngine respondsToSelector:@selector(engineWebView)]) {
            WKWebView *webView = [webViewEngine performSelector:@selector(engineWebView)];

            if (webView && [webView isKindOfClass:[WKWebView class]]) {
                // loadFileURL:allowingReadAccessToURL: правильно настраивает sandbox permissions для локальных файлов
                dispatch_async(dispatch_get_main_queue(), ^{
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

    if (![fileManager fileExistsAtPath:wwwPath]) {
        NSLog(@"[HotUpdates] WWW folder not found in Documents. Creating and copying from bundle...");

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

    if (![fileManager fileExistsAtPath:destination]) {
        [fileManager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"[HotUpdates] Error creating destination directory: %@", error.localizedDescription);
            return NO;
        }
    }

    NSLog(@"[HotUpdates] Extracting ZIP archive using SSZipArchive library");

    if (![[NSFileManager defaultManager] fileExistsAtPath:zipPath]) {
        NSLog(@"[HotUpdates] ZIP file does not exist: %@", zipPath);
        return NO;
    }

    NSString *tempExtractPath = [destination stringByAppendingPathComponent:@"temp_extract"];

    if ([[NSFileManager defaultManager] fileExistsAtPath:tempExtractPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:tempExtractPath error:nil];
    }

    if (![[NSFileManager defaultManager] createDirectoryAtPath:tempExtractPath withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"[HotUpdates] Failed to create temp extraction folder: %@", error.localizedDescription);
        return NO;
    }

    NSLog(@"[HotUpdates] Extracting to temp location: %@", tempExtractPath);

    BOOL extractSuccess = [SSZipArchive unzipFileAtPath:zipPath toDestination:tempExtractPath];

    if (extractSuccess) {
        NSLog(@"[HotUpdates] ZIP extraction successful");

        NSArray *extractedContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tempExtractPath error:nil];
        NSLog(@"[HotUpdates] Extracted contents: %@", extractedContents);

        // Ищем папку www (может быть вложенной)
        NSString *wwwSourcePath = nil;
        for (NSString *item in extractedContents) {
            NSString *itemPath = [tempExtractPath stringByAppendingPathComponent:item];
            BOOL isDirectory;
            if ([[NSFileManager defaultManager] fileExistsAtPath:itemPath isDirectory:&isDirectory] && isDirectory) {
                if ([item isEqualToString:@"www"]) {
                    wwwSourcePath = itemPath;
                    break;
                }
                NSString *nestedWwwPath = [itemPath stringByAppendingPathComponent:@"www"];
                if ([[NSFileManager defaultManager] fileExistsAtPath:nestedWwwPath]) {
                    wwwSourcePath = nestedWwwPath;
                    break;
                }
            }
        }

        if (wwwSourcePath) {
            NSLog(@"[HotUpdates] Found www folder at: %@", wwwSourcePath);

            NSString *finalWwwPath = [destination stringByAppendingPathComponent:@"www"];

            if ([[NSFileManager defaultManager] fileExistsAtPath:finalWwwPath]) {
                [[NSFileManager defaultManager] removeItemAtPath:finalWwwPath error:nil];
            }

            NSError *copyError = nil;
            BOOL copySuccess = [[NSFileManager defaultManager] copyItemAtPath:wwwSourcePath toPath:finalWwwPath error:&copyError];

            if (copySuccess) {
                NSLog(@"[HotUpdates] www folder copied successfully to: %@", finalWwwPath);

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

        [[NSFileManager defaultManager] removeItemAtPath:tempExtractPath error:nil];
    } else {
        NSLog(@"[HotUpdates] Failed to extract ZIP archive");
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

#pragma mark - Canary Timer

/*!
 * @brief Start canary timer with weak self to prevent retain cycle
 * @details Uses block-based timer (iOS 10+) with weak reference
 */
- (void)startCanaryTimer {
    // Инвалидируем предыдущий таймер если есть
    if (canaryTimer && [canaryTimer isValid]) {
        [canaryTimer invalidate];
        canaryTimer = nil;
    }

    // Используем weak self для предотвращения retain cycle
    __weak __typeof__(self) weakSelf = self;
    canaryTimer = [NSTimer scheduledTimerWithTimeInterval:20.0
                                                  repeats:NO
                                                    block:^(NSTimer * _Nonnull timer) {
        [weakSelf canaryTimeout];
    }];
}

#pragma mark - Canary Timeout Handler

- (void)canaryTimeout {
    NSLog(@"[HotUpdates] CANARY TIMEOUT - JS did not call canary() within 20 seconds");

    NSString *currentVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
    NSString *previousVersion = [self getPreviousVersion];

    if (!previousVersion || previousVersion.length == 0) {
        NSLog(@"[HotUpdates] Fresh install from Store, rollback not possible");
        return;
    }

    NSLog(@"[HotUpdates] Version %@ considered faulty, performing rollback", currentVersion);

    // Примечание: версия добавляется в ignoreList внутри rollbackToPreviousVersion
    BOOL rollbackSuccess = [self rollbackToPreviousVersion];

    if (rollbackSuccess) {
        NSLog(@"[HotUpdates] Automatic rollback completed successfully");

        hasPerformedInitialReload = NO;

        [self clearWebViewCacheWithCompletion:^{
            [self reloadWebView];
        }];
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

    if (!previousVersion || previousVersion.length == 0) {
        NSLog(@"[HotUpdates] Rollback failed: no previous version");
        return NO;
    }

    if (![fileManager fileExistsAtPath:previousVersionPath]) {
        NSLog(@"[HotUpdates] Rollback failed: previous version folder not found");
        return NO;
    }

    // Защита от цикла rollback
    NSString *effectiveCurrentVersion = currentVersion ?: appBundleVersion;
    if ([previousVersion isEqualToString:effectiveCurrentVersion]) {
        NSLog(@"[HotUpdates] Rollback failed: cannot rollback to same version");
        return NO;
    }

    NSString *tempBackupPath = [documentsPath stringByAppendingPathComponent:kBackupWWWDirName];
    if ([fileManager fileExistsAtPath:tempBackupPath]) {
        [fileManager removeItemAtPath:tempBackupPath error:nil];
    }

    NSError *error = nil;

    if ([fileManager fileExistsAtPath:wwwPath]) {
        [fileManager moveItemAtPath:wwwPath toPath:tempBackupPath error:&error];
        if (error) {
            NSLog(@"[HotUpdates] Rollback failed: cannot backup current version");
            return NO;
        }
    }

    BOOL success = [fileManager copyItemAtPath:previousVersionPath
                                        toPath:wwwPath
                                         error:&error];

    if (success) {
        [[NSUserDefaults standardUserDefaults] setObject:previousVersion forKey:kInstalledVersion];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPreviousVersion];
        [[NSUserDefaults standardUserDefaults] synchronize];

        [fileManager removeItemAtPath:tempBackupPath error:nil];

        NSLog(@"[HotUpdates] Rollback successful: %@ -> %@", currentVersion, previousVersion);

        if (currentVersion) {
            [self addVersionToIgnoreList:currentVersion];
        }

        return YES;
    } else {
        NSLog(@"[HotUpdates] Rollback failed: %@", error.localizedDescription);

        if ([fileManager fileExistsAtPath:tempBackupPath]) {
            [fileManager moveItemAtPath:tempBackupPath toPath:wwwPath error:nil];
        }

        return NO;
    }
}

#pragma mark - Get Update (Download Only)

- (void)getUpdate:(CDVInvokedUrlCommand*)command {
    // Безопасное получение первого аргумента
    NSDictionary *updateData = nil;
    if (command.arguments.count > 0 && [command.arguments[0] isKindOfClass:[NSDictionary class]]) {
        updateData = command.arguments[0];
    }

    if (!updateData) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:[self createError:kErrorUpdateDataRequired
                                                                                message:@"Update data required"]];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    NSString *downloadURL = [updateData objectForKey:@"url"];

    if (!downloadURL) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:[self createError:kErrorURLRequired
                                                                                message:@"URL is required"]];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    NSString *updateVersion = [updateData objectForKey:@"version"];
    if (!updateVersion) {
        updateVersion = @"pending";
    }

    NSLog(@"[HotUpdates] getUpdate() called - downloading update from: %@", downloadURL);
    NSLog(@"[HotUpdates] Version: %@", updateVersion);

    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersion];
    if (installedVersion && [installedVersion isEqualToString:updateVersion]) {
        NSLog(@"[HotUpdates] Version %@ already installed, skipping download", updateVersion);
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    BOOL hasPending = [[NSUserDefaults standardUserDefaults] boolForKey:kHasPending];
    NSString *existingPendingVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kPendingVersion];

    if (hasPending && existingPendingVersion && [existingPendingVersion isEqualToString:updateVersion]) {
        NSLog(@"[HotUpdates] Version %@ already downloaded, skipping re-download", updateVersion);
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    if (isDownloadingUpdate) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:[self createError:kErrorDownloadInProgress
                                                                                message:@"Download already in progress"]];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    pendingUpdateURL = downloadURL;
    pendingUpdateVersion = updateVersion;
    [[NSUserDefaults standardUserDefaults] setObject:downloadURL forKey:kPendingUpdateURL];
    [[NSUserDefaults standardUserDefaults] setObject:updateVersion forKey:kPendingVersion];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [self downloadUpdateOnly:downloadURL callbackId:command.callbackId];
}

- (void)downloadUpdateOnly:(NSString*)downloadURL callbackId:(NSString*)callbackId {
    isDownloadingUpdate = YES;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kDownloadInProgress];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSLog(@"[HotUpdates] Starting download");

    NSURL *url = [NSURL URLWithString:downloadURL];
    if (!url) {
        NSLog(@"[HotUpdates] Invalid URL: %@", downloadURL);
        isDownloadingUpdate = NO;
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kDownloadInProgress];
        [[NSUserDefaults standardUserDefaults] synchronize];

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:[self createError:kErrorURLRequired
                                                                                message:@"Invalid URL format"]];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 30.0;  // ТЗ: 30-60 секунд
    config.timeoutIntervalForResource = 60.0; // ТЗ: максимум 60 секунд на всю загрузку

    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:url
                                                        completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        // Инвалидируем сессию для предотвращения утечки памяти
        [session finishTasksAndInvalidate];

        self->isDownloadingUpdate = NO;
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kDownloadInProgress];
        [[NSUserDefaults standardUserDefaults] synchronize];

        if (error) {
            NSLog(@"[HotUpdates] Download failed: %@", error.localizedDescription);

            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                     messageAsDictionary:[self createError:kErrorDownloadFailed
                                                                                    message:[NSString stringWithFormat:@"Download failed: %@", error.localizedDescription]]];
            [self.commandDelegate sendPluginResult:result callbackId:callbackId];
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSLog(@"[HotUpdates] Download failed: HTTP %ld", (long)httpResponse.statusCode);

            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                     messageAsDictionary:[self createError:kErrorHTTPError
                                                                                    message:[NSString stringWithFormat:@"HTTP error: %ld", (long)httpResponse.statusCode]]];
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

    NSString *tempUpdatePath = [documentsPath stringByAppendingPathComponent:@"temp_downloaded_update"];

    if ([fileManager fileExistsAtPath:tempUpdatePath]) {
        [fileManager removeItemAtPath:tempUpdatePath error:nil];
    }

    [fileManager createDirectoryAtPath:tempUpdatePath
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:&error];

    if (error) {
        NSLog(@"[HotUpdates] Error creating temp directory: %@", error);
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:[self createError:kErrorTempDirError
                                                                                message:@"Cannot create temp directory"]];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }

    BOOL unzipSuccess = [self unzipFile:updateLocation.path toDestination:tempUpdatePath];

    if (!unzipSuccess) {
        NSLog(@"[HotUpdates] Failed to unzip update");
        [fileManager removeItemAtPath:tempUpdatePath error:nil];

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:[self createError:kErrorExtractionFailed
                                                                                message:@"Failed to extract update package"]];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }

    NSString *tempWwwPath = [tempUpdatePath stringByAppendingPathComponent:kWWWDirName];
    if (![fileManager fileExistsAtPath:tempWwwPath]) {
        NSLog(@"[HotUpdates] www folder not found in update package");
        [fileManager removeItemAtPath:tempUpdatePath error:nil];

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:[self createError:kErrorWWWNotFound
                                                                                message:@"www folder not found in package"]];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }

    // Копируем в pending_update для автоустановки при следующем запуске
    NSString *pendingPath = [documentsPath stringByAppendingPathComponent:kPendingUpdateDirName];

    if ([fileManager fileExistsAtPath:pendingPath]) {
        [fileManager removeItemAtPath:pendingPath error:nil];
    }

    BOOL copySuccess = [fileManager copyItemAtPath:tempUpdatePath
                                            toPath:pendingPath
                                             error:&error];

    if (!copySuccess) {
        NSLog(@"[HotUpdates] Failed to copy to pending_update: %@", error);
    } else {
        NSLog(@"[HotUpdates] Copied to pending_update for auto-install on next launch");
    }

    isUpdateReadyToInstall = YES;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPendingUpdateReady];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kHasPending];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSLog(@"[HotUpdates] Update downloaded and ready to install");
    NSLog(@"[HotUpdates] If user ignores popup, update will install automatically on next launch");

    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
}

#pragma mark - Force Update (Install Only)

- (void)forceUpdate:(CDVInvokedUrlCommand*)command {
    NSLog(@"[HotUpdates] forceUpdate() called - installing downloaded update");

    if (!isUpdateReadyToInstall) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:[self createError:kErrorNoUpdateReady
                                                                                message:@"No update ready to install"]];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    NSString *tempUpdatePath = [documentsPath stringByAppendingPathComponent:@"temp_downloaded_update"];
    NSString *tempWwwPath = [tempUpdatePath stringByAppendingPathComponent:kWWWDirName];

    if (![[NSFileManager defaultManager] fileExistsAtPath:tempWwwPath]) {
        NSLog(@"[HotUpdates] Downloaded update files not found");

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:[self createError:kErrorUpdateFilesNotFound
                                                                                message:@"Downloaded update files not found"]];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    [self installDownloadedUpdate:tempWwwPath callbackId:command.callbackId];
}

- (void)installDownloadedUpdate:(NSString*)tempWwwPath callbackId:(NSString*)callbackId {
    NSLog(@"[HotUpdates] Installing update");

    NSString *versionToInstall = [[NSUserDefaults standardUserDefaults] stringForKey:kPendingVersion];
    if (!versionToInstall) {
        versionToInstall = @"unknown";
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;

    [self backupCurrentVersion];

    if ([fileManager fileExistsAtPath:wwwPath]) {
        [fileManager removeItemAtPath:wwwPath error:nil];
    }

    BOOL copySuccess = [fileManager copyItemAtPath:tempWwwPath
                                            toPath:wwwPath
                                             error:&error];

    if (!copySuccess) {
        NSLog(@"[HotUpdates] Failed to install update: %@", error);

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:[self createError:kErrorInstallFailed
                                                                                message:[NSString stringWithFormat:@"Install failed: %@", error.localizedDescription]]];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }

    NSString *newVersion = versionToInstall;

    [[NSUserDefaults standardUserDefaults] setObject:newVersion forKey:kInstalledVersion];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kPendingUpdateReady];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kHasPending];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPendingUpdateURL];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPendingVersion];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCanaryVersion];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSString *tempUpdatePath = [documentsPath stringByAppendingPathComponent:@"temp_downloaded_update"];
    NSString *pendingPath = [documentsPath stringByAppendingPathComponent:kPendingUpdateDirName];
    [fileManager removeItemAtPath:tempUpdatePath error:nil];
    [fileManager removeItemAtPath:pendingPath error:nil];

    isUpdateReadyToInstall = NO;
    pendingUpdateURL = nil;
    pendingUpdateVersion = nil;

    NSLog(@"[HotUpdates] Update installed successfully");

    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];

    // После reloadWebView pluginInitialize НЕ вызывается, поэтому canary timer запускаем вручную
    NSLog(@"[HotUpdates] Starting canary timer (20 seconds) for version %@", newVersion);

    [self startCanaryTimer];

    hasPerformedInitialReload = NO;

    // Очищаем кэш WebView перед перезагрузкой, иначе может загрузиться старая версия
    [self clearWebViewCacheWithCompletion:^{
        [self reloadWebView];
    }];
}

#pragma mark - Canary

- (void)canary:(CDVInvokedUrlCommand*)command {
    // Безопасное получение первого аргумента
    NSString *canaryVersion = nil;
    if (command.arguments.count > 0 && [command.arguments[0] isKindOfClass:[NSString class]]) {
        canaryVersion = command.arguments[0];
    }

    if (!canaryVersion || canaryVersion.length == 0) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsDictionary:[self createError:kErrorVersionRequired
                                                                                message:@"Version is required"]];
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

    // ТЗ: при успехе callback возвращает null
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

#pragma mark - Debug Methods

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

@end
