// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation

enum MatchingJSONValidation {
    static func validate(_ object: Any, preflight: Bool = false) throws {
        struct Invalid: Error {}
        func keys(_ value: Any, _ allowed: Set<String>) throws -> [String:Any] {
            guard let dictionary = value as? [String:Any], Set(dictionary.keys).isSubset(of:allowed) else { throw Invalid() }
            return dictionary
        }
        func outline(_ value: Any) throws {
            let value = try keys(value,["contours"])
            guard let contours = value["contours"] as? [Any] else { throw Invalid() }
            for contour in contours {
                let c = try keys(contour,["closed","nodes"])
                guard let nodes = c["nodes"] as? [Any] else { throw Invalid() }
                for node in nodes { _ = try keys(node,["x","y","type","smooth"]) }
            }
        }
        func master(_ value: Any) throws {
            let m = try keys(value,["id","outline"])
            guard let o = m["outline"] else { throw Invalid() }; try outline(o)
        }
        let root = try keys(object,preflight ? ["schemaVersion","unitsPerEm","reference","options","rasterOptions","referenceImage"] : ["schemaVersion","unitsPerEm","axis","reference","target","options","mode","images","rasterOptions"])
        if let axis = root["axis"] { _ = try keys(axis,["tag","locations"]) }
        if let options = root["options"] { _ = try keys(options,["referencePolicy","fitTolerance","contourPairs","startNodes","preserveStructure","maxAdditionalOnCurveNodes","maxOnCurveNodes","maxNodes"]) }
        if let reference = root["reference"] { try master(reference) }
        if let target = root["target"] { try master(target) }
        if preflight {
            if let image = root["referenceImage"] { _ = try keys(image,["id","imageData","transform"]) }
            if let rasterOptions = root["rasterOptions"] { _ = try keys(rasterOptions,["threshold","invert","minimumContourArea","smoothing","cornerThresholdDegrees"]) }
            return
        }
        if root["mode"] != nil {
            guard root["target"] == nil, let images = root["images"] as? [Any] else { throw Invalid() }
            for image in images { _ = try keys(image,["id","imageData","transform"]) }
            if let rasterOptions = root["rasterOptions"] {
                _ = try keys(rasterOptions,["threshold","invert","minimumContourArea","smoothing","cornerThresholdDegrees"])
            }
        } else if root["images"] != nil || root["rasterOptions"] != nil { throw Invalid() }
    }
}
