import UIKit
import ImageIO
import RealityKit

@MainActor struct PreparedSpatialImage {
    let data: Data
    let image: UIImage
    let texture: TextureResource
}
@MainActor enum SpatialImageAsset {
    static func prepare(_ data: Data) async throws -> PreparedSpatialImage {
        guard data.count<=30_000_000, let source=CGImageSourceCreateWithData(data as CFData,nil),
              let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:2048,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { throw AppError.message("Dieses Bild konnte nicht geladen werden (maximal 30 MB).") }
        let image=UIImage(cgImage:cg)
        guard let png=image.pngData() else { throw AppError.message("Bild konnte nicht verarbeitet werden.") }
        let texture: TextureResource
        if #available(iOS 18,*) { texture=try await TextureResource(image:cg,options:.init(semantic:.color)) }
        else { texture=try TextureResource.generate(from:cg,withName:nil,options:.init(semantic:.color)) }
        return PreparedSpatialImage(data:png,image:image,texture:texture)
    }
}
