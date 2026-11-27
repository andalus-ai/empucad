use super::{expand_moves, Event, Output, Program, ToolChange};

fn num(v: f64) -> String {
    let s = format!("{v:.3}");
    let s = s.trim_end_matches('0').trim_end_matches('.');
    if s == "-0" || s.is_empty() { "0".into() } else { s.into() }
}

struct Lines<'a> {
    out: String,
    n: u32,
    numbered: bool,
    semi: bool,
    _p: std::marker::PhantomData<&'a ()>,
}
impl Lines<'_> {
    fn push(&mut self, l: &str) {
        if l.is_empty() {
            return;
        }
        if self.numbered {
            self.n += 10;
            self.out.push_str(&format!("N{} ", self.n));
        }
        self.out.push_str(l);
        self.out.push('\n');
    }
    fn comment(&mut self, c: &str) {
        let c = c.replace(['(', ')'], "");
        let l = if self.semi { format!("; {c}") } else { format!("({c})") };
        self.push(&l);
    }
}

/// Render a program as G-code text for the given post-processor.
pub fn write(program: &Program, o: &Output) -> String {
    let u = if o.inches { 1.0 / 25.4 } else { 1.0 };
    let mut l = Lines { out: String::new(), n: 0, numbered: o.post.line_numbers, semi: o.post.semicolon_comments, _p: Default::default() };
    l.comment(&format!("EmpuCAD - {}", o.post.name));
    l.push(if o.inches { "G20" } else { "G21" });
    l.push("G90");
    l.push(o.post.setup);

    let (mut last_g, mut last_f): (Option<u8>, Option<i64>) = (None, None);
    let mut last = [f64::NAN; 3];
    let mut spindle_on = false;
    for e in expand_moves(program, o) {
        match e {
            Event::Section(i) => {
                let s = &program.sections[i];
                if spindle_on {
                    l.push("M5");
                }
                l.comment(&format!("{} - tool {}", s.name, s.tool_number));
                match o.post.tool_change {
                    ToolChange::M6 => l.push(&format!("T{} M6", s.tool_number)),
                    ToolChange::Pause if i > 0 => l.push(&format!("M0 ({})", format!("change to tool {}", s.tool_number).replace(['(', ')'], ""))),
                    ToolChange::Pause => {}
                }
                if s.rpm > 0.0 {
                    l.push(&format!("M3 S{}", s.rpm.round() as i64));
                    if o.spin_up_secs > 0.0 {
                        l.push(&format!("G4 P{}", num(o.spin_up_secs)));
                    }
                    spindle_on = true;
                }
            }
            Event::Arc { x, y, z, i, j, cw, feed, .. } => {
                let g = if cw { 2 } else { 3 };
                // arcs repeat their G code on every line: clearer, and safe on controllers that treat it as non-modal
                let mut w = vec![format!("G{g}")];
                last_g = Some(g);
                w.push(format!("X{}", num(x * u)));
                w.push(format!("Y{}", num(y * u)));
                if (last[2] - z).abs() > 1e-6 || last[2].is_nan() {
                    w.push(format!("Z{}", num(z * u)));
                }
                w.push(format!("I{}", num(i * u)));
                w.push(format!("J{}", num(j * u)));
                let f = (feed * u).round() as i64;
                if last_f != Some(f) {
                    w.push(format!("F{f}"));
                    last_f = Some(f);
                }
                last = [x, y, z];
                l.push(&w.join(" "));
            }
            Event::Move { x, y, z, rapid, feed } => {
                let g = if rapid { 0 } else { 1 };
                let mut w = Vec::new();
                if last_g != Some(g) {
                    w.push(format!("G{g}"));
                    last_g = Some(g);
                }
                for (axis, v, k) in [("X", x, 0), ("Y", y, 1), ("Z", Some(z), 2)] {
                    if let Some(v) = v {
                        if last[k].is_nan() || (last[k] - v).abs() > 1e-6 {
                            w.push(format!("{axis}{}", num(v * u)));
                            last[k] = v;
                        }
                    }
                }
                if !rapid {
                    let f = (feed * u).round() as i64;
                    if last_f != Some(f) {
                        w.push(format!("F{f}"));
                        last_f = Some(f);
                    }
                }
                if !w.is_empty() {
                    l.push(&w.join(" "));
                }
            }
        }
    }
    if spindle_on {
        l.push("M5");
    }
    l.push(o.post.end);
    l.out
}

#[cfg(test)]
mod tests {
    use super::super::{tests::square_program, *};

    #[test]
    fn grbl_output_is_modal_and_ends_cleanly() {
        let g = write(&square_program(), &Output::new(Post::by_id("grbl").unwrap()));
        assert!(g.starts_with("(EmpuCAD - GRBL"));
        assert!(g.contains("G21\nG90\n"));
        assert!(g.contains("M3 S10000\nG4 P3\n"));
        assert!(g.trim_end().ends_with("M30"));
        assert!(g.contains("F600") && g.contains("F200"));
        // G1 is modal: it appears once per run of feed moves, not on every line
        let g1_lines = g.lines().filter(|l| l.starts_with("G1")).count();
        let feed_lines = g.lines().filter(|l| l.contains('X') || l.contains('Z')).count();
        assert!(g1_lines < feed_lines);
    }

    #[test]
    fn mach_numbers_lines_and_linuxcnc_uses_m6() {
        let mach = write(&square_program(), &Output::new(Post::by_id("mach").unwrap()));
        assert!(mach.lines().all(|l| l.starts_with('N')));
        let lc = write(&square_program(), &Output::new(Post::by_id("linuxcnc").unwrap()));
        assert!(lc.contains("T1 M6") && lc.contains("G40 G49 G80 G54") && lc.trim_end().ends_with("M2"));
    }

    #[test]
    fn marlin_uses_semicolon_comments_and_inches_scale() {
        let mut o = Output::new(Post::by_id("marlin").unwrap());
        assert!(write(&square_program(), &o).starts_with("; EmpuCAD"));
        o.inches = true;
        let g = write(&square_program(), &o);
        assert!(g.contains("G20"));
        assert!(g.contains("X0.394"), "10 mm should print as 0.394 in");
    }
}
