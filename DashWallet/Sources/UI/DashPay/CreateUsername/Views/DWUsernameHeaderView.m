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

static CGFloat const BottomSpacing(void) {
    if (IS_IPHONE_5_OR_LESS || IS_IPHONE_6) {
        return 4.0;
    }
    else {
        return 16.0;
    }
}

static CGFloat SmallCircleRadius(void) {
    if (IS_IPHONE_5_OR_LESS || IS_IPHONE_6) {
        return 39.0;
    }
    else {
        return 78.0;
    }
}

static CGFloat PlanetarySize(void) {
    const CGSize screenSize = [UIScreen mainScreen].bounds.size;
    const CGFloat side = MIN(screenSize.width, screenSize.height);
    if (IS_IPHONE_5_OR_LESS || IS_IPHONE_6) {
        return side / 2.0;
    }
    else {
        return MIN(375.0, side);
    }
}

static NSArray<DWPlanetObject *> *Planets(void) {
    CGSize size;
    if (IS_IPHONE_5_OR_LESS || IS_IPHONE_6) {
        size = CGSizeMake(20.0, 20.0);
    }
    else {
        size = CGSizeMake(36.0, 36.0);
    }

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
@property (nonatomic, strong) UILabel *titleLabel;

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
        planetaryView.centerOffset = SmallCircleRadius();
        planetaryView.colors = colors;
        planetaryView.lineWidth = 1.0;
        planetaryView.numberOfOrbits = colors.count;
        planetaryView.planets = Planets();
        [self addSubview:planetaryView];
        _planetaryView = planetaryView;

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.backgroundColor = [UIColor clearColor];
        titleLabel.numberOfLines = 3;
        [self addSubview:titleLabel];
        _titleLabel = titleLabel;

        const CGFloat buttonSize = 44.0;
        const CGFloat side = PlanetarySize();
        [NSLayoutConstraint activateConstraints:@[
            [cancelButton.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor],
            [cancelButton.leadingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.leadingAnchor],
            [cancelButton.widthAnchor constraintEqualToConstant:buttonSize],
            [cancelButton.heightAnchor constraintEqualToConstant:buttonSize],

            [planetaryView.centerXAnchor constraintEqualToAnchor:self.trailingAnchor],
            [planetaryView.centerYAnchor constraintEqualToAnchor:self.topAnchor],
            [planetaryView.widthAnchor constraintEqualToConstant:side],
            [planetaryView.heightAnchor constraintEqualToConstant:side],

            [titleLabel.topAnchor constraintGreaterThanOrEqualToAnchor:cancelButton.bottomAnchor],
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.leadingAnchor],
            [self.layoutMarginsGuide.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                              constant:BottomSpacing()],
        ]];
    }
    return self;
}

- (void)setTitleBuilder:(DWTitleStringBuilder)titleBuilder {
    _titleBuilder = [titleBuilder copy];

    [self updateTitle];
}

- (void)showInitialAnimation {
    [self.planetaryView showInitialAnimation];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self updateTitle];
}

#pragma mark - Private

- (void)updateTitle {
    if (self.titleBuilder) {
        self.titleLabel.attributedText = self.titleBuilder();
    }
    else {
        self.titleLabel.attributedText = nil;
    }
}

@end
