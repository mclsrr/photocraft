//! An opt-in log of the pointer and mouse button messages the tablet hooks see, for diagnosing
//! pens whose buttons a driver maps to mouse buttons. Off unless `PHOTOCRAFT_INPUT_LOG` is set:
//! `1` appends to `photocraft-input.log` in the temporary folder, any other value is the path of
//! the file to append to. The UI writes its side of the same events to the same file.

use std::io::Write as _;
use std::sync::OnceLock;

/// The file the log appends to, or `None` when the log is off. Read once per process.
fn target() -> Option<&'static std::path::Path> {
    static TARGET: OnceLock<Option<std::path::PathBuf>> = OnceLock::new();
    TARGET
        .get_or_init(|| {
            let value = std::env::var_os("PHOTOCRAFT_INPUT_LOG").filter(|v| !v.is_empty() && v != "0")?;
            Some(if value == "1" { std::env::temp_dir().join("photocraft-input.log") } else { std::path::PathBuf::from(value) })
        })
        .as_deref()
}

/// Whether the input log is on.
pub fn enabled() -> bool {
    target().is_some()
}

/// Appends one line, stamped with the milliseconds since the Unix epoch. Failures are ignored:
/// the log is a diagnostic and must never disturb input handling.
pub fn line(text: &str) {
    let Some(path) = target() else { return };
    let ms = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_millis());
    if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "{ms} {text}");
    }
}
