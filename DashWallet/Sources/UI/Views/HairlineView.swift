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

class HairlineView: UIView {
    @IBInspectable var separatorColor: UIColor = .separator
    
    override var intrinsicContentSize: CGSize { .init(width: HairlineView.noIntrinsicMetric, height: 1/UIScreen.main.scale) }
    
    func drawHairline(in context: CGContext, scale: CGFloat, color: CGColor, rect: CGRect) {
        
        let center: CGFloat
        if Int(scale) % 2 == 0 {
            center = 1/(scale * 2)
        } else {
            center = 0
        }
        
        let offset = 0.5 - center
        let p1 = CGPoint(x: 0, y: rect.maxY - offset)
        let p2 = CGPoint(x: rect.maxX, y: rect.maxY - offset)
        
        let width = 1/scale
        context.setLineWidth(width)
        context.setStrokeColor(color)
        context.beginPath()
        context.move(to: p1)
        context.addLine(to: p2)
        context.strokePath()
    }
    
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        drawHairline(in: context!, scale: UIScreen.main.scale, color: UIColor.separator.withAlphaComponent(0.5).cgColor, rect: rect)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }
}
