// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

enum CoreError: Error, Equatable, Sendable {
    case emptyInput
    case encodedInputTooLarge(actual: Int, limit: Int)
    case malformedImage
    case unsupportedImageFormat(String)
    case invalidDimensions(width: Int, height: Int)
    case decodedImageTooLarge(width: Int, height: Int, limit: Int)
    case invalidPixelStorage(expected: Int, actual: Int)
    case pixelBufferAllocationFailed
    case nonFiniteGeometry
    case noContours
}
