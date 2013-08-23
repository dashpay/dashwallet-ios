//
//  NSManagedObjectContext+Utils.m
//  ZincWallet
//
//  Created by Aaron Voisine on 8/22/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "NSManagedObjectContext+Utils.h"

@implementation NSManagedObjectContext (Utils)

- (void)saveContext:(void (^)(NSError *error))completion;
{
    [self performBlock:^{
        NSError *error = nil;

        if ([self hasChanges] && ! [self save:&error]) {
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            //abort();
        }
        
        if (completion) completion(error);
    }];
}

#pragma mark - Core Data stack

// Returns the managed object context for the application. If the context doesn't already exist, it is created and bound
// to the persistent store coordinator for the application.
+ (instancetype)sharedInstance
{
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        NSURL *docURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                          inDomains:NSUserDomainMask] lastObject];
        NSURL *modelURL = [NSBundle.mainBundle URLsForResourcesWithExtension:@"momd" subdirectory:nil].lastObject;
        NSString *projName = [[modelURL lastPathComponent] stringByDeletingPathExtension];
        NSURL *storeURL = [[docURL URLByAppendingPathComponent:projName] URLByAppendingPathExtension:@"sqlite"];
        NSPersistentStoreCoordinator *coordinator =
            [[NSPersistentStoreCoordinator alloc]
             initWithManagedObjectModel:[[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL]];
        NSError *error = nil;
        
        if (! [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil
               error:&error]) {
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            
            if (! [[NSFileManager defaultManager] removeItemAtURL:storeURL error:&error]) {
                NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            }
            
            if (! [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil
                   error:&error]) {
                NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
                abort();
            }
        }

        if (coordinator) {
            singleton = [NSManagedObjectContext new];
            [singleton setPersistentStoreCoordinator:coordinator];
        }
    });
    
    return singleton;
}

@end
