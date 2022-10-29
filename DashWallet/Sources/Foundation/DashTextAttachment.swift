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

import Foundation

final class DashTextAttachment: NSTextAttachment {
    private let verticalOffset: CGFloat
    
    init(image: UIImage, verticalOffset: CGFloat) {
        self.verticalOffset = verticalOffset
        super.init(data: nil, ofType: nil)
        self.image = image
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        
        let height = lineFrag.size.height
        var scale: CGFloat = 1.0
        let imageSize = image?.size ?? .zero
        
        if (height < imageSize.height) {
            scale = height/imageSize.height - 0.3;
        }
        
        return CGRect(x: 0, y: verticalOffset, width: imageSize.width*scale, height: imageSize.height*scale);
    }
}
