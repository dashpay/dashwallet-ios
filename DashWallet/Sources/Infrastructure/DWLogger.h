//
//  Created by Dash Core Group.
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

// App-owned logging facade, ported from DashSync's `DSLogger` so the app no
// longer depends on the pod for logging. A thin wrapper over CocoaLumberjack
// (already a project dependency): a console (OSLog) logger plus a rolling file
// logger whose files back the "Share application logs" feature. Ported 1:1
// from `DSLogger` except the rolled-log gzip compression (DashSync's
// `CompressingLogFileManager`) is replaced by CocoaLumberjack's default file
// manager — same 5 MB / 24 h / 10-file rolling; rolled logs stay `.log`
// instead of `.gz` (the share UI already handles both).

#import <Foundation/Foundation.h>

#import <CocoaLumberjack/CocoaLumberjack.h>

// App-owned log-level symbol. CocoaLumberjack's DDLog* macros read the level
// from `LOG_LEVEL_DEF` (default `ddLogLevel`); we point it at our own
// `dwLogLevel` so this header never collides with DashSync's `DSLogger.h`
// (which defines `ddLogLevel` and is still transitively imported while the pod
// is linked). Same level values DSLogger used. At the final DashSync unlink,
// this can revert to the plain `ddLogLevel` name.
#ifdef DEBUG
static const DDLogLevel dwLogLevel = DDLogLevelVerbose;
#else
static const DDLogLevel dwLogLevel = DDLogLevelInfo;
#endif /* DEBUG */

#undef LOG_LEVEL_DEF
#define LOG_LEVEL_DEF dwLogLevel

NS_ASSUME_NONNULL_BEGIN

// Thread name helper
NSString *DWCurrentThreadName(void);

#pragma mark - Android-style logging macros
// Format: "HH:MM:SS [thread] ClassName - message"

#define DWLogInfo(className, frmt, ...) DDLogInfo(@"[%@] %@ - " frmt, DWCurrentThreadName(), className, ##__VA_ARGS__)
#define DWLogDebug(className, frmt, ...) DDLogDebug(@"[%@] %@ - " frmt, DWCurrentThreadName(), className, ##__VA_ARGS__)
#define DWLogWarn(className, frmt, ...) DDLogWarn(@"[%@] %@ - " frmt, DWCurrentThreadName(), className, ##__VA_ARGS__)
#define DWLogError(className, frmt, ...) DDLogError(@"[%@] %@ - " frmt, DWCurrentThreadName(), className, ##__VA_ARGS__)

#ifdef DEBUG
#define DWLogVerbose(className, frmt, ...) DDLogVerbose(@"[%@] %@ - " frmt, DWCurrentThreadName(), className, ##__VA_ARGS__)
#else
#define DWLogVerbose(className, frmt, ...)
#endif /* DEBUG */

#pragma mark - Legacy logging macros

#define DWLog(frmt, ...) DDLogInfo(frmt, ##__VA_ARGS__)

#ifdef DEBUG
#define DWLogPrivate(s, ...) DDLogVerbose(s, ##__VA_ARGS__)
#else
#define DWLogPrivate(s, ...)
#endif /* DEBUG */

@interface DWLogger : NSObject

+ (instancetype)sharedInstance;

- (NSArray<NSURL *> *)logFiles;

/** @fn log:
 *  @brief This method logs a message with default class name
 *  @param message Final message to log
 */
+ (void)log:(NSString *)message;

/** @fn log:className:
 *  @brief This method logs a message with specified class name
 *  @param message Final message to log
 *  @param className The class name to include in the log
 */
+ (void)log:(NSString *)message className:(NSString *)className;

/** @fn logVersionInfo
 *  @brief Logs the app version at startup.
 */
+ (void)logVersionInfo;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
