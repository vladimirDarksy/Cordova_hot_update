/*!
 * @file HotUpdates+Helpers.h
 * @brief Helper methods for Hot Updates Plugin
 * @details Category extension providing utility methods for error handling
 * @version 2.2.0
 * @date 2025-11-13
 * @author Mustafin Vladimir
 * @copyright Copyright (c) 2025. All rights reserved.
 */

#import "HotUpdates.h"

@interface HotUpdates (Helpers)

/*!
 * @brief Create error dictionary for JavaScript callback
 * @param code Error code (e.g., "URL_REQUIRED")
 * @param message Detailed message for logs
 * @return Dictionary with error structure {error: {code: "...", message: "..."}}
 */
- (NSDictionary*)createError:(NSString*)code message:(NSString*)message;

@end
