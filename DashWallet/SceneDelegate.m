//
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

#import "SceneDelegate.h"

#import "AppDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@implementation SceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) {
        return;
    }

    AppDelegate *appDelegate = [AppDelegate appDelegate];
    [appDelegate installWindowInScene:(UIWindowScene *)scene];
    self.window = appDelegate.window;

    // A cold launch from a link delivers it here instead of through
    // `scene:openURLContexts:` / `scene:continueUserActivity:`.
    for (NSUserActivity *userActivity in connectionOptions.userActivities) {
        [appDelegate handleUserActivity:userActivity];
    }
    UIOpenURLContext *urlContext = connectionOptions.URLContexts.anyObject;
    if (urlContext != nil) {
        [appDelegate handleOpenURL:urlContext.URL];
    }
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    [[AppDelegate appDelegate] handleDidBecomeActive];
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    // The app handles one link at a time, as `application:openURL:options:` did.
    UIOpenURLContext *urlContext = URLContexts.anyObject;
    if (urlContext != nil) {
        [[AppDelegate appDelegate] handleOpenURL:urlContext.URL];
    }
}

- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity {
    [[AppDelegate appDelegate] handleUserActivity:userActivity];
}

@end

NS_ASSUME_NONNULL_END
