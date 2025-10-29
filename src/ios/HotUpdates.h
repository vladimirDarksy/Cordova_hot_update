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
@interface HotUpdates : CDVPlugin
{
    NSString *documentsPath;
    NSString *wwwPath;
    NSString *updateServerURL;
    NSString *appBundleVersion;
    NSTimer *updateCheckTimer;

    // Settings
    BOOL autoUpdateEnabled;           // Флаг автообновлений
    BOOL firstLaunchDone;             // Первый запуск выполнен
    NSMutableArray *ignoreList;       // Список игнорируемых версий
    NSString *previousVersionPath;    // Путь к предыдущей версии
}

// Plugin lifecycle methods
- (void)pluginInitialize;
- (void)loadConfiguration;
- (void)initializeWWWFolder;
- (void)checkAndInstallPendingUpdate;
- (void)switchToUpdatedContentWithReload;
- (void)reloadWebView;

// Update management methods
- (void)installPendingUpdate:(NSString*)newVersion;
- (void)startBackgroundUpdateProcess;
- (void)performAutomaticUpdateCheck;
- (void)downloadUpdateAutomatically:(NSString*)downloadURL version:(NSString*)newVersion;
- (void)prepareUpdateForNextLaunch:(NSURL*)updateLocation version:(NSString*)newVersion;
- (BOOL)unzipFile:(NSString *)zipPath toDestination:(NSString *)destinationPath;

// Version comparison utilities
- (NSComparisonResult)compareVersion:(NSString*)version1 withVersion:(NSString*)version2;

// JavaScript callable methods (minimal set for debugging)
- (void)getCurrentVersion:(CDVInvokedUrlCommand*)command;
- (void)getPendingUpdateInfo:(CDVInvokedUrlCommand*)command;

// Settings management
- (void)setAutoUpdateEnabled:(CDVInvokedUrlCommand*)command;
- (void)addToIgnoreList:(CDVInvokedUrlCommand*)command;
- (void)removeFromIgnoreList:(CDVInvokedUrlCommand*)command;
- (void)clearIgnoreList:(CDVInvokedUrlCommand*)command;
- (void)getIgnoreListJS:(CDVInvokedUrlCommand*)command;

// Update methods
- (void)forceUpdate:(CDVInvokedUrlCommand*)command;
- (void)canary:(CDVInvokedUrlCommand*)command;
- (void)rollback:(CDVInvokedUrlCommand*)command;
- (void)checkForUpdates:(CDVInvokedUrlCommand*)command;

// Information methods
- (void)getVersionInfo:(CDVInvokedUrlCommand*)command;

@end
