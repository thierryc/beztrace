// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

/// Ink coverage sampled in the same y-up pixel space as subpixel contours.
struct RasterTarget: Equatable, Sendable {
    let coverageValues: [Float]
    let width: Int
    let height: Int
    let pixelsPerUnit: Double

    init(raster: GrayRaster, invert: Bool, pixelsPerUnit: Double) {
        let low = raster.pixels.min() ?? 0
        let high = raster.pixels.max() ?? 255
        let range = max(Float(high) - Float(low), 1)
        coverageValues = raster.pixels.map { pixel in
            let coverage = (Float(high) - Float(pixel)) / range
            return invert ? 1 - coverage : coverage
        }
        width = raster.width
        height = raster.height
        self.pixelsPerUnit = max(pixelsPerUnit, 1e-6)
    }

    func coverage(x: Double, yUp: Double) -> Double {
        let u = x - 0.5
        let v = Double(height) - yUp - 0.5
        let x0 = floor(u)
        let y0 = floor(v)
        let fx = u - x0
        let fy = v - y0
        func at(_ x: Double, _ y: Double) -> Double {
            let ix = min(max(Int(max(x, 0)), 0), width - 1)
            let iy = min(max(Int(max(y, 0)), 0), height - 1)
            return Double(coverageValues[iy * width + ix])
        }
        let c00 = at(x0, y0)
        let c10 = at(x0 + 1, y0)
        let c01 = at(x0, y0 + 1)
        let c11 = at(x0 + 1, y0 + 1)
        return c00 * (1 - fx) * (1 - fy)
            + c10 * fx * (1 - fy)
            + c01 * (1 - fx) * fy
            + c11 * fx * fy
    }
}
