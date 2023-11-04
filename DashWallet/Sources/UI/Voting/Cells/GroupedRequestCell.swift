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

protocol HeightChangedDelegate {
    func heightChanged()
}

final class GroupedRequestCell: UITableViewCell {

    var heightDelegate: HeightChangedDelegate?
    var model: [UsernameRequest] = []
    private var dataSource: DataSource! = nil

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
    
    private let chevron: UIImageView = {
        let image = UIImageView(image: UIImage(systemName: "chevron.down"))
        image.contentMode = .scaleAspectFill
        image.tintColor = .dw_label()
        image.translatesAutoresizingMaskIntoConstraints = false
        return image
    }()
    
    private let container: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.backgroundColor = .systemBackground
        stackView.layer.cornerRadius = 10
        stackView.axis = .vertical
        return stackView
    }()

    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.estimatedRowHeight = 44
        tableView.rowHeight = UITableView.automaticDimension
        tableView.isScrollEnabled = false
        tableView.separatorStyle = .singleLine
        tableView.register(UsernameRequestCell.self, forCellReuseIdentifier: UsernameRequestCell.description())
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.tableFooterView = UIView(frame: .zero)
        return tableView
    }()
}

private extension GroupedRequestCell {
    func configureLayout() {
        toggleArea.addTarget(self, action: #selector(expandOrCollapse), for: .touchUpInside)
        toggleArea.addSubview(username)
        toggleArea.addSubview(chevron)
        toggleArea.addSubview(requestsAmount)
        container.addArrangedSubview(toggleArea)
        
        tableView.isHidden = true
        tableView.delegate = self
        container.addArrangedSubview(tableView)
        
        contentView.addSubview(container)
        contentView.backgroundColor = .dw_secondaryBackground()
        
        NSLayoutConstraint.activate([
            toggleArea.heightAnchor.constraint(equalToConstant: 50),

            tableView.topAnchor.constraint(equalTo: toggleArea.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            username.topAnchor.constraint(equalTo: toggleArea.topAnchor, constant: 18),
            username.leadingAnchor.constraint(equalTo: toggleArea.leadingAnchor, constant: 15),
            
            requestsAmount.topAnchor.constraint(equalTo: username.topAnchor),
            requestsAmount.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10),
            requestsAmount.bottomAnchor.constraint(equalTo: username.bottomAnchor),
            
            chevron.heightAnchor.constraint(equalToConstant: 14),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.topAnchor.constraint(equalTo: username.topAnchor),
            chevron.trailingAnchor.constraint(equalTo: toggleArea.trailingAnchor, constant: -15),
            chevron.bottomAnchor.constraint(equalTo: username.bottomAnchor),
            
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -15),
        ])
    }
    
    @objc func expandOrCollapse() {
        let shouldHide = !self.tableView.isHidden
        
        if !shouldHide {
            updateInnerTableViewHeight()
        }
        
        self.tableView.isHidden = shouldHide
        self.container.setNeedsLayout()
        self.heightDelegate?.heightChanged()
        
        UIView.transition(with: container,
                          duration: 0.3,
                          options: .curveEaseInOut) { [weak self] in
            let transform = shouldHide ? CGAffineTransform.identity : CGAffineTransform(rotationAngle: CGFloat.pi)
            self?.chevron.transform = transform
        }
    }
}

extension GroupedRequestCell {
    func configure(withModel model: [UsernameRequest]) {
        self.model = model
        self.username.text = model.first?.username
        self.requestsAmount.text = String.localizedStringWithFormat(NSLocalizedString("%ld requests", comment: "Voting"), model.count)
        self.configureDataSource()
        self.reloadDataSource(data: model)
    }
    
    func updateInnerTableViewHeight() {
        let contentHeight = tableView.contentSize.height
        tableView.heightAnchor.constraint(equalToConstant: contentHeight).isActive = true
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
        contentView.dw_showInfoHUD(withText: NSLocalizedString("Selected row with \(request.votes) votes", comment: ""))
    }
}

