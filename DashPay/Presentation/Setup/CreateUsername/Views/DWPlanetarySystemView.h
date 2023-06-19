//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Model

@interface DWPlanetObject : NSObject

/// The planet image.
@property (nullable, nonatomic, strong) UIImage *image;
/// Custom view to display as a planet
@property (nullable, nonatomic, strong) UIView *customView;

/// The speed of animation.
@property (nonatomic, assign) CGFloat speed;
/// The duration of the complete rotation along the orbit.
@property (nonatomic, assign) CGFloat duration;
/// The animation time offset in percentage.
@property (nonatomic, assign) CGFloat offset;
/// Size of the corresponding UIImageView.
@property (nonatomic, assign) CGSize size;
/// The number of the orbit. Must be less than `numberOfOrbits` of the view.
@property (nonatomic, assign) NSInteger orbit;
/// The rotation direction.
@property (nonatomic, assign) BOOL rotateClockwise;

@end

#pragma mark - View

@interface DWPlanetarySystemView : UIView

@property (nonatomic, assign) NSInteger numberOfOrbits;
@property (nonatomic, assign) CGFloat centerOffset;
@property (nonatomic, assign) CGFloat borderOffset;
@property (nonatomic, assign) CGFloat lineWidth;
@property (nonatomic, copy) NSArray<UIColor *> *colors;

@property (nullable, nonatomic, copy) NSArray<DWPlanetObject *> *planets;

- (void)showInitialAnimation;

@end

NS_ASSUME_NONNULL_END
