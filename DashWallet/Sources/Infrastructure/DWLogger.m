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

#import "DWLogger.h"

NS_ASSUME_NONNULL_BEGIN

// Thread name helper - returns current thread name or identifier
NSString *DWCurrentThreadName(void) {
    NSThread *thread = [NSThread currentThread];
    NSString *name = thread.name;
    if (name.length > 0) {
        return name;
    }
    if ([thread isMainThread]) {
        return @"main";
    }
    // Use thread number as fallback
    NSString *description = thread.description;
    NSRange numRange = [description rangeOfString:@"number = "];
    if (numRange.location != NSNotFound) {
        NSUInteger start = numRange.location + numRange.length;
        NSRange endRange = [description rangeOfString:@"," options:0 range:NSMakeRange(start, description.length - start)];
        if (endRange.location != NSNotFound) {
            return [NSString stringWithFormat:@"Thread-%@", [description substringWithRange:NSMakeRange(start, endRange.location - start)]];
        }
    }
    return @"Thread";
}

// Custom log formatter that adds timestamp in Android format (HH:MM:SS)
@interface DWAndroidStyleLogFormatter : NSObject <DDLogFormatter>
@end

@implementation DWAndroidStyleLogFormatter

- (nullable NSString *)formatLogMessage:(DDLogMessage *)logMessage {
    // Get time components
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    });
    NSString *timestamp = [formatter stringFromDate:logMessage.timestamp];

    // The message already contains [thread] ClassName - message format from our macros
    return [NSString stringWithFormat:@"%@ %@", timestamp, logMessage.message];
}

@end

@interface DWLogger ()

@property (readonly, nonatomic, strong) DDFileLogger *fileLogger;

@end

@implementation DWLogger

+ (instancetype)sharedInstance {
    static DWLogger *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        DWAndroidStyleLogFormatter *formatter = [[DWAndroidStyleLogFormatter alloc] init];

        // Console logger with formatter
        DDOSLogger *osLogger = [DDOSLogger sharedInstance];
        [osLogger setLogFormatter:formatter];
        [DDLog addLogger:osLogger];

        // File logger with formatter. Uses CocoaLumberjack's default file
        // manager (no gzip compression of rolled logs — see the header note);
        // same rolling policy DSLogger used.
        unsigned long long maxFileSize = 1024 * 1024 * 5; // 5 MB max
        DDFileLogger *fileLogger = [[DDFileLogger alloc] init];
        fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling
        fileLogger.maximumFileSize = maxFileSize;
        fileLogger.logFileManager.maximumNumberOfLogFiles = 10;
        [fileLogger setLogFormatter:formatter];

        [DDLog addLogger:fileLogger];
        _fileLogger = fileLogger;

        // Log version info at startup
        [DWLogger logVersionInfo];
    }
    return self;
}

- (NSArray<NSURL *> *)logFiles {
    NSString *logsDirectory = [self.fileLogger.logFileManager logsDirectory];
    NSArray *fileNames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:logsDirectory error:nil];
    NSMutableArray *logFiles = [NSMutableArray arrayWithCapacity:[fileNames count]];

    for (NSString *fileName in fileNames) {
        BOOL hasProperSuffix = [fileName hasSuffix:@".log"] || [fileName hasSuffix:@".gz"];

        if (hasProperSuffix) {
            NSString *filePath = [logsDirectory stringByAppendingPathComponent:fileName];
            NSURL *fileURL = [NSURL fileURLWithPath:filePath];

            if (fileURL) {
                [logFiles addObject:fileURL];
            }
        }
    }

    return [logFiles copy];
}

+ (void)log:(NSString *)message {
    DDLogInfo(@"%@", message);
}

+ (void)log:(NSString *)message className:(NSString *)className {
    DWLogInfo(className, @"%@", message);
}

+ (void)logVersionInfo {
    // Get host app version info
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *appVersion = mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"Unknown";
    NSString *appBuild = mainBundle.infoDictionary[@"CFBundleVersion"] ?: @"Unknown";
    NSString *appName = mainBundle.infoDictionary[@"CFBundleDisplayName"] ?: mainBundle.infoDictionary[@"CFBundleName"] ?
                                                                                                                        : @"DashWallet";

    DWLogInfo(@"DWLogger", @"===== Application Startup =====");
    DWLogInfo(@"DWLogger", @"%@ v%@ (build %@)", appName, appVersion, appBuild);
    DWLogInfo(@"DWLogger", @"===============================");
}

@end

NS_ASSUME_NONNULL_END
