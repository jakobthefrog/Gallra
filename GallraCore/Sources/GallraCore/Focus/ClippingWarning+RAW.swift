import Foundation
import CoreImage
import CoreGraphics

extension ClippingWarning {
    nonisolated(unsafe) private static let ciContext = CIContext()

    /// Finds clipped areas from the RAW sensor data instead of the camera's JPEG preview, using
    /// Apple's RAW decoder with its tone curve and colour styling switched off. Takes roughly
    /// 0.1 to 0.4 s per photo, so call it off the main thread. Throws if the file is not a RAW
    /// Apple can decode (the caller then falls back to `mask(fromJPEG:)`).
    /// - Parameter maxPixel: long edge used for analysis (the RAW is decoded at reduced size).
    public static func mask(fromRAW url: URL, kind: ClippingKind, maxPixel: Int = 2048) throws -> FocusMask {
        // Apple's decoder also opens plain JPEG/TIFF, which would give nothing extra, so insist on a RAW format.
        guard PhotoFormat(fileExtension: url.pathExtension)?.isRaw == true,
              let raw = CIRAWFilter(imageURL: url) else { throw PreviewError.cannotRead }
        raw.boostAmount = 0
        raw.shadowBias = 0
        raw.baselineExposure = 0
        raw.isGamutMappingEnabled = false
        raw.isLensCorrectionEnabled = false
        raw.localToneMapAmount = 0
        raw.extendedDynamicRangeAmount = 0
        let native = raw.nativeSize
        guard native.width > 0, native.height > 0 else { throw PreviewError.cannotRead }
        raw.scaleFactor = Float(min(1, Double(maxPixel) / Double(max(native.width, native.height))))

        guard let image = raw.outputImage else { throw PreviewError.cannotRead }
        let w = Int(image.extent.width.rounded()), h = Int(image.extent.height.rounded())
        guard w >= 5, h >= 5 else { throw PreviewError.cannotRead }
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        ciContext.render(image, toBitmap: &rgba, rowBytes: w * 4, bounds: image.extent,
                         format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return mask(rgba: rgba, width: w, height: h, kind: kind)
    }
}
