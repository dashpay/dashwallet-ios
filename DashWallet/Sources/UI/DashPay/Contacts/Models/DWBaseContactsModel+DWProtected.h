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

#import "DWBaseContactsModel.h"

#import "DWFetchedResultsDataSource.h"

NS_ASSUME_NONNULL_BEGIN

@class DWBaseContactsDataSourceObject;

@interface DWBaseContactsModel () <DWFetchedResultsDataSourceDelegate>

@property (readonly, nonatomic, strong) DWBaseContactsDataSourceObject *aggregateDataSource;

@property (readonly, nonatomic, strong) DWFetchedResultsDataSource *firstSectionDataSource;
@property (readonly, nonatomic, strong) DWFetchedResultsDataSource *secondSectionDataSource;

- (void)rebuildDataSources;

@end

NS_ASSUME_NONNULL_END
