import CoreVideo
import Foundation

/// A square in the top-left corner of the picture that the stream probe switches between black and
/// white. The phone reads its brightness in each decoded frame, to tell the Mac when it saw a switch.
public enum LatencyMarker {
    /// The square, as fractions of the picture's width and height. Large enough to survive compression.
    public static let size = 0.12
    /// Luma halfway between black (16) and white (235) in video range.
    public static let threshold: UInt8 = 126

    /// The mean luma of the middle of the square, sampled on a grid, so a few compression artifacts
    /// don't matter. Reads the first plane, which is luma in the NV12 buffers the decoder makes.
    public static func luma(of pixelBuffer: CVPixelBuffer) -> UInt8 {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)?.assumingMemoryBound(to: UInt8.self) else {
            preconditionFailure("Expected a planar NV12 buffer")
        }
        // The middle half of the square in each direction.
        let side = Double(min(width, height)) * size
        var sum = 0
        var count = 0
        for gridY in 0..<8 {
            for gridX in 0..<8 {
                let x = Int(side * (0.25 + 0.5 * Double(gridX) / 7))
                let y = Int(side * (0.25 + 0.5 * Double(gridY) / 7))
                sum += Int(base[y * rowBytes + x])
                count += 1
            }
        }
        return UInt8(sum / count)
    }

    public static func isWhite(_ pixelBuffer: CVPixelBuffer) -> Bool {
        luma(of: pixelBuffer) > threshold
    }
}

/// Makes NV12 test pictures for the stream probe without screen capture: a scrolling pattern, so the
/// encoder has motion to compress as in a game, with the ``LatencyMarker`` drawn on top.
public final class TestPattern {
    public let width: Int
    public let height: Int
    private let pool: CVPixelBufferPool

    public struct PoolError: Error {
        public let status: CVReturn
    }

    public init(width: Int = 854, height: Int = 480) throws {
        self.width = width
        self.height = height
        let attributes = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ] as CFDictionary
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, nil, attributes, &pool)
        guard status == kCVReturnSuccess, let pool else { throw PoolError(status: status) }
        self.pool = pool
    }

    /// The picture at frame `number`, with the marker white or black.
    public func frame(_ number: Int, markerWhite: Bool) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw PoolError(status: status) }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
        let lumaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let markerSide = Int(Double(min(width, height)) * LatencyMarker.size)
        for y in 0..<height {
            let row = luma + y * lumaRow
            for x in 0..<width {
                if x < markerSide, y < markerSide {
                    row[x] = markerWhite ? 235 : 16
                } else {
                    // Diagonal stripes moving 4 pixels a frame, between dark and mid gray.
                    row[x] = UInt8(40 + ((x + y + number * 4) / 16 % 2) * 80 + (x * 37 / width))
                }
            }
        }
        // Gray chroma, then a band of colour moving down, so chroma changes too.
        let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!.assumingMemoryBound(to: UInt8.self)
        let chromaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        let band = (number * 2) % (height / 2)
        for y in 0..<height / 2 {
            let value: UInt8 = abs(y - band) < 20 ? 90 : 128
            memset(chroma + y * chromaRow, Int32(value), width)
        }
        return buffer
    }
}
