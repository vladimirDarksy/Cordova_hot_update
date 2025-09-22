/*!
 * @file HotUpdates.m
 * @brief Cordova Hot Updates Plugin for iOS
 * @details Provides automatic background hot updates functionality for Cordova applications.
 *          Downloads and installs web content updates without requiring App Store updates.
 *
 *          Key Features:
 *          - Automatic background update checking
 *          - Seamless download and installation
 *          - WebView Reload approach for instant updates
 *          - Configurable update intervals
 *          - Version compatibility checks
 *
 * @version 1.0.0
 * @date 2025-09-22
 * @author Mustafin Vladimir
 * @copyright Copyright (c) 2025. All rights reserved.
 */

#import <Cordova/CDV.h>
#import <Cordova/CDVViewController.h>
#import "HotUpdates.h"

// Note: This plugin expects SSZipArchive to be available via CocoaPods
// Add to your Podfile: pod 'SSZipArchive'
#ifdef COCOAPODS
#import <SSZipArchive/SSZipArchive.h>
#else
#import "SSZipArchive.h"
#endif

@interface HotUpdates ()
{
    BOOL isDownloadingUpdate;
    NSMutableDictionary *progressCallbacks;
}
@end

@implementation HotUpdates

#pragma mark - Plugin Lifecycle Methods

/*!
 * @brief Initialize the Hot Updates plugin
 * @details Called automatically when the plugin is loaded by Cordova.
 *          Sets up configuration, initializes www folder, and starts background processes.
 */
- (void)pluginInitialize {
    [super pluginInitialize];

    // Initialize progress callbacks dictionary
    progressCallbacks = [[NSMutableDictionary alloc] init];

    // Get paths to directories
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    documentsPath = [paths objectAtIndex:0];
    wwwPath = [documentsPath stringByAppendingPathComponent:@"www"];

    // Load configuration
    [self loadConfiguration];

    NSLog(@"[HotUpdates] === STARTUP SEQUENCE ===");
    NSLog(@"[HotUpdates] 📁 Bundle www: %@", [[NSBundle mainBundle] pathForResource:@"www" ofType:nil]);
    NSLog(@"[HotUpdates] 📁 Documents www: %@", wwwPath);

    // 1. Check and install pending updates
    [self checkAndInstallPendingUpdate];

    // 2. Initialize www folder if needed (copy from bundle)
    [self initializeWWWFolder];

    // 3. Switch WebView to updated content and reload
    [self switchToUpdatedContentWithReload];

    // 4. Start background update process
    [self startBackgroundUpdateProcess];

    NSLog(@"[HotUpdates] Plugin initialized. All processes started automatically.");
}

- (void)loadConfiguration {
    // Get all settings from config.xml
    updateServerURL = [self.commandDelegate.settings objectForKey:@"hot_updates_server_url"];
    if (!updateServerURL) {
        updateServerURL = @"https://your-server.com/api/updates"; // Default URL
    }

    // Get app bundle version
    appBundleVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    if (!appBundleVersion) {
        appBundleVersion = @"1.0.0";
    }

    // Get check interval from config.xml
    NSString *checkIntervalStr = [self.commandDelegate.settings objectForKey:@"hot_updates_check_interval"];
    checkInterval = checkIntervalStr ? [checkIntervalStr doubleValue] / 1000.0 : 300.0; // Default 5 minutes

    NSLog(@"[HotUpdates] Configuration loaded:");
    NSLog(@"  Server URL: %@", updateServerURL);
    NSLog(@"  App bundle version: %@", appBundleVersion);
    NSLog(@"  Check interval: %.0f seconds", checkInterval);
}

/*!
 * @brief Check and install pending updates
 * @details Looks for pending updates and installs them to Documents/www
 */
