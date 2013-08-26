//
//  NSManagedObject+Utils.m
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

#import "NSManagedObject+Utils.h"

@implementation NSManagedObject (Utils)

+ (instancetype)managedObject
{
    return [[self alloc] initWithEntity:[self entity] insertIntoManagedObjectContext:[self managedObjectContext]];
}

// Returns the managed object context for the application. If the context doesn't already exist, it is created and bound
// to the persistent store coordinator for the application.
+ (NSManagedObjectContext *)managedObjectContext
{
    static id context = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        NSURL *docURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                          inDomains:NSUserDomainMask] lastObject];
        NSURL *modelURL = [NSBundle.mainBundle URLsForResourcesWithExtension:@"momd" subdirectory:nil].lastObject;
        NSString *projName = [[modelURL lastPathComponent] stringByDeletingPathExtension];
        NSURL *storeURL = [[docURL URLByAppendingPathComponent:projName] URLByAppendingPathExtension:@"sqlite"];
        NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
        NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc]
                                                     initWithManagedObjectModel:model];
        NSError *error = nil;
        
        if (! [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil
               error:&error]) {
            NSLog(@"[%s %s] line %d: %@, %@", object_getClassName(self), sel_getName(_cmd), __LINE__, error,
                  error.userInfo);

#if DEBUG
            abort();
#else       // if this is a not a debug build, attempt to delete and create a new persisent data store
            if (! [[NSFileManager defaultManager] removeItemAtURL:storeURL error:&error]) {
                NSLog(@"[%s %s] line %d: %@, %@", object_getClassName(self), sel_getName(_cmd), __LINE__, error,
                      error.userInfo);
            }
            
            if (! [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil
                   error:&error]) {
                NSLog(@"[%s %s] line %d: %@, %@", object_getClassName(self), sel_getName(_cmd), __LINE__, error,
                      error.userInfo);
                abort();
            }
#endif
        }

        if (coordinator) {
            context = [NSManagedObjectContext new];
            [context setPersistentStoreCoordinator:coordinator];
        }
    });
    
    return context;
}

+ (void)saveContext
{
    [self saveContext:nil];
}

+ (void)saveContext:(void (^)(NSError *error))completion
{
    [[self managedObjectContext] performBlock:^{
        NSError *error = nil;
        
        if ([[self managedObjectContext] hasChanges] && ! [[self managedObjectContext] save:&error]) {
            NSLog(@"[%s %s] line %d: %@, %@", object_getClassName(self), sel_getName(_cmd), __LINE__, error,
                  error.userInfo);
#if DEBUG
            abort();
#endif
        }
        
        if (completion) completion(error);
    }];
}

+ (NSString *)entityName
{
    return NSStringFromClass(self);
}

+ (NSEntityDescription *)entity
{
    return [NSEntityDescription entityForName:[self entityName] inManagedObjectContext:[self managedObjectContext]];
}

+ (NSFetchRequest *)fetchRequest
{
    return [NSFetchRequest fetchRequestWithEntityName:[self entityName]];
}

+ (NSFetchedResultsController *)fetchedResultsController {
    return [[NSFetchedResultsController alloc] initWithFetchRequest:[self fetchRequest]
            managedObjectContext:[self managedObjectContext] sectionNameKeyPath:nil cacheName:[self entityName]];
}

@end
