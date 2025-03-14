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

import UIKit

let kToogleAreaHeight = CGFloat(50)

final class GroupedRequestCell: UITableViewCell {
    private var model: [UsernameRequest] = []
    private var dataSource: DataSource! = nil
    private var containerHeightConstraint: NSLayoutConstraint!
    
    var onHeightChanged: (() -> ())?
    var onRequestSelected: ((UsernameRequest) -> ())?
    var onBlockTapped: ((UsernameRequest) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }
    
    private let toggleArea: UIControl = {
        let view = UIControl()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let username: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.dw_mediumFont(ofSize: 13)
        label.textColor = UIColor.dw_label()
        return label
    }()
    
    private let requestsAmount: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.dw_regularFont(ofSize: 13)
        label.textColor = UIColor.dw_tertiaryText()
        return label
    }()
    
    private let chevronButton: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        let image = UIImage(systemName: "chevron.down")!.withConfiguration(UIImage.SymbolConfiguration(scale: .small))
        button.setImage(image, for: .normal)
        button.tintColor = .dw_label()
        button.backgroundColor = .dw_secondaryBackground()
        button.layer.cornerRadius = 7
        button.isUserInteractionEnabled = false
        return button
    }()
    
    private let container: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.backgroundColor = .dw_background()
        stackView.layer.cornerRadius = 10
        stackView.axis = .vertical
        return stackView
    }()

    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.estimatedRowHeight = 60
        tableView.rowHeight = UITableView.automaticDimension
        tableView.isScrollEnabled = false
        tableView.separatorStyle = .none
        tableView.register(UsernameRequestCell.self, forCellReuseIdentifier: UsernameRequestCell.description())
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.tableFooterView = UIView(frame: .zero)
        tableView.backgroundColor = .dw_background()
        return tableView
    }()

    private let blockButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("0", for: .normal)
        let image = UIImage(named: "icon_thumbs_up")!
        button.setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
        button.imageView?.transform = CGAffineTransform(rotationAngle: .pi)
        button.tintColor = .dw_label()
        button.backgroundColor = .dw_secondaryBackground()
        button.layer.cornerRadius = 7
        button.semanticContentAttribute = .forceRightToLeft
        button.contentHorizontalAlignment = .center
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 0)

        return button
    }()
}

private extension GroupedRequestCell {
    func configureLayout() {
        toggleArea.addTarget(self, action: #selector(expandOrCollapse), for: .touchUpInside)
        toggleArea.addSubview(username)
        toggleArea.addSubview(requestsAmount)
        toggleArea.addSubview(chevronButton)

        toggleArea.addSubview(blockButton)
        blockButton.addTarget(self, action: #selector(blockButtonTapped), for: .touchUpInside)

        container.addArrangedSubview(toggleArea)
        containerHeightConstraint = container.heightAnchor.constraint(equalToConstant: kToogleAreaHeight)
        
        tableView.isHidden = true
        tableView.delegate = self
        container.addArrangedSubview(tableView)
        
        contentView.addSubview(container)
        contentView.backgroundColor = .dw_secondaryBackground()
        
        NSLayoutConstraint.activate([
            toggleArea.heightAnchor.constraint(equalToConstant: kToogleAreaHeight),

            tableView.topAnchor.constraint(equalTo: toggleArea.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            username.topAnchor.constraint(equalTo: toggleArea.topAnchor, constant: 18),
            username.leadingAnchor.constraint(equalTo: toggleArea.leadingAnchor, constant: 15),
            
            requestsAmount.topAnchor.constraint(equalTo: username.topAnchor),
            requestsAmount.leadingAnchor.constraint(equalTo: username.trailingAnchor, constant: 6),
            requestsAmount.bottomAnchor.constraint(equalTo: username.bottomAnchor),
            
            chevronButton.heightAnchor.constraint(equalToConstant: 30),
            chevronButton.widthAnchor.constraint(equalToConstant: 70),
            chevronButton.centerYAnchor.constraint(equalTo: username.centerYAnchor),
            chevronButton.trailingAnchor.constraint(equalTo: toggleArea.trailingAnchor, constant: -10),
            
            containerHeightConstraint,
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -15),

            blockButton.heightAnchor.constraint(equalToConstant: 30),
            blockButton.widthAnchor.constraint(equalToConstant: 70),
            blockButton.centerYAnchor.constraint(equalTo: username.centerYAnchor),
            blockButton.trailingAnchor.constraint(equalTo: chevronButton.leadingAnchor, constant: -10),
        ])
    }
    
    @objc func expandOrCollapse() {
        let shouldExpand = self.tableView.isHidden
        toggleCell(expand: shouldExpand)
    }
    
    private func toggleCell(expand: Bool) {
        if expand {
            updateInnerTableViewHeight()
        }
        
        self.tableView.isHidden = !expand
        self.container.setNeedsLayout()
        self.onHeightChanged?()
        
        UIView.transition(with: chevronButton.imageView ?? chevronButton,
                          duration: 0.3,
                          options: .curveEaseInOut) { [weak self] in
            let transform = expand ? CGAffineTransform(rotationAngle: CGFloat.pi) :  CGAffineTransform.identity
            self?.chevronButton.imageView?.transform = transform
        }
    }
    
    @objc private func blockButtonTapped() {
        guard let usernameRequest = model.last else { return }
        onBlockTapped?(usernameRequest)
    }
}

extension GroupedRequestCell {
    func configure(withModel model: [UsernameRequest]) {
        toggleCell(expand: false)
        
        self.model = model
        self.username.text = model.first?.username
        self.requestsAmount.text = String.localizedStringWithFormat(NSLocalizedString("%ld requests", comment: "Voting"), model.count)
        self.configureDataSource()
        self.reloadDataSource(data: model)

        let blockVotes = model.last?.blockVotes ?? 0
        let isBlocked = blockVotes > 0
        blockButton.backgroundColor = isBlocked ? .dw_red() : .dw_secondaryBackground()
        blockButton.tintColor = isBlocked ? .white : .dw_label()
        blockButton.setTitle("\(blockVotes)", for: .normal)
    }
    
    private func updateInnerTableViewHeight() {
        let contentHeight = tableView.contentSize.height
        containerHeightConstraint.constant = contentHeight + kToogleAreaHeight
        self.layoutIfNeeded()
    }
}

extension GroupedRequestCell {
    enum Section: CaseIterable {
        case main
    }
    
    class DataSource: UITableViewDiffableDataSource<Section, UsernameRequest> { }
    
    private func configureDataSource() {
        dataSource = DataSource(tableView: tableView) { [weak self]
            (tableView: UITableView, indexPath: IndexPath, item: UsernameRequest) -> UITableViewCell? in

            guard self != nil else { return UITableViewCell() }
            let cell = tableView.dequeueReusableCell(withIdentifier: UsernameRequestCell.description(), for: indexPath)

            if let requestCell = cell as? UsernameRequestCell {
                requestCell.configure(withModel: item)
                requestCell.onApproveTapped = { [weak self] username in
                    self?.onRequestSelected?(username)
                }
            }

            return cell
        }
    }
    
    private func reloadDataSource(data: [UsernameRequest]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, UsernameRequest>()
        snapshot.appendSections([.main])
        snapshot.appendItems(data)
        dataSource.apply(snapshot, animatingDifferences: false)
        dataSource.defaultRowAnimation = .none
    }
}


extension GroupedRequestCell: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let request = model[indexPath.row]
        onRequestSelected?(request)
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0
    }
}
