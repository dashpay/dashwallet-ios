//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import "DWCrashReporter.h"

#import <mach/mach.h>
#import <mach/mach_host.h>
#include <sys/sysctl.h>
#import <sys/utsname.h>

#import <Dash-PLCrashReporter/PLCrashReporter.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const DW_CRASH_REPORTER_LAST_ASK_DATE = @"org.dash.crashreporter.last-ask-date";
static NSTimeInterval const DW_CRASH_REPORTER_REMIND_INTERVAL = 60 * 60 * 24 * 3; // 3 days

static NSString *FormatBytes(long long byteCount) {
    return [NSByteCountFormatter stringFromByteCount:byteCount
                                          countStyle:NSByteCountFormatterCountStyleBinary];
}

static NSString *DeviceModel() {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *deviceModel = [NSString stringWithUTF8String:systemInfo.machine];
    return deviceModel;
}

static NSString *OSInformation() {
    const char *ctlKey = "kern.osversion";

    size_t size;
    sysctlbyname(ctlKey, NULL, &size, NULL, 0);

    char *result = (char *)malloc(size);
    sysctlbyname(ctlKey, result, &size, NULL, 0);

    NSString *versionBuild = [NSString stringWithCString:result encoding:NSUTF8StringEncoding];
    free(result);

    NSString *osInfo = [NSString stringWithFormat:@"%@ %@ (%@)",
                                                  [UIDevice currentDevice].systemName,
                                                  [UIDevice currentDevice].systemVersion,
                                                  versionBuild];

    return osInfo;
}

static NSString *RamInformation() {
    mach_port_t host_port;
    mach_msg_type_number_t host_size;
    vm_size_t pagesize;

    host_port = mach_host_self();
    host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
    host_page_size(host_port, &pagesize);

    vm_statistics_data_t vm_stat;

    if (host_statistics(host_port, HOST_VM_INFO, (host_info_t)&vm_stat, &host_size) != KERN_SUCCESS) {
        NSLog(@"Failed to fetch vm statistics");
    }

    /* Stats in bytes */
    natural_t mem_used = (vm_stat.active_count +
                          vm_stat.inactive_count +
                          vm_stat.wire_count) *
                         pagesize;
    NSString *ramInfo = [NSString stringWithFormat:@"Used %@ / Total: %@",
                                                   FormatBytes(mem_used),
                                                   FormatBytes([NSProcessInfo processInfo].physicalMemory)];
    return ramInfo;
}

static NSString *DiskInformation() {
    NSDictionary *dictionary = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
    if (dictionary) {
        NSNumber *fileSystemSizeInBytes = dictionary[NSFileSystemSize];
        NSNumber *freeFileSystemSizeInBytes = dictionary[NSFileSystemFreeSize];
        NSString *diskInfo = [NSString stringWithFormat:@"Free %@ / Total: %@",
                                                        FormatBytes(freeFileSystemSizeInBytes.longLongValue),
                                                        FormatBytes(fileSystemSizeInBytes.longLongValue)];
        return diskInfo;
    }
    else {
        return @"Unknown";
    }
}

@interface DWCrashReporter ()

@property (strong, nonatomic) PLCrashReporter *plCrashReporter;

@end

@implementation DWCrashReporter

+ (instancetype)sharedInstance {
    static DWCrashReporter *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        PLCrashReporterConfig *config = [PLCrashReporterConfig defaultConfiguration];
        _plCrashReporter = [[PLCrashReporter alloc] initWithConfiguration:config];

        [self handlePendingCrashReportsIfNeeded];
    }
    return self;
}

- (BOOL)shouldHandleCrashReports {
    BOOL hasCrashesToSend = [self crashReportFiles].count > 0;
    if (!hasCrashesToSend) {
        return NO;
    }

    NSDate *lastAskDate = [[NSUserDefaults standardUserDefaults] objectForKey:DW_CRASH_REPORTER_LAST_ASK_DATE];
    if (lastAskDate) {
        NSTimeInterval ti = -[lastAskDate timeIntervalSinceNow];
        if (ti < DW_CRASH_REPORTER_REMIND_INTERVAL) {
            return NO;
        }
    }

    return YES;
}

