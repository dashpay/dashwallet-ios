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

#import "UIView+DWHUD.h"

#import <MBProgressHUD/MBProgressHUD.h>
#import <objc/runtime.h>

#import "DWUIKit.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

NSTimeInterval const DW_INFO_HUD_DISPLAY_TIME = 3.5;

@implementation UIView (DWHUD)

/// The progress HUD is held by reference (`dw_progressHUD`) rather than looked
/// up, so show and hide always address the same object.
///
/// MBProgressHUD's own `HUDForView:` cannot serve here: info HUDs are the same
/// class on the same view, and it returns the TOPMOST one. A flow that reports
/// its result with `dw_showInfoHUD` and then takes its spinner down with
/// `dw_hideProgressHUD` therefore dismissed the confirmation it had just put
/// up, leaving nothing to hide the spinner — which then ran forever. The
/// asset-lock retry in `TxDetailViewController` is exactly that pair, and it
/// span on over a transfer that had already completed. The same lookup made
/// `dw_showProgressHUD` adopt a visible info HUD and rewrite its label instead
/// of raising a spinner at all.
///
/// Telling the two apart by `mode` would fix those but not this: a HUD stays in
/// the hierarchy for the length of its fade-out with `finished` already set
/// (private, so not readable from here), and a show inside that window would
/// adopt a HUD on its way out — leaving the caller with no spinner. An owned
/// reference, released at hide time, has neither problem.
- (void)dw_showProgressHUDWithMessage:(nullable NSString *)message {
    MBProgressHUD *hud = [self dw_progressHUD];
    if (!hud) {
        hud = [MBProgressHUD showHUDAddedTo:self animated:YES];
        hud.removeFromSuperViewOnHide = YES;
        hud.label.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
        hud.label.adjustsFontForContentSizeCategory = YES;
        hud.label.numberOfLines = 0;
        [self setDw_progressHUD:hud];
    }
    hud.label.text = message;
}

- (void)dw_hideProgressHUD {
    MBProgressHUD *hud = [self dw_progressHUD];
    if (!hud) {
        return;
    }
    // Released before the fade-out finishes, deliberately: a `dw_show…` during
    // that window must build a fresh HUD instead of adopting this one.
    [self setDw_progressHUD:nil];
    [hud hideAnimated:YES];
}

- (void)dw_showInfoHUDWithText:(NSString *)text {
    [self dw_showInfoHUDWithText:text offsetForNavBar:NO];
}

- (void)dw_showInfoHUDWithText:(NSString *)text offsetForNavBar:(BOOL)shouldOffset {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self animated:YES];
    hud.removeFromSuperViewOnHide = YES;
    hud.mode = MBProgressHUDModeCustomView;

    DWCustomHUDView *customView = [[DWCustomHUDView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.frame), 28)];
    [customView setText:text];
    [customView setIconImage:[UIImage imageNamed:@"checkmark.circle.white"]];

    hud.customView = customView;
    hud.bezelView.layer.cornerRadius = 8.0f;
    hud.bezelView.clipsToBounds = YES;
    hud.bezelView.color = [UIColor colorWithWhite:0.0f alpha:0.9f];
    hud.bezelView.style = MBProgressHUDBackgroundStyleSolidColor;

    CGFloat yOffset = CGRectGetHeight(self.bounds) / 2 - CGRectGetHeight(customView.bounds) - (shouldOffset ? 85 : 35);
    hud.offset = CGPointMake(0.0f, yOffset);
    hud.userInteractionEnabled = NO;

    __weak typeof(self) weakSelf = self;
    hud.completionBlock = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        NSMutableArray<MBProgressHUD *> *infoHUDQueue = [strongSelf dw_infoHUDQueue];
        if (infoHUDQueue.count > 0) {
            [infoHUDQueue removeObjectAtIndex:0];
        }

        MBProgressHUD *nextHUD = infoHUDQueue.firstObject;
        if (nextHUD) {
            [strongSelf addSubview:nextHUD];
            [nextHUD showAnimated:YES];
            [nextHUD hideAnimated:YES afterDelay:DW_INFO_HUD_DISPLAY_TIME];
        }
    };

    NSMutableArray<MBProgressHUD *> *infoHUDQueue = [self dw_infoHUDQueue];
    if (!infoHUDQueue) {
        infoHUDQueue = [NSMutableArray array];
        [self setDw_infoHUDQueue:infoHUDQueue];
    }

    [infoHUDQueue addObject:hud];

    if (infoHUDQueue.count == 1) {
        [self addSubview:hud];
        [hud showAnimated:YES];
        [hud hideAnimated:YES afterDelay:DW_INFO_HUD_DISPLAY_TIME];
    }
}

#pragma mark - Private

- (nullable MBProgressHUD *)dw_progressHUD {
    return objc_getAssociatedObject(self, @selector(dw_progressHUD));
}

- (void)setDw_progressHUD:(nullable MBProgressHUD *)dw_progressHUD {
    objc_setAssociatedObject(self,
                             @selector(dw_progressHUD),
                             dw_progressHUD,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (nullable NSMutableArray<MBProgressHUD *> *)dw_infoHUDQueue {
    return objc_getAssociatedObject(self, @selector(dw_infoHUDQueue));
}

- (void)setDw_infoHUDQueue:(nullable NSMutableArray<MBProgressHUD *> *)dw_infoHUDQueue {
    objc_setAssociatedObject(self,
                             @selector(dw_infoHUDQueue),
                             dw_infoHUDQueue,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

NS_ASSUME_NONNULL_END
