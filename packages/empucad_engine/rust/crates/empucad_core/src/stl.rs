//! Binary + ASCII STL. Import welds vertices so the result is an indexed mesh.
use crate::error::{EngineError, Result};
use crate::types::Mesh;
use std::collections::HashMap;

pub fn write_binary(mesh: &Mesh) -> Vec<u8> {
    let tris = mesh.triangle_count();
    let mut out = Vec::with_capacity(84 + tris * 50);
    let mut header = [0u8; 80];
    header[..16].copy_from_slice(b"EmpuCAD binary  ");
    out.extend_from_slice(&header);
    out.extend_from_slice(&(tris as u32).to_le_bytes());
    let v = |i: u32| {
        let k = i as usize * 3;
        [mesh.positions[k], mesh.positions[k + 1], mesh.positions[k + 2]]
    };
    for t in mesh.indices.chunks_exact(3) {
        let (a, b, c) = (v(t[0]), v(t[1]), v(t[2]));
        let (u, w) = ([b[0] - a[0], b[1] - a[1], b[2] - a[2]], [c[0] - a[0], c[1] - a[1], c[2] - a[2]]);
        let mut n = [u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0]];
        let len = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).sqrt();
        if len > 0.0 {
            n = [n[0] / len, n[1] / len, n[2] / len];
        }
        for f in n.iter().chain(a.iter()).chain(b.iter()).chain(c.iter()) {
            out.extend_from_slice(&f.to_le_bytes());
        }
        out.extend_from_slice(&[0, 0]);
    }
    out
}

pub fn read(bytes: &[u8]) -> Result<Mesh> {
    let looks_binary = bytes.len() >= 84 && {
        let n = u32::from_le_bytes([bytes[80], bytes[81], bytes[82], bytes[83]]) as usize;
        84 + n * 50 == bytes.len()
    };
    let soup = if looks_binary { read_binary(bytes) } else { read_ascii(bytes)? };
    Ok(weld(&soup))
}

fn read_binary(b: &[u8]) -> Vec<[f32; 3]> {
    let n = u32::from_le_bytes([b[80], b[81], b[82], b[83]]) as usize;
    let f = |o: usize| f32::from_le_bytes([b[o], b[o + 1], b[o + 2], b[o + 3]]);
    let mut out = Vec::with_capacity(n * 3);
    for t in 0..n {
        let base = 84 + t * 50 + 12;
        for v in 0..3 {
            let o = base + v * 12;
            out.push([f(o), f(o + 4), f(o + 8)]);
        }
    }
    out
}

fn read_ascii(b: &[u8]) -> Result<Vec<[f32; 3]>> {
    let text = std::str::from_utf8(b).map_err(|e| EngineError::Stl(e.to_string()))?;
    let mut out = Vec::new();
    for line in text.lines() {
        let mut it = line.split_whitespace();
        if it.next() == Some("vertex") {
            let p: Vec<f32> = it.filter_map(|s| s.parse().ok()).collect();
            if p.len() != 3 {
                return Err(EngineError::Stl("bad vertex line".into()));
            }
            out.push([p[0], p[1], p[2]]);
        }
    }
    if out.is_empty() || out.len() % 3 != 0 {
        return Err(EngineError::Stl("no triangles found".into()));
    }
    Ok(out)
}

fn weld(soup: &[[f32; 3]]) -> Mesh {
    let mut map: HashMap<[u32; 3], u32> = HashMap::new();
    let mut m = Mesh::default();
    for v in soup {
        let key = [v[0].to_bits(), v[1].to_bits(), v[2].to_bits()];
        let idx = *map.entry(key).or_insert_with(|| {
            m.positions.extend_from_slice(v);
            (m.positions.len() / 3 - 1) as u32
        });
        m.indices.push(idx);
    }
    m
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::csg::{cuboid, inspect};

    #[test]
    fn binary_roundtrip_keeps_a_closed_solid() {
        let cube = cuboid(10., 20., 30.);
        let back = read(&write_binary(&cube)).unwrap();
        assert_eq!(back.triangle_count(), cube.triangle_count());
        let r = inspect(&back);
        assert!(r.closed);
        assert!((r.volume - 6000.0).abs() < 1e-2);
    }

    #[test]
    fn ascii_is_parsed() {
        let s = "solid t\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid";
        let m = read(s.as_bytes()).unwrap();
        assert_eq!((m.vertex_count(), m.triangle_count()), (3, 1));
    }
}
