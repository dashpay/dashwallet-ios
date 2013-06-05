//
//  ZNAmountViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 6/4/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNAmountViewController.h"

@interface ZNAmountViewController ()

@property (nonatomic, strong) UILabel *addressLabel;

@end

@implementation ZNAmountViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string
{
    
}

@end