- (void)checkAndInstallPendingUpdate {
    BOOL hasPendingUpdate = [[NSUserDefaults standardUserDefaults] boolForKey:@"hot_updates_has_pending"];
    NSString *pendingVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"hot_updates_pending_version"];
    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"hot_updates_installed_version"];

    if (hasPendingUpdate && pendingVersion && !installedVersion) {
        NSLog(@"[HotUpdates] 🚀 Installing pending update %@ to Documents/www...", pendingVersion);

        NSString *pendingUpdatePath = [documentsPath stringByAppendingPathComponent:@"pending_update"];
        NSString *pendingWwwPath = [pendingUpdatePath stringByAppendingPathComponent:@"www"];
        NSString *documentsWwwPath = [documentsPath stringByAppendingPathComponent:@"www"];

        if ([[NSFileManager defaultManager] fileExistsAtPath:pendingWwwPath]) {
            // Remove old Documents/www
            if ([[NSFileManager defaultManager] fileExistsAtPath:documentsWwwPath]) {
                [[NSFileManager defaultManager] removeItemAtPath:documentsWwwPath error:nil];
            }

            // Copy pending_update/www to Documents/www
            NSError *copyError = nil;
            BOOL copySuccess = [[NSFileManager defaultManager] copyItemAtPath:pendingWwwPath toPath:documentsWwwPath error:&copyError];

            if (copySuccess) {
                // Mark as installed
                [[NSUserDefaults standardUserDefaults] setObject:pendingVersion forKey:@"hot_updates_installed_version"];
                [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"hot_updates_has_pending"];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"hot_updates_pending_version"];
                [[NSUserDefaults standardUserDefaults] synchronize];

                // Clean up pending_update folder
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
    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"hot_updates_installed_version"];

    if (installedVersion) {
        NSString *documentsWwwPath = [documentsPath stringByAppendingPathComponent:@"www"];
        NSString *indexPath = [documentsWwwPath stringByAppendingPathComponent:@"index.html"];

        // Check that files actually exist
        if ([[NSFileManager defaultManager] fileExistsAtPath:indexPath]) {
            NSLog(@"[HotUpdates] 🎯 WEBVIEW RELOAD APPROACH!");
            NSLog(@"[HotUpdates] Found installed update version: %@", installedVersion);

            // Set new path
            ((CDVViewController *)self.viewController).wwwFolderName = documentsWwwPath;
            NSLog(@"[HotUpdates] ✅ Changed wwwFolderName to: %@", documentsWwwPath);

            // Force reload WebView to apply new path
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
 * @details Uses WKWebView reload method to refresh content from new wwwFolderName path
 */
- (void)reloadWebView {
    // Cast to CDVViewController type for access to webViewEngine
    if ([self.viewController isKindOfClass:[CDVViewController class]]) {
        CDVViewController *cdvViewController = (CDVViewController *)self.viewController;

        // Build new URL for updated content
        NSString *documentsWwwPath = [documentsPath stringByAppendingPathComponent:@"www"];
        NSString *indexPath = [documentsWwwPath stringByAppendingPathComponent:@"index.html"];
        NSURL *newURL = [NSURL fileURLWithPath:indexPath];

        NSLog(@"[HotUpdates] 🔄 Loading WebView with new URL: %@", newURL.absoluteString);

        id webViewEngine = cdvViewController.webViewEngine;
        if (webViewEngine && [webViewEngine respondsToSelector:@selector(engineWebView)]) {
            // Get WKWebView
            WKWebView *webView = [webViewEngine performSelector:@selector(engineWebView)];

            if (webView && [webView isKindOfClass:[WKWebView class]]) {
                // Load new URL instead of simple reload
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSURLRequest *request = [NSURLRequest requestWithURL:newURL];
                    [webView loadRequest:request];
                    NSLog(@"[HotUpdates] ✅ WebView loadRequest executed with updated URL");
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

    // Check if www folder exists in Documents
    if (![fileManager fileExistsAtPath:wwwPath]) {
        NSLog(@"[HotUpdates] WWW folder not found in Documents. Creating and copying from bundle...");

        // Copy www contents from bundle to Documents
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

#pragma mark - Background Update Methods

- (void)installPendingUpdate:(NSString*)newVersion {
    NSLog(@"[HotUpdates] 🚀 INSTALLING UPDATE %@ AUTOMATICALLY...", newVersion);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;

    NSString *pendingUpdatePath = [documentsPath stringByAppendingPathComponent:@"pending_update"];
    NSString *pendingWWWPath = [pendingUpdatePath stringByAppendingPathComponent:@"www"];

    // Check that ready update exists
    if (![fileManager fileExistsAtPath:pendingWWWPath]) {
        NSLog(@"[HotUpdates] ❌ Error: Pending update not found at %@", pendingWWWPath);
        return;
    }

    NSLog(@"[HotUpdates] 📂 Installing update to Documents/www: %@", wwwPath);

    // Create backup of current www folder
    NSString *backupPath = [documentsPath stringByAppendingPathComponent:@"www_backup"];
    if ([fileManager fileExistsAtPath:backupPath]) {
        [fileManager removeItemAtPath:backupPath error:nil];
    }

    // Create backup only if www folder exists
    if ([fileManager fileExistsAtPath:wwwPath]) {
        [fileManager moveItemAtPath:wwwPath toPath:backupPath error:&error];
        if (error) {
            NSLog(@"[HotUpdates] ⚠️ Warning: Could not create backup: %@", error.localizedDescription);
        } else {
            NSLog(@"[HotUpdates] Backup created successfully");
        }
    }

    NSLog(@"[HotUpdates] Installing new version...");

    // Move new version
    [fileManager moveItemAtPath:pendingWWWPath toPath:wwwPath error:&error];

    if (error) {
        NSLog(@"[HotUpdates] ❌ ERROR installing update: %@", error.localizedDescription);

        // Restore from backup
        if ([fileManager fileExistsAtPath:backupPath]) {
            NSLog(@"[HotUpdates] Restoring from backup...");
            [fileManager moveItemAtPath:backupPath toPath:wwwPath error:nil];
        }

        // Remove corrupted update
        [fileManager removeItemAtPath:pendingUpdatePath error:nil];
        return;
    }

    // Save information about new installed version
    [[NSUserDefaults standardUserDefaults] setObject:newVersion forKey:@"hot_updates_installed_version"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"hot_updates_pending_version"];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"hot_updates_has_pending"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // Clean up temporary files
    [fileManager removeItemAtPath:pendingUpdatePath error:nil];
    [fileManager removeItemAtPath:backupPath error:nil];

    NSLog(@"[HotUpdates] ✅ UPDATE INSTALLED SUCCESSFULLY!");
    NSLog(@"[HotUpdates] 🎉 App updated from bundle version to %@", newVersion);
    NSLog(@"[HotUpdates] 📂 Files updated in Documents/www - WebView will load via URL interception");
}

- (void)startBackgroundUpdateProcess {
    NSLog(@"[HotUpdates] Starting AUTOMATIC background update process:");
    NSLog(@"  - Check interval: %.0f seconds", checkInterval);
    NSLog(@"  - Auto-download: YES");
    NSLog(@"  - Auto-install on next launch: YES");

    // Start first check after 30 seconds after startup (so app has time to load)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"[HotUpdates] Starting initial background check...");
        [self performAutomaticUpdateCheck];
    });

    // Set up periodic automatic checking
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

    // Check if there's already a ready update
    BOOL hasPending = [[NSUserDefaults standardUserDefaults] boolForKey:@"hot_updates_has_pending"];
    if (hasPending) {
        NSString *pendingVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"hot_updates_pending_version"];
        NSLog(@"[HotUpdates] Automatic check skipped - update %@ already downloaded and ready", pendingVersion);
        return;
    }

    NSLog(@"[HotUpdates] Performing AUTOMATIC update check...");

    // Get current installed version (may differ from bundle version)
    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"hot_updates_installed_version"];
    NSString *checkVersion = installedVersion ?: appBundleVersion;

    // Create URL for update checking
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

                // Check minAppVersion if specified
                if (minAppVersion) {
                    NSComparisonResult comparison = [self compareVersion:appBundleVersion withVersion:minAppVersion];
                    if (comparison == NSOrderedAscending) {
                        NSLog(@"[HotUpdates] ❌ Update skipped: requires app version %@ but current is %@", minAppVersion, appBundleVersion);
                        return;
                    } else {
                        NSLog(@"[HotUpdates] ✅ App version %@ meets minimum requirement %@", appBundleVersion, minAppVersion);
                    }
                } else {
                    NSLog(@"[HotUpdates] No minAppVersion requirement specified");
                }

                NSLog(@"[HotUpdates] Starting automatic download...");

                // Automatically start download
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

    // Create session configuration for background download
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 60.0;
    config.timeoutIntervalForResource = 300.0; // 5 minutes for download

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

    // Create folder for ready update
    NSString *pendingUpdatePath = [documentsPath stringByAppendingPathComponent:@"pending_update"];

    // Remove old ready update if exists
    if ([fileManager fileExistsAtPath:pendingUpdatePath]) {
        NSLog(@"[HotUpdates] Removing old pending update...");
        [fileManager removeItemAtPath:pendingUpdatePath error:nil];
    }

    // Create folder for new update
    [fileManager createDirectoryAtPath:pendingUpdatePath withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
        NSLog(@"[HotUpdates] ❌ Error creating pending update directory: %@", error.localizedDescription);
        return;
    }

    NSLog(@"[HotUpdates] Extracting update package...");

    // Extract update
    BOOL success = [self unzipFile:updateLocation.path toDestination:pendingUpdatePath];
    if (!success) {
        NSLog(@"[HotUpdates] ❌ Error extracting update package");
        [fileManager removeItemAtPath:pendingUpdatePath error:nil];
        return;
    }

    // Check that www folder was created
    NSString *pendingWWWPath = [pendingUpdatePath stringByAppendingPathComponent:@"www"];
    if (![fileManager fileExistsAtPath:pendingWWWPath]) {
        NSLog(@"[HotUpdates] ❌ Error: www folder not found in update package");
        [fileManager removeItemAtPath:pendingUpdatePath error:nil];
        return;
    }

    // Save version information
    NSString *versionPath = [pendingUpdatePath stringByAppendingPathComponent:@"version.txt"];
    [newVersion writeToFile:versionPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    // Save information about ready update in UserDefaults
    [[NSUserDefaults standardUserDefaults] setObject:newVersion forKey:@"hot_updates_pending_version"];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"hot_updates_has_pending"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSLog(@"[HotUpdates] ✅ UPDATE %@ PREPARED SUCCESSFULLY!", newVersion);
    NSLog(@"[HotUpdates] 📱 Update will be AUTOMATICALLY INSTALLED on next app launch");
    NSLog(@"[HotUpdates] Bundle version: %@, Pending version: %@", appBundleVersion, newVersion);
}

- (BOOL)unzipFile:(NSString*)zipPath toDestination:(NSString*)destination {
    NSLog(@"[HotUpdates] 📦 Unzipping %@ to %@", zipPath, destination);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;

    // Create destination folder if it doesn't exist
    if (![fileManager fileExistsAtPath:destination]) {
        [fileManager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"[HotUpdates] ❌ Error creating destination directory: %@", error.localizedDescription);
            return NO;
        }
    }

    // Extract ZIP archive with SSZipArchive
    NSLog(@"[HotUpdates] 📦 Extracting ZIP archive using SSZipArchive library...");

    // Simple file check
    if (![[NSFileManager defaultManager] fileExistsAtPath:zipPath]) {
        NSLog(@"[HotUpdates] ❌ ZIP file does not exist: %@", zipPath);
        return NO;
    }

    // Create temporary folder for extraction
    NSString *tempExtractPath = [destination stringByAppendingPathComponent:@"temp_extract"];

    // Remove existing temporary folder
    if ([[NSFileManager defaultManager] fileExistsAtPath:tempExtractPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:tempExtractPath error:nil];
    }

    // Create temporary folder
    if (![[NSFileManager defaultManager] createDirectoryAtPath:tempExtractPath withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"[HotUpdates] ❌ Failed to create temp extraction folder: %@", error.localizedDescription);
        return NO;
    }

    NSLog(@"[HotUpdates] 📦 Extracting to temp location: %@", tempExtractPath);

    // Extract ZIP archive
    BOOL extractSuccess = [SSZipArchive unzipFileAtPath:zipPath toDestination:tempExtractPath];

    if (extractSuccess) {
        NSLog(@"[HotUpdates] ✅ ZIP extraction successful!");

        // Check contents of extracted archive
        NSArray *extractedContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tempExtractPath error:nil];
        NSLog(@"[HotUpdates] 📂 Extracted contents: %@", extractedContents);

        // Look for www folder in extracted contents
        NSString *wwwSourcePath = nil;
        for (NSString *item in extractedContents) {
            NSString *itemPath = [tempExtractPath stringByAppendingPathComponent:item];
            BOOL isDirectory;
            if ([[NSFileManager defaultManager] fileExistsAtPath:itemPath isDirectory:&isDirectory] && isDirectory) {
                if ([item isEqualToString:@"www"]) {
                    wwwSourcePath = itemPath;
                    break;
                }
                // Check if www is inside the folder
                NSString *nestedWwwPath = [itemPath stringByAppendingPathComponent:@"www"];
                if ([[NSFileManager defaultManager] fileExistsAtPath:nestedWwwPath]) {
                    wwwSourcePath = nestedWwwPath;
                    break;
                }
            }
        }

        if (wwwSourcePath) {
            NSLog(@"[HotUpdates] 📁 Found www folder at: %@", wwwSourcePath);

            // Copy www folder to final location
            NSString *finalWwwPath = [destination stringByAppendingPathComponent:@"www"];

            // Remove existing www folder if exists
            if ([[NSFileManager defaultManager] fileExistsAtPath:finalWwwPath]) {
                [[NSFileManager defaultManager] removeItemAtPath:finalWwwPath error:nil];
            }

            // Copy new www folder
            NSError *copyError = nil;
            BOOL copySuccess = [[NSFileManager defaultManager] copyItemAtPath:wwwSourcePath toPath:finalWwwPath error:&copyError];

            if (copySuccess) {
                NSLog(@"[HotUpdates] ✅ www folder copied successfully to: %@", finalWwwPath);

                // Clean up temporary folder
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

        // Clean up temporary folder on error
        [[NSFileManager defaultManager] removeItemAtPath:tempExtractPath error:nil];
    } else {
        NSLog(@"[HotUpdates] ❌ Failed to extract ZIP archive");
        // Clean up temporary folder on error
        [[NSFileManager defaultManager] removeItemAtPath:tempExtractPath error:nil];
    }

    NSLog(@"[HotUpdates] ❌ ZIP extraction failed");
    return NO;
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

    // Split versions into components
    NSArray *components1 = [version1 componentsSeparatedByString:@"."];
    NSArray *components2 = [version2 componentsSeparatedByString:@"."];

    // Find maximum number of components
    NSUInteger maxComponents = MAX(components1.count, components2.count);

    for (NSUInteger i = 0; i < maxComponents; i++) {
        // Get component or 0 if component doesn't exist
        NSInteger component1 = (i < components1.count) ? [components1[i] integerValue] : 0;
        NSInteger component2 = (i < components2.count) ? [components2[i] integerValue] : 0;

        if (component1 < component2) {
            return NSOrderedAscending;
        } else if (component1 > component2) {
            return NSOrderedDescending;
        }
        // If equal, continue to next component
    }

    // All components are equal
    return NSOrderedSame;
}

#pragma mark - JavaScript Callable Methods

- (void)getCurrentVersion:(CDVInvokedUrlCommand*)command {
    // Return current active version (installed update or bundle version)
    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"hot_updates_installed_version"];
    NSString *actualVersion = installedVersion ?: appBundleVersion;

    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:actualVersion];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)getPendingUpdateInfo:(CDVInvokedUrlCommand*)command {
    BOOL hasPending = [[NSUserDefaults standardUserDefaults] boolForKey:@"hot_updates_has_pending"];

    if (hasPending) {
        NSString *pendingVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"hot_updates_pending_version"];
        NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"hot_updates_installed_version"];

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

- (void)checkForUpdates:(CDVInvokedUrlCommand*)command {
    // Get current installed version (may differ from bundle version)
    NSString *installedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"hot_updates_installed_version"];
    NSString *checkVersion = installedVersion ?: appBundleVersion;

    // Create URL for update checking
    NSString *checkURL = [NSString stringWithFormat:@"%@/check?version=%@&platform=ios", updateServerURL, checkVersion];
    NSURL *url = [NSURL URLWithString:checkURL];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }

        if (data) {
            NSError *jsonError;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

            if (jsonError) {
                CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:jsonError.localizedDescription];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                return;
            }

            BOOL hasUpdate = [[responseDict objectForKey:@"hasUpdate"] boolValue];

            NSDictionary *result = @{
                @"hasUpdate": @(hasUpdate),
                @"currentVersion": checkVersion,
                @"availableVersion": hasUpdate ? [responseDict objectForKey:@"version"] : [NSNull null],
                @"downloadURL": hasUpdate ? [responseDict objectForKey:@"downloadURL"] : [NSNull null],
                @"minAppVersion": hasUpdate ? ([responseDict objectForKey:@"minAppVersion"] ?: [NSNull null]) : [NSNull null]
            };

            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }];

    [task resume];
}

