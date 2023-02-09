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

class OutlinedTextField: UITextField {
    private let padding = UIEdgeInsets(top: 15, left: 15, bottom: 0, right: 10);
    private let labelControl = UILabel(frame: CGRect.zero)
    
    var label: String = "" {
        didSet {
            labelControl.text = label
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.borderStyle = .none
        self.layer.borderColor = UIColor.dw_dashBlue().withAlphaComponent(0.2).cgColor
        self.layer.borderWidth = 4
        self.layer.cornerRadius = 12
        
        let path = UIBezierPath(roundedRect: self.bounds.inset(by: UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 1)), cornerRadius: 8)

        let shape = CAShapeLayer()
        shape.lineWidth = 1
        shape.path = path.cgPath
        shape.strokeColor = UIColor.dw_dashBlue().cgColor
        shape.fillColor = UIColor.clear.cgColor

        self.layer.addSublayer(shape)
        
        labelControl.textColor = .dw_secondaryText()
        labelControl.font = .dw_regularFont(ofSize: 12)
        labelControl.text = label
        labelControl.translatesAutoresizingMaskIntoConstraints = false
        labelControl.clipsToBounds = true
        labelControl.frame = CGRect(x: 0, y: 0, width: self.frame.size.width, height: 18)
        
        self.addSubview(labelControl)
              
        labelControl.topAnchor.constraint(equalTo: self.topAnchor, constant: 10).isActive = true
        labelControl.leftAnchor.constraint(equalTo: self.leftAnchor, constant: 15).isActive = true
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: padding)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: padding)
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: padding)
    }
}
