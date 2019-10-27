//
//  DWMasternodeViewController.m
//  DashWallet
//
//  Created by Sam Westrich on 6/10/18.
//  Copyright © 2018 Dash Core Group. All rights reserved.
//

#import "DWMasternodeViewController.h"
#import "DWMasternodeDetailViewController.h"
#import "DWMasternodeTableViewCell.h"
#import "DWRegisterMasternodeViewController.h"
#import "DWResultsMasternodeViewController.h"
#import <DashSync/DashSync.h>
#import <arpa/inet.h>

static UITextField *TextFieldSubviewOfView(UIView *view) {
    if ([view isKindOfClass:UITextField.class]) {
        return (UITextField *)view;
    }
    else {
        UITextField *textField = nil;
        for (UIView *subview in view.subviews) {
            textField = TextFieldSubviewOfView(subview);
            if (textField) {
                break;
            }
        }
        return textField;
    }
}

@interface DWMasternodeViewController () <UISearchResultsUpdating, UISearchBarDelegate>

@property (strong, nonatomic) IBOutlet UIBarButtonItem *registerButton;
@property (strong, nonatomic) UISearchController *searchController;
@property (strong, nonatomic) DWResultsMasternodeViewController *searchResultsController;

@end

@implementation DWMasternodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.definesPresentationContext = YES;

    DWResultsMasternodeViewController *searchResultsController = [[DWResultsMasternodeViewController alloc] initWithStyle:UITableViewStyleGrouped];
    searchResultsController.tableView.delegate = self;
    self.searchResultsController = searchResultsController;

    UIColor *dashBlueColor = [UIColor colorWithRed:0.0 green:141.0 / 255.0 blue:228.0 / 255.0 alpha:1.0];
    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:searchResultsController];
    searchController.searchResultsUpdater = self;
    searchController.searchBar.delegate = self;
    searchController.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    searchController.searchBar.searchBarStyle = UISearchBarStyleProminent;
    searchController.searchBar.barTintColor = dashBlueColor;
    searchController.searchBar.tintColor = [UIColor whiteColor];
    UITextField *searchTextField = TextFieldSubviewOfView(searchController.searchBar);
    searchTextField.tintColor = dashBlueColor;
    UIView *textfieldBackground = searchTextField.subviews.firstObject;
    textfieldBackground.backgroundColor = [UIColor whiteColor];
    textfieldBackground.layer.cornerRadius = 10;
    textfieldBackground.clipsToBounds = YES;
    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController = searchController;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
    }
    else {
        self.tableView.tableHeaderView = searchController.searchBar;
    }
    self.searchController = searchController;
}

#pragma mark - Table view data source

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    DSSimplifiedMasternodeEntryEntity *simplifiedMasternodeEntryEntity = [self.fetchedResultsController objectAtIndexPath:indexPath];
    DWMasternodeDetailViewController *masternodeDetailViewController = (DWMasternodeDetailViewController *)[self.storyboard instantiateViewControllerWithIdentifier:@"DWMasternodeDetailViewControllerId"];
    masternodeDetailViewController.simplifiedMasternodeEntry = simplifiedMasternodeEntryEntity.simplifiedMasternodeEntry;
    masternodeDetailViewController.localMasternode = simplifiedMasternodeEntryEntity.localMasternode ? [simplifiedMasternodeEntryEntity.localMasternode loadLocalMasternode] : nil;
    [self.navigationController pushViewController:masternodeDetailViewController animated:YES];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"RegisterMasternodeSegue"]) {
        UINavigationController *navigationController = (UINavigationController *)segue.destinationViewController;
        DWRegisterMasternodeViewController *registerMasternodeViewController = (DWRegisterMasternodeViewController *)navigationController.topViewController;
        registerMasternodeViewController.chain = self.chain;
    }
}

#pragma mark UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self.searchResultsController updateSearchString:searchController.searchBar.text];
}

#pragma mark UISearchBarDelegate

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

@end
