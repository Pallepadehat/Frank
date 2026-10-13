import SwiftUI

/// A tiny Frank: the blob with two googly eyes.
struct MiniFrank: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                BlobShape().fill(BlobShape.linear)
                HStack(spacing: w * 0.1) {
                    ForEach(0..<2, id: \.self) { _ in
                        Circle()
                            .fill(.white)
                            .frame(width: w * 0.26, height: w * 0.26)
                            .overlay(Circle().fill(Color(hex: Palette.ink)).frame(width: w * 0.12).offset(x: w * 0.02, y: w * 0.03))
                    }
                }
                .offset(y: -w * 0.04)
            }
        }
    }
}
