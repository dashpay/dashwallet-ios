//    Copyright (c) 2014 Matej Bukovinski
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in
//    all copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//    THE SOFTWARE.

// https://gist.github.com/matej/9639064

#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

@interface CALayer (MBAnimationPersistence)

/**
 Animation keys for animations that should be persisted.
 Inspect the `animationKeys` array to find valid keys for your layer.
 
 `CAAnimation` instances associated with the provided keys will be copied and held onto,
 when the applications enters background mode and restored when exiting background mode.
 
 Set to `nil`to disable persistance.
 */
@property (nullable, nonatomic, strong) NSArray *MB_persistentAnimationKeys;

/** Set all current `animationKeys` as persistent. */
- (void)MB_setCurrentAnimationsPersistent;

@end

NS_ASSUME_NONNULL_END
