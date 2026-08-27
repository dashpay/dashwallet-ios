//
//  Created by Dash Core Group
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

#import "DWSecureAllocator.h"

#import <dispatch/dispatch.h>
#import <stdlib.h>
#import <string.h>

static void *DWSecureAllocate(CFIndex allocSize, CFOptionFlags hint, void *info) {
    void *allocation = malloc(sizeof(CFIndex) + allocSize);
    if (allocation == NULL) {
        return NULL;
    }

    *(CFIndex *)allocation = allocSize;
    return (CFIndex *)allocation + 1;
}

static void DWSecureDeallocate(void *pointer, void *info) {
    CFIndex size = *((CFIndex *)pointer - 1);
    if (size > 0) {
        memset(pointer, 0, size);
    }

    free((CFIndex *)pointer - 1);
}

static void *DWSecureReallocate(void *pointer, CFIndex newSize, CFOptionFlags hint, void *info) {
    void *newPointer = DWSecureAllocate(newSize, hint, info);
    CFIndex oldSize = *((CFIndex *)pointer - 1);

    if (newPointer != NULL) {
        if (oldSize > 0) {
            memcpy(newPointer, pointer, oldSize < newSize ? oldSize : newSize);
        }
        DWSecureDeallocate(pointer, info);
    }

    return newPointer;
}

CFAllocatorRef DWSecureAllocator(void) {
    static CFAllocatorRef allocator = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFAllocatorContext context;
        CFAllocatorGetContext(kCFAllocatorDefault, &context);
        context.allocate = DWSecureAllocate;
        context.reallocate = DWSecureReallocate;
        context.deallocate = DWSecureDeallocate;
        allocator = CFAllocatorCreate(kCFAllocatorDefault, &context);
    });

    return allocator;
}
