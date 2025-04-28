//
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

import Foundation

protocol MainMenuViewControllerDelegate: AnyObject {
    
    /// Called when the user wants to import a private key
    /// - Parameter controller: The main menu view controller
    func mainMenuViewControllerImportPrivateKey(_ controller: MainMenuViewController)
    
    /// Called when the user wants to open the home screen
    /// - Parameter controller: The main menu view controller
    func mainMenuViewControllerOpenHomeScreen(_ controller: MainMenuViewController)
    
    /// Called when the user wants to show the payments controller with a specific page
    /// - Parameter pageIndex: The index of the page to show
    func showPaymentsController(withActivePage pageIndex: Int)
} 
