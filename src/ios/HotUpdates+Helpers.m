/*!
 * @file HotUpdates+Helpers.m
 * @brief Implementation of helper methods for Hot Updates Plugin
 * @details Provides utility methods for error handling and response formatting
 * @version 2.2.0
 * @date 2025-11-13
 * @author Mustafin Vladimir
 * @copyright Copyright (c) 2025. All rights reserved.
 */

#import "HotUpdates+Helpers.h"

@implementation HotUpdates (Helpers)

- (NSDictionary*)createError:(NSString*)code message:(NSString*)message {
    return @{
        @"error": @{
            @"code": code,
            @"message": message
        }
    };
}

@end
