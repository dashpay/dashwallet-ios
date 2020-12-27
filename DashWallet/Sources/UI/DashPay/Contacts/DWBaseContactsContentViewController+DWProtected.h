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

#import "DWBaseContactsContentViewController.h"

#import "DWContactsSearchInfoHeaderView.h"
#import "DWContactsSearchPlaceholderView.h"
#import "DWFilterHeaderView.h"
#import "DWGlobalMatchFailedHeaderView.h"
#import "DWGlobalMatchHeaderView.h"
#import "DWTitleActionHeaderView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWBaseContactsContentViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, DWTitleActionHeaderViewDelegate, DWFilterHeaderViewDelegate, DWContactsSearchPlaceholderViewDelegate>

@property (readonly, nonatomic, strong) id<DWPayModelProtocol> payModel;
@property (readonly, nonatomic, strong) id<DWTransactionListDataProviderProtocol> dataProvider;

@property (null_resettable, nonatomic, strong) UICollectionView *collectionView;

@property (null_resettable, nonatomic, strong) DWContactsSearchPlaceholderView *measuringSearchPlaceholderView;
@property (null_resettable, nonatomic, strong) DWContactsSearchInfoHeaderView *measuringSearchHeaderView;
@property (null_resettable, nonatomic, strong) DWTitleActionHeaderView *measuringRequestsHeaderView;
@property (null_resettable, nonatomic, strong) DWFilterHeaderView *measuringContactsHeaderView;
@property (null_resettable, nonatomic, strong) DWGlobalMatchHeaderView *measuringGlobalMatchHeaderView;
@property (null_resettable, nonatomic, strong) DWGlobalMatchFailedHeaderView *measuringGlobalMatchFailedHeaderView;

@property (null_resettable, nonatomic, copy) NSAttributedString *searchHeaderTitle;
@property (null_resettable, nonatomic, copy) NSString *requestsHeaderTitle;
@property (null_resettable, nonatomic, copy) NSAttributedString *contactsHeaderFilterButtonTitle;

@end

NS_ASSUME_NONNULL_END
