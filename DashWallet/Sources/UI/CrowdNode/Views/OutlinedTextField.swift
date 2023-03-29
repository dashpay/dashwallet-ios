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
    private let borderColor = UIColor(red: 0.808, green: 0.824, blue: 0.835, alpha: 1)
    private let labelControl = UILabel(frame: CGRect.zero)
    private var outerBorder: CAShapeLayer!

    var label = "" {
        didSet {
            labelControl.text = label
        }
    }

    var isError = false {
        didSet {
            if isError {
                self.layer.borderColor = UIColor.systemRed.cgColor
                outerBorder.fillColor = UIColor.systemRed.withAlphaComponent(0.1).cgColor
                outerBorder.strokeColor = UIColor.systemRed.withAlphaComponent(0.2).cgColor
            } else {
                outerBorder.fillColor = UIColor.clear.cgColor
                outerBorder.strokeColor = UIColor.dw_dashBlue().withAlphaComponent(0.2).cgColor

                if isEditing {
                    self.layer.borderColor = UIColor.dw_dashBlue().cgColor
                } else {
                    self.layer.borderColor = borderColor.cgColor
                }
            }
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        borderStyle = .none
        layer.borderColor = UIColor.lightGray.cgColor
        layer.borderWidth = 1
        layer.cornerRadius = 12

        labelControl.textColor = .dw_secondaryText()
        labelControl.font = .dw_regularFont(ofSize: 12)
        labelControl.text = label
        labelControl.translatesAutoresizingMaskIntoConstraints = false
        labelControl.clipsToBounds = true
        labelControl.frame = CGRect(x: 0, y: 0, width: frame.size.width, height: 18)

        addSubview(labelControl)

        labelControl.topAnchor.constraint(equalTo: topAnchor, constant: 10).isActive = true
        labelControl.leftAnchor.constraint(equalTo: leftAnchor, constant: 15).isActive = true

        outerBorder = CAShapeLayer()
        outerBorder.lineWidth = 4
        outerBorder.strokeColor = UIColor.dw_dashBlue().withAlphaComponent(0.2).cgColor
        outerBorder.fillColor = UIColor.clear.cgColor
        outerBorder.opacity = 0
        layer.addSublayer(outerBorder)

        addTarget(self, action: #selector(onEditingBegin), for: .editingDidBegin)
        addTarget(self, action: #selector(onEditingEnd), for: .editingDidEnd)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let path = UIBezierPath(roundedRect: bounds.inset(by: UIEdgeInsets(top: -2, left: -2, bottom: -2, right: -2)), cornerRadius: 14)
        outerBorder.path = path.cgPath
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: padding)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: padding)
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: padding)
    }

    @objc
    func onEditingBegin() {
        outerBorder.opacity = 1
        layer.borderColor = UIColor.dw_dashBlue().cgColor
    }

    @objc
    func onEditingEnd() {
        outerBorder.opacity = 0
        layer.borderColor = borderColor.cgColor
    }
}
