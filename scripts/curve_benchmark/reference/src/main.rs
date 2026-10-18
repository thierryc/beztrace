// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Maintenance driver calling unmodified kurbo APIs; no upstream code translated.
use kurbo::{BezPath, Point, fit_to_cubic, simplify::SimplifyBezPath};
use serde_json::{Value, json};
use std::{hint::black_box, io::{self, Read}, time::Instant};

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let jobs: Value = serde_json::from_str(&input).unwrap();
    let repeats = jobs["repeats"].as_u64().unwrap() as usize;
    let mut results = Vec::new();
    for job in jobs["jobs"].as_array().unwrap() {
        if job["line"].as_bool().unwrap() { continue; }
        let mut path = BezPath::new();
        for (i, coordinates) in job["curves"].as_array().unwrap().iter().enumerate() {
            let c: Vec<f64> = coordinates.as_array().unwrap().iter().map(|x| x.as_f64().unwrap()).collect();
            if i == 0 { path.move_to(Point::new(c[0], c[1])); }
            path.curve_to((c[2],c[3]), (c[4],c[5]), (c[6],c[7]));
        }
        let source = SimplifyBezPath::new(path.iter());
        for tol in jobs["tolerances"].as_array().unwrap() {
            let tolerance = tol.as_f64().unwrap();
            let mut times = Vec::new();
            let mut result = None;
            for round in 0..repeats+2 {
                let start = Instant::now();
                let r = black_box(fit_to_cubic(black_box(&source),0.0..1.0,black_box(tolerance)));
                let elapsed = start.elapsed().as_secs_f64()*1000.0;
                if round >= 2 { times.push(elapsed); }
                result = r;
            }
            let curve = result.map(|(c,_)| vec![c.p0.x,c.p0.y,c.p1.x,c.p1.y,c.p2.x,c.p2.y,c.p3.x,c.p3.y]);
            results.push(json!({"id":job["id"],"tolerance":tol,"method":"levien-kurbo-0.13.1","curve":curve,"line":false,"timesMs":times}));
        }
    }
    println!("{}",serde_json::to_string(&results).unwrap());
}
