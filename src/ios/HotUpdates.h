/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import <UIKit/UIKit.h>
#import <Cordova/CDVPlugin.h>

/**
 * Cordova Hot Updates Plugin for iOS
 *
 * Provides automatic over-the-air (OTA) updates for Cordova applications
 * using the WebView Reload approach for instant updates.
 *
 * Key Features:
 * - Automatic background update checking and downloading
 * - Seamless installation using wwwFolderName switching
 * - Version compatibility checks with semantic versioning
 * - Configurable update intervals and server endpoints
 * - No AppDelegate modifications required
 *
 * Architecture:
 * - Uses Documents/www folder for updated content
 * - Switches WebView to load from Documents instead of bundle
 * - Maintains backward compatibility with bundle version
 * - Supports rollback mechanisms
 *
 * @version 1.0.0
 * @author Mustafin Vladimir
 */
@interface HotUpdates : CDVPlugin
{
    NSString *documentsPath;
    NSString *wwwPath;
    NSString *updateServerURL;
    NSString *appBundleVersion;
    NSTimer *updateCheckTimer;
    NSTimeInterval checkInterval;
}

#pragma mark - Plugin Lifecycle Methods

/**
 * Initialize the Hot Updates plugin
 * Called automatically when the plugin is loaded by Cordova
 */
- (void)pluginInitialize;

/**
 * Load configuration from config.xml
 */
- (void)loadConfiguration;

/**
 * Initialize www folder in Documents directory
 */
- (void)initializeWWWFolder;

#pragma mark - Update Management Methods

/**
 * Check for pending updates on startup and install them
 */
- (void)checkAndInstallPendingUpdate;

/**
 * Switch WebView to updated content and reload
 */
- (void)switchToUpdatedContentWithReload;

/**
 * Force reload the WebView with new content
 */
- (void)reloadWebView;

/**
 * Install pending update to Documents/www
 * @param newVersion Version string of the update to install
 */
- (void)installPendingUpdate:(NSString*)newVersion;

/**
 * Start background update checking process
 */
- (void)startBackgroundUpdateProcess;

/**
 * Perform automatic update check
 */
- (void)performAutomaticUpdateCheck;

/**
 * Download update automatically in background
 * @param downloadURL URL to download the update from
 * @param newVersion Version string of the update
 */
- (void)downloadUpdateAutomatically:(NSString*)downloadURL version:(NSString*)newVersion;

/**
 * Prepare downloaded update for next launch
 * @param updateLocation Local file URL of downloaded update
 * @param newVersion Version string of the update
 */
- (void)prepareUpdateForNextLaunch:(NSURL*)updateLocation version:(NSString*)newVersion;

/**
 * Unzip update file to destination
 * @param zipPath Path to ZIP file
 * @param destinationPath Destination directory path
 * @return YES if successful, NO if failed
 */
- (BOOL)unzipFile:(NSString*)zipPath toDestination:(NSString*)destinationPath;

#pragma mark - Version Comparison Utilities

/**
 * Compare two semantic version strings
 * @param version1 First version string (e.g., "2.7.7")
 * @param version2 Second version string (e.g., "2.8.0")
 * @return NSComparisonResult indicating the relationship between the versions
 */
- (NSComparisonResult)compareVersion:(NSString*)version1 withVersion:(NSString*)version2;

#pragma mark - JavaScript Callable Methods

/**
 * Get current version information
 * @param command CDVInvokedUrlCommand from JavaScript
 */
- (void)getCurrentVersion:(CDVInvokedUrlCommand*)command;

/**
 * Get pending update information
 * @param command CDVInvokedUrlCommand from JavaScript
 */
- (void)getPendingUpdateInfo:(CDVInvokedUrlCommand*)command;

/**
 * Check for updates manually
 * @param command CDVInvokedUrlCommand from JavaScript
 */
- (void)checkForUpdates:(CDVInvokedUrlCommand*)command;

/**
 * Download specific update
 * @param command CDVInvokedUrlCommand from JavaScript with [downloadURL, version, callbackId]
 */
- (void)downloadUpdate:(CDVInvokedUrlCommand*)command;

/**
 * Get plugin configuration
 * @param command CDVInvokedUrlCommand from JavaScript
 */
- (void)getConfiguration:(CDVInvokedUrlCommand*)command;

/**
 * Install pending update immediately (requires app restart)
 * @param command CDVInvokedUrlCommand from JavaScript
 */
- (void)installUpdate:(CDVInvokedUrlCommand*)command;

/**
 * Set progress callback for downloads
 * @param command CDVInvokedUrlCommand from JavaScript
 */
- (void)setProgressCallback:(CDVInvokedUrlCommand*)command;

@end