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

#import "UINavigationBar+DWAppearance.h"

#import "DWUIKit.h"

@implementation UINavigationBar (DWAppearance)

- (void)dw_configureForDefaultAppearance {
    UINavigationBar *navigationBar = self;
    navigationBar.barStyle = UIBarStyleDefault;
    navigationBar.barTintColor = [UIColor dw_dashNavigationBlueColor];
    navigationBar.tintColor = [UIColor dw_tintColor];
    navigationBar.translucent = NO;

    navigationBar.titleTextAttributes = @{
        NSForegroundColorAttributeName : [UIColor dw_lightTitleColor],
        NSFontAttributeName : [UIFont dw_navigationBarTitleFont],
    };

    navigationBar.shadowImage = [[UIImage alloc] init];
}

- (void)dw_configureForWhiteAppearance {
    UINavigationBar *navigationBar = self;
    navigationBar.barStyle = UIBarStyleDefault;
    navigationBar.barTintColor = [UIColor dw_backgroundColor];
    navigationBar.tintColor = [UIColor dw_dashBlueColor];
    navigationBar.translucent = NO;

    navigationBar.titleTextAttributes = @{
        NSForegroundColorAttributeName : [UIColor dw_darkTitleColor],
        NSFontAttributeName : [UIFont dw_navigationBarTitleFont],
    };

    navigationBar.shadowImage = [[UIImage alloc] init];
}

- (void)dw_applyStandardAppearance {
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *standardAppearance = self.standardAppearance;
        UINavigationBar *navigationBar = self;
        NSParameterAssert(standardAppearance);
        standardAppearance.backgroundColor = navigationBar.barTintColor;
        standardAppearance.titleTextAttributes = navigationBar.titleTextAttributes;
        standardAppearance.shadowImage = navigationBar.shadowImage;
        standardAppearance.shadowColor = [UIColor clearColor];

        UIBarButtonItemAppearance *buttonAppearance = standardAppearance.buttonAppearance;
        NSParameterAssert(buttonAppearance);
        UIBarButtonItemStateAppearance *stateApperance = buttonAppearance.normal;
        stateApperance.titleTextAttributes = navigationBar.titleTextAttributes;

        navigationBar.scrollEdgeAppearance = standardAppearance;
        navigationBar.compactAppearance = standardAppearance;
    }
}

@end
