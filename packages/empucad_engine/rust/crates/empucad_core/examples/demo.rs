use empucad_core::cam::*;
use empucad_core::gcode::*;
use empucad_core::geom2d::Region;
use empucad_core::types::Polyline;
fn main() {
    let geo = Geometry { region: Region::from_outlines(&[Polyline::closed(vec![[0., 0.], [20., 0.], [20., 20.], [0., 20.]])]), lines: vec![] };
    let tool = Tool::end_mill(3.0);
    let cut = CutParams { depth: 2.0, step_down: 1.0, ..Default::default() };
    let paths = Profile { side: Side::Outside }.generate(&geo, &tool, &cut);
    let prog = Program { sections: vec![Section { name: "Cut out".into(), tool_number: 1, feed: 800.0, plunge: 300.0, rpm: 12000.0, paths }] };
    let o = Output::new(Post::by_id("grbl").unwrap());
    print!("{}", write(&prog, &o));
    println!("; est {:.1}s", estimate_seconds(&prog, &o));
}
