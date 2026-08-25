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
    case invalidOptions
    case nonFiniteGeometry
    case noContours
    case invalidClosure(contour: Int)
    case degenerateSegment(contour: Int, segment: Int)
    case invalidWinding(contour: Int)
    case selfIntersection(contour: Int)
    case handleReachExceeded(contour: Int, segment: Int)
    case pointLimitExceeded(contour: Int, actual: Int, limit: Int)
}
