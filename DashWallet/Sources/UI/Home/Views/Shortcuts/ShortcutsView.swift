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

import UIKit

func cellSize(for contentSizeCategory: UIContentSizeCategory) -> CGSize {
    var size = CGSize.zero

    if contentSizeCategory == .extraSmall ||
        contentSizeCategory == .small ||
        contentSizeCategory == .medium ||
        contentSizeCategory == .large {
        size = CGSize(width: 80.0, height: 95.0)
    } else if contentSizeCategory == .extraLarge {
        size = CGSize(width: 88.0, height: 95.0)
    } else if contentSizeCategory == .extraExtraLarge {
        size = CGSize(width: 100.0, height: 100.0)
    } else {
        size = CGSize(width: 116.0, height: 116.0)
    }

    if UIDevice.isIphone6Plus || UIDevice.hasHomeIndicator {
        let width = UIScreen.main.bounds.size.width
        let margin: CGFloat = 16.0
        let minSpacing: CGFloat = 8.0 // min cell spacing, set in xib
        let visibleCells: CGFloat = 4.0
        let cellWidth = (width - margin * 2.0 - minSpacing * (visibleCells - 1)) / visibleCells
        if cellWidth > size.width {
            return CGSize(width: cellWidth, height: cellWidth)
        }
    }

    if UIDevice.isIpad {
        return CGSize(width: size.width * 2.0, height: size.height)
    }

    return size
}


// MARK: - ShortcutsActionDelegate

@objc(DWShortcutsActionDelegate)
protocol ShortcutsActionDelegate: AnyObject {
    func shortcutsView(_ view: UIView, didSelectAction action: ShortcutAction, sender: UIView)
}

// MARK: - ShortcutsViewDelegate

@objc(DWShortcutsViewDelegate)
protocol ShortcutsViewDelegate: AnyObject {
    func shortcutsViewDidUpdateContentSize(_ shortcutsView: ShortcutsView)
}

// MARK: - ShortcutsView

@objc
class ShortcutsView: UIView {
    @objc
    weak var actionDelegate: ShortcutsActionDelegate?

    @objc
    weak var delegate: ShortcutsViewDelegate?

    @IBOutlet
    weak var contentView: UIView!

    @IBOutlet
    weak var collectionView: UICollectionView!

    @IBOutlet
    var collectionViewHeightConstraint: NSLayoutConstraint!

    var model = ShortcutsModel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func reloadData() {
        model.reloadShortcuts()
    }
    
    private func commonInit() {
        model.shortcutItemsDidChangeHandler = { [weak self] in
            self?.collectionView.reloadData()
        }

        Bundle.main.loadNibNamed(String(describing: type(of: self)), owner: self, options: nil)

        backgroundColor = .dw_secondaryBackground()

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: widthAnchor),
        ])


        collectionView.layer.cornerRadius = 8
        collectionView.layer.masksToBounds = true

        if UIDevice.current.userInterfaceIdiom == .pad {
            collectionView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        }

        collectionView.register(UINib(nibName: "DWShortcutCollectionViewCell", bundle: nil), forCellWithReuseIdentifier: ShortcutCell.reuseIdentifier)

        NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChangeNotification(notification:)),
                                               name: UIContentSizeCategory.didChangeNotification, object: nil)

        updateCellSizeForContentSizeCategory(UIApplication.shared.preferredContentSizeCategory, initialSetup: true)
    }

    @objc
    func contentSizeCategoryDidChangeNotification(notification: Notification) {
        guard let category = notification.userInfo?[UIContentSizeCategory.newValueUserInfoKey] as? UIContentSizeCategory else {
            return
        }
        updateCellSizeForContentSizeCategory(category, initialSetup: false)
    }

    private func updateCellSizeForContentSizeCategory(_ contentSizeCategory: UIContentSizeCategory, initialSetup: Bool) {
        let cellSize = cellSize(for: contentSizeCategory)
        collectionViewHeightConstraint.constant = cellSize.height
        setNeedsUpdateConstraints()

        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.itemSize = cellSize
            if !initialSetup {
                layout.invalidateLayout()
            }
        }
        collectionView.reloadData()

        if !initialSetup {
            delegate?.shortcutsViewDidUpdateContentSize(self)
        }
    }
}

// MARK: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout

extension ShortcutsView: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let action = model.items[indexPath.item]

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ShortcutCell.reuseIdentifier, for: indexPath) as! ShortcutCell
        cell.model = action

        #if SNAPSHOT
        if action.type == .secureWallet {
            cell.accessibilityIdentifier = "shortcut_secure_wallet"
        }
        #endif // SNAPSHOT

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        model.items.count
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        let action = model.items[indexPath.item]
        guard action.enabled else { return }
        guard let cell = collectionView.cellForItem(at: indexPath) else { return }

        actionDelegate?.shortcutsView(self, didSelectAction: action, sender: cell)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        guard let collectionViewLayout = collectionViewLayout as? UICollectionViewFlowLayout else { return UIEdgeInsets.zero }

        let cellSpacing = collectionViewLayout.minimumLineSpacing
        let cellWidth = collectionViewLayout.itemSize.width

        let cellCount = CGFloat(collectionView.numberOfItems(inSection: section))
        var inset = (collectionView.bounds.size.width - (cellCount * cellWidth) - ((cellCount - 1) * cellSpacing)) * 0.5
        inset = max(inset, 0.0)
        return UIEdgeInsets(top: 0.0, left: inset, bottom: 0.0, right: 0.0)
    }
}

// MARK: ShortcutsModelDataSource, ShortcutsModelDelegate

extension ShortcutsView {
    // TODO: DashPay
    func shouldShowCreateUserNameButton() -> Bool {
        false
    }
}
