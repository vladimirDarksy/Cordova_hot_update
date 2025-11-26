/*!
 * @file HotUpdatesConstants.m
 * @brief Implementation of constants for Hot Updates Plugin
 * @details Defines all constant values used throughout the plugin
 * @version 2.1.0
 * @date 2025-11-13
 * @author Mustafin Vladimir
 * @copyright Copyright (c) 2025. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "HotUpdatesConstants.h"

#pragma mark - Error Codes

NSString * const kErrorUpdateDataRequired = @"UPDATE_DATA_REQUIRED";
NSString * const kErrorURLRequired = @"URL_REQUIRED";
NSString * const kErrorDownloadInProgress = @"DOWNLOAD_IN_PROGRESS";
NSString * const kErrorDownloadFailed = @"DOWNLOAD_FAILED";
NSString * const kErrorHTTPError = @"HTTP_ERROR";
NSString * const kErrorTempDirError = @"TEMP_DIR_ERROR";
NSString * const kErrorExtractionFailed = @"EXTRACTION_FAILED";
NSString * const kErrorWWWNotFound = @"WWW_NOT_FOUND";
NSString * const kErrorNoUpdateReady = @"NO_UPDATE_READY";
NSString * const kErrorUpdateFilesNotFound = @"UPDATE_FILES_NOT_FOUND";
NSString * const kErrorInstallFailed = @"INSTALL_FAILED";
NSString * const kErrorVersionRequired = @"VERSION_REQUIRED";

#pragma mark - Storage Keys

NSString * const kInstalledVersion = @"hot_updates_installed_version";
NSString * const kPendingVersion = @"hot_updates_pending_version";
NSString * const kHasPending = @"hot_updates_has_pending";
NSString * const kPreviousVersion = @"hot_updates_previous_version";
NSString * const kIgnoreList = @"hot_updates_ignore_list";
NSString * const kCanaryVersion = @"hot_updates_canary_version";
NSString * const kDownloadInProgress = @"hot_updates_download_in_progress";
NSString * const kPendingUpdateURL = @"hot_updates_pending_update_url";
NSString * const kPendingUpdateReady = @"hot_updates_pending_ready";

#pragma mark - Directory Names

NSString * const kWWWDirName = @"www";
NSString * const kPreviousWWWDirName = @"www_previous";
NSString * const kBackupWWWDirName = @"www_backup";
NSString * const kPendingUpdateDirName = @"pending_update";
