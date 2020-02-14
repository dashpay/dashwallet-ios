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

#import "DWUsernameHeaderView.h"

#import "DWPlanetarySystemView.h"
#import "DWUIKit.h"

static NSArray<DWPlanetObject *> *Planets(void) {
    const CGSize size = CGSizeMake(36.0, 36.0);

    NSMutableArray<DWPlanetObject *> *planets = [NSMutableArray array];
    {
        DWPlanetObject *planet = [[DWPlanetObject alloc] init];
        planet.image = [UIImage imageNamed:@"dp_user_1"];
        planet.speed = 2.1;
        planet.duration = 0.75;
        planet.offset = 245.0 / 360.0;
        planet.size = size;
        planet.orbit = 0;
        planet.rotateClockwise = YES;
        [planets addObject:planet];
    }

    {
        DWPlanetObject *planet = [[DWPlanetObject alloc] init];
        planet.image = [UIImage imageNamed:@"dp_user_2"];
        planet.speed = 1.8;
        planet.duration = 0.75;
        planet.offset = 255.0 / 360.0;
        planet.size = size;
        planet.orbit = 1;
        planet.rotateClockwise = YES;
        [planets addObject:planet];
    }

    {
        DWPlanetObject *planet = [[DWPlanetObject alloc] init];
        planet.image = [UIImage imageNamed:@"dp_user_3"];
        planet.speed = 1.55;
        planet.duration = 0.75;
        planet.offset = 230.0 / 360.0;
        planet.size = size;
        planet.orbit = 2;
        planet.rotateClockwise = YES;
        [planets addObject:planet];
    }

    {
        DWPlanetObject *planet = [[DWPlanetObject alloc] init];
        planet.image = [UIImage imageNamed:@"dp_user_2"]; // TODO: fix image
        planet.speed = 1.3;
        planet.duration = 0.75;
        planet.offset = 200.0 / 360.0;
        planet.size = size;
        planet.orbit = 3;
        planet.rotateClockwise = YES;
        [planets addObject:planet];
    }

    {
        DWPlanetObject *planet = [[DWPlanetObject alloc] init];
        planet.image = [UIImage imageNamed:@"dp_user_generic"];
        planet.speed = 1.0;
        planet.duration = 0.75;
        planet.offset = 250.0 / 360.0;
        planet.size = size;
        planet.orbit = 3;
        planet.rotateClockwise = YES;
        [planets addObject:planet];
    }

    return [planets copy];
}

NS_ASSUME_NONNULL_BEGIN

@interface DWUsernameHeaderView ()

@property (strong, nonatomic) DWPlanetarySystemView *planetaryView;

@end

NS_ASSUME_NONNULL_END

@implementation DWUsernameHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
        cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
        [cancelButton setImage:[UIImage imageNamed:@"payments_nav_cross"] forState:UIControlStateNormal];
        [self addSubview:cancelButton];
        _cancelButton = cancelButton;

        // Luckily, DashBlueColor doesn't have DarkMode counterpart
        // and we don't need to reset colors on traitCollectionDidChange:
        UIColor *color = [UIColor dw_dashBlueColor];
        NSArray<UIColor *> *colors = @[
            [color colorWithAlphaComponent:0.5],
            [color colorWithAlphaComponent:0.3],
            [color colorWithAlphaComponent:0.1],
            [color colorWithAlphaComponent:0.07],
        ];

        DWPlanetarySystemView *planetaryView = [[DWPlanetarySystemView alloc] initWithFrame:CGRectZero];
        planetaryView.translatesAutoresizingMaskIntoConstraints = NO;
        planetaryView.centerOffset = 78.0;
        planetaryView.colors = colors;
        planetaryView.lineWidth = 1.0;
        planetaryView.numberOfOrbits = colors.count;
        planetaryView.planets = Planets();
        [self addSubview:planetaryView];
        _planetaryView = planetaryView;

        const CGFloat buttonSize = 44.0;
        const CGSize screenSize = [UIScreen mainScreen].bounds.size;
        const CGFloat side = MIN(screenSize.width, screenSize.height);
        [NSLayoutConstraint activateConstraints:@[
            [cancelButton.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor],
            [cancelButton.leadingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.leadingAnchor],
            [cancelButton.widthAnchor constraintEqualToConstant:buttonSize],
            [cancelButton.heightAnchor constraintEqualToConstant:buttonSize],

            [planetaryView.centerXAnchor constraintEqualToAnchor:self.trailingAnchor],
            [planetaryView.centerYAnchor constraintEqualToAnchor:self.topAnchor],
            [planetaryView.widthAnchor constraintEqualToConstant:side],
            [planetaryView.heightAnchor constraintEqualToConstant:side],
        ]];
    }
    return self;
}

- (void)showInitialAnimation {
    [self.planetaryView showInitialAnimation];
}

@end