- (void)downloadUpdate:(CDVInvokedUrlCommand*)command {
    NSString *downloadURL = [command argumentAtIndex:0];
    NSString *version = [command argumentAtIndex:1];
    NSString *callbackId = [command argumentAtIndex:2 withDefault:nil];

    if (!downloadURL || !version) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Missing downloadURL or version parameter"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    if (isDownloadingUpdate) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Download already in progress"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    isDownloadingUpdate = YES;
    NSLog(@"[HotUpdates] 📥 MANUAL DOWNLOAD STARTED for version %@", version);

    NSURL *url = [NSURL URLWithString:downloadURL];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 60.0;
    config.timeoutIntervalForResource = 300.0;

    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:url
                                                        completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        self->isDownloadingUpdate = NO;

        if (error) {
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSString *errorMsg = [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode];
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMsg];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }

        NSLog(@"[HotUpdates] ✅ MANUAL DOWNLOAD COMPLETED successfully");

        [self prepareUpdateForNextLaunch:location version:version];

        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Download completed successfully"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];

    [downloadTask resume];
}

- (void)getConfiguration:(CDVInvokedUrlCommand*)command {
    NSDictionary *config = @{
        @"serverURL": updateServerURL,
        @"checkInterval": @(checkInterval * 1000), // Convert to milliseconds
        @"appBundleVersion": appBundleVersion,
        @"autoDownload": @YES
    };

    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:config];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)installUpdate:(CDVInvokedUrlCommand*)command {
    // This would require app restart, which is not trivial to implement
    // For now, return an error suggesting manual restart
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsString:@"Immediate installation requires app restart. Please restart the app manually."];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setProgressCallback:(CDVInvokedUrlCommand*)command {
    NSString *callbackId = [command argumentAtIndex:0];
    if (callbackId) {
        [progressCallbacks setObject:command.callbackId forKey:callbackId];
    }
}

@end