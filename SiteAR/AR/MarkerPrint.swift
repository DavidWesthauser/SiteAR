import UIKit
import SwiftUI

/// A unique, asymmetric, high-contrast visual target. Physical width must be measured after printing.
enum MarkerPrint {
    static func make(id: UUID) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1000))
        let image = renderer.image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0,y: 0,width: 900,height: 1000))
            let bytes = Array(id.uuidString.utf8)
            var seed: UInt64 = 1469598103934665603
            for b in bytes { seed = (seed ^ UInt64(b)) &* 1099511628211 }
            func random() -> UInt64 { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return seed }
            for row in 0..<20 { for col in 0..<20 {
                let value = random()
                UIColor(white: CGFloat(value % 5) / 5, alpha: 1).setFill()
                let rect = CGRect(x: 40+col*41, y: 40+row*41, width: 36, height: 36)
                if value % 3 == 0 { context.cgContext.fillEllipse(in: rect) } else { context.fill(rect) }
            } }
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 28), .foregroundColor: UIColor.black]
            ("SiteAR • \(id.uuidString.prefix(8))" as NSString).draw(at: CGPoint(x: 40,y: 890), withAttributes: attributes)
            ("Keep fixed. Measure full image width." as NSString).draw(at: CGPoint(x: 40,y: 935), withAttributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.black])
        }
        return image.pngData()!
    }
}
struct PrintSheet: UIViewControllerRepresentable {
    let data: Data
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [UIImage(data: data)!], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
