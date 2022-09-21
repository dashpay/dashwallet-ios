//  
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

import UIKit

func sb(_ name: String) -> UIStoryboard {
    return UIStoryboard(name: name, bundle: .main)
}

func vc<T>(_ name: T.Type, from storyboard: UIStoryboard) -> T
{
    return viewController(name, from: storyboard)
}

func viewController<T>(_ name: T.Type, from storyBoard: UIStoryboard) -> T
{
    let identifier: String = String(String(describing: type(of: name)).split(separator: ".").first!)
    return storyBoard.instantiateViewController(withIdentifier: identifier) as! T
}

