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
import Combine

func cellSize(for contentSizeCategory: UIContentSizeCategory) -> CGSize {
    let screenWidth = UIScreen.main.bounds.size.width
    let margin: CGFloat = 10.0       // Figma: container px padding
    let spacing: CGFloat = 4.0       // Figma: shortcut-bar/gap
    let visibleCells: CGFloat = 4.0
    let cellWidth = floor((screenWidth - margin * 2.0 - spacing * (visibleCells - 1)) / visibleCells)
    let cellHeight: CGFloat = 68.0   // Figma: icon(46) + gap(4) + text(16) + bottomPad(2)

    if UIDevice.isIpad {
        return CGSize(width: cellWidth * 2.0, height: cellHeight)
    }

    return CGSize(width: cellWidth, height: cellHeight)
}


// MARK: - ShortcutsActionDelegate

protocol ShortcutsActionDelegate: AnyObject {
    func shortcutsView(didSelectAction action: ShortcutAction, sender: UIView?)
    func shortcutsView(didLongPressPosition position: Int, currentAction: ShortcutAction)
}

// MARK: - ShortcutsViewDelegate

protocol ShortcutsViewDelegate: AnyObject {
    func shortcutsViewDidUpdateContentSize(_ shortcutsView: ShortcutsView)
}

// MARK: - ShortcutsView

class ShortcutsView: UIView {
    private var cancellableBag = Set<AnyCancellable>()
    private let viewModel: HomeViewModel
    
    weak var actionDelegate: ShortcutsActionDelegate?

    weak var delegate: ShortcutsViewDelegate?

    @IBOutlet
    weak var contentView: UIView!

    @IBOutlet
    weak var collectionView: UICollectionView!

    @IBOutlet
    var collectionViewHeightConstraint: NSLayoutConstraint!

    init(frame: CGRect, viewModel: HomeViewModel) {
        self.viewModel = viewModel
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        viewModel.$shortcutItems
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.collectionView.reloadData()
            }
            .store(in: &cancellableBag)
        
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

        collectionView.layer.cornerRadius = 16
        collectionView.layer.masksToBounds = true

        if UIDevice.current.userInterfaceIdiom == .pad {
            collectionView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        }

        collectionView.register(UINib(nibName: "DWShortcutCollectionViewCell", bundle: nil), forCellWithReuseIdentifier: ShortcutCell.reuseIdentifier)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        collectionView.addGestureRecognizer(longPress)

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
        var cellSize = cellSize(for: contentSizeCategory)
        cellSize.height = ceil(cellSize.height) // This fixes the autolayout issue when the size of the cell is higher than the collection view itself

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

    @objc
    private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }

        let point = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point) else { return }

        let position = indexPath.item
        guard position < viewModel.shortcutItems.count else { return }

        let action = viewModel.shortcutItems[position]
        actionDelegate?.shortcutsView(didLongPressPosition: position, currentAction: action)
    }
}

// MARK: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout

extension ShortcutsView: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let action = viewModel.shortcutItems[indexPath.item]

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
        viewModel.shortcutItems.count
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        let action = viewModel.shortcutItems[indexPath.item]
        guard action.enabled else { return }
        guard let cell = collectionView.cellForItem(at: indexPath) else { return }

        actionDelegate?.shortcutsView(didSelectAction: action, sender: cell)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        guard let collectionViewLayout = collectionViewLayout as? UICollectionViewFlowLayout else { return UIEdgeInsets.zero }

        let cellSpacing = collectionViewLayout.minimumLineSpacing
        let cellWidth = collectionViewLayout.itemSize.width

        let cellCount = CGFloat(collectionView.numberOfItems(inSection: section))
        var inset = (collectionView.bounds.size.width - (cellCount * cellWidth) - ((cellCount - 1) * cellSpacing)) * 0.5
        inset = max(inset, 0.0)
        return UIEdgeInsets(top: 0.0, left: inset, bottom: 0.0, right: inset)
    }
}

// MARK: ShortcutsModelDataSource, ShortcutsModelDelegate

extension ShortcutsView {
    // TODO: DashPay
    func shouldShowCreateUserNameButton() -> Bool {
        false
    }
}
