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
#import "HotUpdatesConstants.h"

@interface HotUpdates : CDVPlugin
{
    NSString *documentsPath;
    NSString *wwwPath;
    NSString *appBundleVersion;

    // Settings
    NSMutableArray *ignoreList;       // Список игнорируемых версий (управляется только native)
    NSString *previousVersionPath;    // Путь к предыдущей версии
}

// JavaScript API methods (v2.1.0)
- (void)getUpdate:(CDVInvokedUrlCommand*)command;      // Download update
- (void)forceUpdate:(CDVInvokedUrlCommand*)command;    // Install downloaded update
- (void)canary:(CDVInvokedUrlCommand*)command;         // Confirm successful load
- (void)getIgnoreList:(CDVInvokedUrlCommand*)command;  // Get ignore list (JS reads only)

// Debug method
- (void)getVersionInfo:(CDVInvokedUrlCommand*)command; // Get all version info for debugging

@end