- (void)enableCrashReporter {
    NSError *error = nil;
    if (![self.plCrashReporter enableCrashReporterAndReturnError:&error]) {
        NSLog(@"[CrashReporter] Warning: Could not enable crash reporter: %@", error);
    }
}

- (NSArray<NSString *> *)crashReportFiles {
    NSString *reportsDirectory = [self crashReportsPath];
    if (!reportsDirectory) {
        return @[];
    }
    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *directoryContent = [fileManager contentsOfDirectoryAtPath:reportsDirectory error:&error];
    if (!directoryContent) {
        NSLog(@"[CrashReporter] Failed to list crash reports directory: %@", error);
    }
    
    NSMutableArray <NSString *> *fullPaths = [NSMutableArray array];
    for (NSString *fileName in directoryContent) {
        [fullPaths addObject:[reportsDirectory stringByAppendingPathComponent:fileName]];
    }

    return [fullPaths copy];
}

- (void)removeCrashReportFiles {
    NSString *reportsDirectory = [self crashReportsPath];
    if (!reportsDirectory) {
        return;
    }
    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager removeItemAtPath:reportsDirectory error:&error]) {
        NSLog(@"[CrashReporter] Failed to remove crash reports directory: %@", error);
    }
}

- (void)updateLastCrashReportAskDate {
    [[NSUserDefaults standardUserDefaults] setObject:[NSDate date]
                                              forKey:DW_CRASH_REPORTER_LAST_ASK_DATE];
}

- (NSString *)gatherUserDeviceInfo {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    
    // non localizable
    [lines addObject:[NSString stringWithFormat:@"Device Model: %@", DeviceModel()]];
    [lines addObject:[NSString stringWithFormat:@"OS: %@", OSInformation()]];
    [lines addObject:[NSString stringWithFormat:@"Current Locale: %@", [NSLocale currentLocale].localeIdentifier]];
    [lines addObject:[NSString stringWithFormat:@"Preferred Languages: %@", [[NSLocale preferredLanguages] componentsJoinedByString:@", "]]];
    [lines addObject:[NSString stringWithFormat:@"RAM Space: %@", RamInformation()]];
    [lines addObject:[NSString stringWithFormat:@"Disk Space: %@", DiskInformation()]];

    return [lines componentsJoinedByString:@"\n"];
}

#pragma mark - Private

- (void)handlePendingCrashReportsIfNeeded {
    if (![self.plCrashReporter hasPendingCrashReport]) {
        return;
    }

    NSString *reportsDirectory = [self crashReportsPath];
    if (reportsDirectory) {
        NSError *error = nil;
        NSData *data = [self.plCrashReporter loadPendingCrashReportDataAndReturnError:&error];
        if (data != nil) {
            NSString *filename = [NSString stringWithFormat:@"%ld.plcrash", (NSUInteger)[[NSDate date] timeIntervalSince1970]];
            NSString *outputPath = [reportsDirectory stringByAppendingPathComponent:filename];
            if (![data writeToFile:outputPath atomically:YES]) {
                NSLog(@"[CrashReporter] Failed to write crash report");
            }
            else {
                NSLog(@"[CrashReporter] Saved crash report to: %@", outputPath);
            }
        }
        else {
            NSLog(@"[CrashReporter] Failed to load crash report data: %@", error);
        }
    }

    [self.plCrashReporter purgePendingCrashReport];
}

- (nullable NSString *)crashReportsPath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *reportsDirectory = [paths.firstObject stringByAppendingPathComponent:@"DWCrashReports"];
    if (![fileManager createDirectoryAtPath:reportsDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:&error]) {
        NSLog(@"[CrashReporter] Could not create DWCrashReports directory: %@", error);

        return nil;
    }

    NSURL *url = [NSURL fileURLWithPath:reportsDirectory];
    if (![url setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&error]) {
        NSLog(@"[CrashReporter] Failed to exclude crash reports directory from iCloud backup %@", error);
    }

    return reportsDirectory;
}

@end

NS_ASSUME_NONNULL_END
