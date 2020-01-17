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

#import "DWContactsModel.h"

#import "DWContactsDataSourceObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWContactObject : NSObject <DWContactItem>

@property (nonatomic, assign) DWContactItemDisplayType displayType;
@property (nonatomic, copy) NSString *username;
@property (nullable, nonatomic, copy) NSString *tagline;
@property (nullable, nonatomic, copy) NSString *dateString;

@end

NS_ASSUME_NONNULL_END

@implementation DWContactObject

@end

#pragma mark - Model

@implementation DWContactsModel

- (instancetype)init {
    self = [super init];
    if (self) {
        NSArray *incomingNames = @[ @"Bean_swanson_98", @"Codywebster", @"Ajohnward" ];
        NSArray *pendingNames = @[ @"Georgiasullivan", @"Jeffrey_rowe", @"Wayne_campbell" ];
        NSArray *contactNames = @[ @"Quantum", @"SamB", @"Tomasz", @"Eric" ];

        NSMutableArray<id<DWContactItem>> *contacts = [NSMutableArray array];

        for (NSString *name in incomingNames) {
            DWContactObject *contact = [[DWContactObject alloc] init];
            contact.displayType = DWContactItemDisplayType_IncomingRequest;
            contact.username = name;
            contact.dateString = @"Feb 31, 2020";
            [contacts addObject:contact];
        }

        for (NSString *name in pendingNames) {
            DWContactObject *contact = [[DWContactObject alloc] init];
            contact.displayType = DWContactItemDisplayType_OutgoingRequest;
            contact.username = name;
            contact.dateString = @"Feb 32, 2020";
            [contacts addObject:contact];
        }

        for (NSString *name in contactNames) {
            DWContactObject *contact = [[DWContactObject alloc] init];
            contact.displayType = DWContactItemDisplayType_Contact;
            contact.username = name;
            contact.tagline = @"Friend";
            [contacts addObject:contact];
        }

        DWContactsDataSourceObject *datasource = [[DWContactsDataSourceObject alloc] initWithItems:contacts];
        _contactsDataSource = datasource;
    }
    return self;
}

@end
