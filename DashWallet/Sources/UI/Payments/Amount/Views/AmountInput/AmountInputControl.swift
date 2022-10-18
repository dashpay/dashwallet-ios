//  
//  Created by tkhp
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

private let kBigAmountTextAlpha = 1.0
private let kSmallAmountTextAlpha = 0.47

private let kMainAmountLabelHeight: CGFloat = 40
private let kSupplementaryAmountLabelHeight: CGFloat = 20

private let kMainAmountFontSize: CGFloat = 34
private let kSupplementaryAmountFontSize: CGFloat = 17

protocol AmountInputControlDelegate: AnyObject {
    func amountInputControlChangeCurrencyDidTap(_ control: AmountInputControl)
}

protocol AmountInputControlDataSource: AnyObject {
    var dashAttributedString: NSAttributedString { get }
    var localCurrencyAttributedString: NSAttributedString { get }
}

extension AmountInputControl.AmountType {
    func toggle() -> Self {
        self == .dash ? .fiat : .dash
    }
}

class AmountInputControl: UIControl {
    enum Style {
        case basic
        case oppositeAmount
    }
    
    enum AmountType {
        case dash
        case fiat
    }
    
    public var style: Style = .oppositeAmount
    public var amountType: AmountType = .dash
    
    public weak var delegate: AmountInputControlDelegate?
    public weak var dataSource: AmountInputControlDataSource? {
        didSet {
            reloadData()
        }
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: mainAmountLabel.bounds.width, height: contentHeight)
    }
    
    private var contentView: UIControl!
    private var mainAmountLabel: UILabel!
    private var supplementaryAmountLabel: UILabel!
    
    private var currencySelectorButton: UIButton!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    func reloadData() {
        mainAmountLabel.attributedText = dataSource?.dashAttributedString
        supplementaryAmountLabel.attributedText = dataSource?.localCurrencyAttributedString
    }
    
    func setActiveType(_ type: AmountType, animated: Bool, completion: (() -> Void)?) {
        let wasSwapped = type != .fiat
        let bigLabel: UILabel = wasSwapped ? supplementaryAmountLabel : mainAmountLabel
        let smallLabel: UILabel = wasSwapped ? mainAmountLabel : supplementaryAmountLabel
        
        let scale = kSupplementaryAmountFontSize/kMainAmountFontSize
        
        
        bigLabel.font = .dw_regularFont(ofSize: kSupplementaryAmountFontSize)
        bigLabel.transform = CGAffineTransformMakeScale(1.0 / scale, 1.0 / scale);
        
        smallLabel.frame = CGRect(x: 0, y: smallLabel.frame.minY, width: bounds.width, height: kMainAmountLabelHeight)
        smallLabel.font = .dw_regularFont(ofSize: kMainAmountFontSize)
        smallLabel.transform = CGAffineTransformMakeScale(scale, scale);
     
        let updateAlphaAndTransform = {
            bigLabel.transform = CGAffineTransformIdentity;
            smallLabel.transform = CGAffineTransformIdentity;
            bigLabel.alpha = kSmallAmountTextAlpha
            smallLabel.alpha = kBigAmountTextAlpha
        }
        
        // Change possition
        let bigFramePosition = CGRect(x: 0, y: 0, width: bounds.width, height: kMainAmountLabelHeight)
        let smallFramePosition = CGRect(x: 0, y: kMainAmountLabelHeight, width: bounds.width, height: kSupplementaryAmountLabelHeight)
        
        let changePossiton = {
            bigLabel.frame = smallFramePosition
            smallLabel.frame = bigFramePosition
        }
        
        if animated {
            UIView.animate(withDuration: 0.1, delay: 0.0, options: .curveEaseOut, animations: {
                updateAlphaAndTransform()
            }) { _ in
                UIView.animate(withDuration: 0.7, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 1.0, animations: {
                    changePossiton()
                }) { _ in
                    completion?()
                }
            }
           
        }else{
            updateAlphaAndTransform()
            changePossiton()
            completion?()
        }
    }
    
    
    @objc func switchAmountCurrencyAction() {
        let nextType = amountType.toggle()
        setActiveType(nextType, animated: true, completion: nil)
        amountType = nextType
    }
}

//MARK: Layout
extension AmountInputControl {
    override func layoutSubviews() {
        super.layoutSubviews()
        
        mainAmountLabel.frame = CGRect(x: 0, y: 0, width: bounds.width, height: kMainAmountLabelHeight)
        supplementaryAmountLabel.frame = CGRect(x: 0, y: mainAmountLabel.bounds.maxY, width: bounds.width, height: kSupplementaryAmountLabelHeight)
    }
}

//MARK: Private
extension AmountInputControl {
    private func configureHierarchy() {
        clipsToBounds = false
        
        self.contentView = UIControl()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false
        addSubview(contentView)
        
        self.mainAmountLabel = label(with: .dw_regularFont(ofSize: kMainAmountFontSize))
        mainAmountLabel.text = "10DASH"
        contentView.addSubview(mainAmountLabel)
        
        self.supplementaryAmountLabel = label(with: .dw_regularFont(ofSize: kSupplementaryAmountFontSize))
        supplementaryAmountLabel.text = "10$"
        contentView.addSubview(supplementaryAmountLabel)

        mainAmountLabel.frame = CGRect(x: 0, y: 0, width: bounds.width, height: kMainAmountLabelHeight)
        supplementaryAmountLabel.frame = CGRect(x: 0, y: mainAmountLabel.bounds.maxY, width: bounds.width, height: kSupplementaryAmountLabelHeight)
        
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}

//MARK: Utils

extension AmountInputControl {
    var contentHeight: CGFloat {
        style == .basic ? 40 : 60
    }
    
    func label(with font: UIFont) -> UILabel {
        let label = UILabel()
        label.minimumScaleFactor = 0.5
        label.adjustsFontSizeToFitWidth = true
        label.isUserInteractionEnabled = true
        label.textAlignment = .center
        label.font = font
        label.clipsToBounds = false
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(switchAmountCurrencyAction))
        label.addGestureRecognizer(tapGesture)
        
        return label
    }
}
