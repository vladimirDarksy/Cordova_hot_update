/*!
 * @file HotUpdatesConstants.h
 * @brief Constants for Hot Updates Plugin
 * @details Contains error codes, storage keys, and directory names used by the plugin
 * @version 2.1.0
 * @date 2025-11-13
 * @author Mustafin Vladimir
 * @copyright Copyright (c) 2025. All rights reserved.
 */

#ifndef HotUpdatesConstants_h
#define HotUpdatesConstants_h

#pragma mark - Error Codes

// Error codes returned to JavaScript
extern NSString * const kErrorUpdateDataRequired;
extern NSString * const kErrorURLRequired;
extern NSString * const kErrorDownloadInProgress;
extern NSString * const kErrorDownloadFailed;
extern NSString * const kErrorHTTPError;
extern NSString * const kErrorTempDirError;
extern NSString * const kErrorExtractionFailed;
extern NSString * const kErrorWWWNotFound;
extern NSString * const kErrorNoUpdateReady;
extern NSString * const kErrorUpdateFilesNotFound;
extern NSString * const kErrorInstallFailed;
extern NSString * const kErrorVersionRequired;

#pragma mark - Storage Keys

// NSUserDefaults keys
extern NSString * const kInstalledVersion;
extern NSString * const kPendingVersion;
extern NSString * const kHasPending;
extern NSString * const kPreviousVersion;
extern NSString * const kIgnoreList;
extern NSString * const kCanaryVersion;
extern NSString * const kDownloadInProgress;
extern NSString * const kPendingUpdateURL;
extern NSString * const kPendingUpdateReady;
extern NSString * const kVersionHistory;

#pragma mark - Directory Names

// Directory names
extern NSString * const kWWWDirName;
extern NSString * const kPreviousWWWDirName;
extern NSString * const kBackupWWWDirName;
extern NSString * const kPendingUpdateDirName;

#endif /* HotUpdatesConstants_h */
