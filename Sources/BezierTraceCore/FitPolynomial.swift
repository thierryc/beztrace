// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Small ordered polynomial arithmetic and bounded real-root isolation.
import Foundation

enum FitPolynomial {
    static func add(_ a: [Double],_ b: [Double]) -> [Double] {
        var result=Array(repeating:0.0,count:max(a.count,b.count))
        for i in result.indices {
            let first:Double=i<a.count ? a[i] : 0
            let second:Double=i<b.count ? b[i] : 0
            result[i]=first+second
        }
        return result
    }
    static func scale(_ a: [Double],_ s: Double) -> [Double] { a.map { $0*s } }
    static func multiply(_ a: [Double],_ b: [Double]) -> [Double] {
        var result=Array(repeating:0.0,count:a.count+b.count-1)
        for i in a.indices { for j in b.indices { result[i+j]+=a[i]*b[j] } }
        return result
    }
    static func derivative(_ a: [Double]) -> [Double] {
        a.count>1 ? (1..<a.count).map { Double($0)*a[$0] } : [0]
    }
    static func value(_ a: [Double],_ x: Double) -> Double { a.reversed().reduce(0) { $0*x+$1 } }
    static func integral(_ a: [Double]) -> Double { a.enumerated().reduce(0) { $0+$1.element/Double($1.offset+1) } }

    /// Derivative roots divide the bounded interval into monotone pieces.
    /// Critical-point evaluation retains repeated roots; bisection is bounded.
    static func roots(_ coefficients: [Double],in range: ClosedRange<Double>) -> [Double] {
        guard !coefficients.isEmpty,coefficients.count<=6,coefficients.allSatisfy(\.isFinite),
              range.lowerBound.isFinite,range.upperBound.isFinite else { return [] }
        let scale=coefficients.map(abs).max() ?? 0
        guard scale>0 else { return [] }
        var c=coefficients.map { $0/scale }
        while c.count>1 && abs(c.last!)<1e-14 { c.removeLast() }
        guard c.count>1 else { return [] }
        if c.count==2 {
            let x = -c[0]/c[1]
            return x.isFinite && range.contains(x) ? [x] : []
        }
        let critical=roots(derivative(c),in:range)
        let cuts=[range.lowerBound]+critical+[range.upperBound]
        func zero(_ x: Double) -> Bool {
            let magnitude=c.enumerated().reduce(0.0) { $0+abs($1.element)*pow(abs(x),Double($1.offset)) }
            return abs(value(c,x))<=max(1,magnitude)*2e-13
        }
        var result=cuts.filter(zero)
        for (lo,hi) in zip(cuts,cuts.dropFirst()) {
            var a=lo,b=hi,fa=value(c,a)
            let fb=value(c,b)
            guard fa*fb<0 else { continue }
            for _ in 0..<64 {
                let mid=(a+b)/2
                if mid==a || mid==b { break }
                let fm=value(c,mid)
                if (fa<0)==(fm<0) { a=mid;fa=fm } else { b=mid }
            }
            result.append((a+b)/2)
        }
        var unique:[Double]=[]
        for x in result.sorted() where unique.last.map({ abs($0-x)>1e-9 }) ?? true { unique.append(x) }
        return unique
    }
}
