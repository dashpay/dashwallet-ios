//  
//  Created by Andrei Ashikhmin
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

final class OnlineAccountEmailController: UIViewController {
    private let viewModel = CrowdNode.shared

    @IBOutlet var input: UITextField!

    static func controller() -> OnlineAccountEmailController {
        vc(OnlineAccountEmailController.self, from: sb("CrowdNode"))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
    }
    
    private func configureHierarchy() {
        let path = UIBezierPath(roundedRect: input.bounds, byRoundingCorners: [.topLeft, .bottomLeft, .topRight, .bottomRight], cornerRadii: CGSize(width: input.frame.size.height / 2, height: input.frame.size.height / 2))

        var gradient = CALayer()
        gradient.frame =  CGRect(origin: CGPoint.zero, size: input.frame.size)
        gradient.backgroundColor = UIColor.red.cgColor
        gradient.borderColor = UIColor.green.cgColor
//        gradient.colors = [UIColor.green.cgColor, UIColor.red.cgColor]

        let shape = CAShapeLayer()
        shape.lineWidth = 10
        shape.path = path.cgPath
        shape.strokeColor = UIColor.black.cgColor
        shape.fillColor = UIColor.clear.cgColor
        gradient.mask = shape

        input.layer.masksToBounds = true
        input.layer.borderColor = UIColor.blue.cgColor
        input.layer.borderWidth = 1.0
        
        input.layer.addSublayer(gradient)
    }
}
