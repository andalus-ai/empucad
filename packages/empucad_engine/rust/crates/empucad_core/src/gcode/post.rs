//! Controller dialects as data. Supporting a new controller means adding a row, not a branch.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ToolChange {
    /// `M0` pause with the tool named in a comment (hobby GRBL machines).
    Pause,
    /// `T<n> M6`.
    M6,
}

#[derive(Debug, PartialEq, Eq)]
pub struct Post {
    pub id: &'static str,
    pub name: &'static str,
    pub ext: &'static str,
    pub tool_change: ToolChange,
    pub setup: &'static str,
    pub end: &'static str,
    pub line_numbers: bool,
    pub semicolon_comments: bool,
}

pub static POSTS: [Post; 5] = [
    Post { id: "grbl", name: "GRBL / grblHAL / FluidNC", ext: "gcode", tool_change: ToolChange::Pause, setup: "", end: "M30", line_numbers: false, semicolon_comments: false },
    Post { id: "linuxcnc", name: "LinuxCNC", ext: "ngc", tool_change: ToolChange::M6, setup: "G40 G49 G80 G54", end: "M2", line_numbers: false, semicolon_comments: false },
    Post { id: "mach", name: "Mach3 / Mach4", ext: "tap", tool_change: ToolChange::M6, setup: "G40 G49 G80 G54", end: "M30", line_numbers: true, semicolon_comments: false },
    Post { id: "marlin", name: "Marlin", ext: "gcode", tool_change: ToolChange::Pause, setup: "", end: "", line_numbers: false, semicolon_comments: true },
    Post { id: "generic", name: "Generic ISO G-code", ext: "nc", tool_change: ToolChange::M6, setup: "G40 G49 G80", end: "M30", line_numbers: false, semicolon_comments: false },
];

impl Post {
    pub fn by_id(id: &str) -> Option<&'static Post> {
        POSTS.iter().find(|p| p.id == id)
    }
}
