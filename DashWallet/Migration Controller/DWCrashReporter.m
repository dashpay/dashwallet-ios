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

#import <Dash-PLCrashReporter/PLCrashReporter.h>

NS_ASSUME_NONNULL_BEGIN

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
    }
    return self;
}

- (BOOL)shouldHandleCrashReports {
    if (![self.plCrashReporter hasPendingCrashReport]) {
        return NO;
    }
    
    return YES;
}

- (void)enableCrashReporter {
    NSError *error = nil;
    if (![self.plCrashReporter enableCrashReporterAndReturnError:&error]) {
        NSLog(@"Warning: Could not enable crash reporter: %@", error);
    }
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
            if (![data writeToFile: outputPath atomically:YES]) {
                NSLog(@"Failed to write crash report");
            }
            else {
                NSLog(@"Saved crash report to: %@", outputPath);
            }
        }
        else {
            NSLog(@"Failed to load crash report data: %@", error);
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
        NSLog(@"Could not create DWCrashReports directory: %@", error);
        
        return nil;
    }
    
    return reportsDirectory;
}

@end

NS_ASSUME_NONNULL_END
