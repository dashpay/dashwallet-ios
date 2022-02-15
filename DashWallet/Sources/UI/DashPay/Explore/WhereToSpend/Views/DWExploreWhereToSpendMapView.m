//
// Created by Pavel Tikhonenko on 13.02.2022.
// Copyright (c) 2022 Dash Core. All rights reserved.
//

#import "DWExploreWhereToSpendMapView.h"
#import "UIColor+DWStyle.h"
#import "CALayer+DWShadow.h"

@import MapKit;

@interface DWExploreWhereToSpendMapView() <MKMapViewDelegate>

@property (nonatomic, strong) MKMapView *mapView;
@end

@implementation DWExploreWhereToSpendMapView
-(instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if(self) {
        [self configureHierarchy];
    }

    return self;
}

- (void)configureHierarchy {
    self.mapView = [[MKMapView alloc] init];
    _mapView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_mapView];

    UIButton *myLocationButton = [UIButton buttonWithType:UIButtonTypeCustom];
    myLocationButton.translatesAutoresizingMaskIntoConstraints = NO;
    myLocationButton.backgroundColor = [UIColor dw_backgroundColor];
    myLocationButton.layer.cornerRadius = 8.0f;
    myLocationButton.layer.masksToBounds = YES;
    [myLocationButton.layer dw_applyShadowWithColor:[UIColor dw_shadowColor] alpha:0.12 x:0 y:3 blur:8];
    [myLocationButton setImage:[UIImage imageNamed:@"image.explore.dash.wts.map.my-location"] forState:UIControlStateNormal];
    [self addSubview:myLocationButton];

    [NSLayoutConstraint activateConstraints:@[
            [_mapView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_mapView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_mapView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_mapView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [myLocationButton.widthAnchor constraintEqualToConstant:40],
            [myLocationButton.heightAnchor constraintEqualToConstant:40],
            [myLocationButton.topAnchor constraintEqualToAnchor:self.topAnchor constant: 8],
            [myLocationButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant: -8],
    ]];

}
@end