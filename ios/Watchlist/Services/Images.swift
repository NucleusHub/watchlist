import UIKit

enum Images {
    /// A photo shrunk and inlined as a JPEG data URL, how custom posters are stored (480 px, 0.72).
    static func dataURL(_ data: Data, maxEdge: CGFloat = 480, quality: CGFloat = 0.72) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        return dataURL(image, maxEdge: maxEdge, quality: quality)
    }

    static func dataURL(_ image: UIImage, maxEdge: CGFloat = 480, quality: CGFloat = 0.72) -> String? {
        jpeg(image, maxEdge: maxEdge, quality: quality).map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
    }

    static func jpeg(_ image: UIImage, maxEdge: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Posters may be a URL or an inlined data URL.
    static func image(fromDataURL string: String) -> UIImage? {
        guard string.hasPrefix("data:"), let comma = string.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(string[string.index(after: comma)...])).flatMap(UIImage.init(data:))
    }
}
