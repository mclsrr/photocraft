use serde_json::json;

use crate::PhotocraftApp;
use crate::canvas::{ToolEvent, tool_event};
use crate::state::Tool;

fn app(tool: Tool) -> Box<PhotocraftApp> {
    let mut app = PhotocraftApp::new(photocraft_engine::Session::new(), crate::Services::default());
    app.run("file.new", json!({"width": 400, "height": 300, "background": "transparent"})).unwrap();
    app.run("shape.create", json!({"kind": "rect", "rect": [0, 0, 200, 300], "fill": "#ff0000"})).unwrap();
    app.run("shape.create", json!({"kind": "rect", "rect": [200, 0, 200, 300], "fill": "#00ff00"})).unwrap();
    app.run("layer.new.layer", json!({})).unwrap();
    app.run("tools.setColors", json!({"foreground": [0.0, 0.0, 1.0, 1.0], "background": [1.0, 1.0, 1.0, 1.0]})).unwrap();
    app.ui.tool = tool;
    app.sync_views();
    app
}

/// Every drag pick applies, not only the release: the swatch follows the pointer.
#[test]
fn eyedropper_drag_updates_the_sampled_colour() {
    let mut app = app(Tool::Eyedropper);
    let none = egui::Modifiers::NONE;
    tool_event(&mut app, ToolEvent::Down { x: 100.0, y: 100.0, pressure: 1.0 }, none);
    assert_eq!(app.session.tools.foreground, [1.0, 0.0, 0.0, 1.0], "the press picked the red half");
    tool_event(&mut app, ToolEvent::Move { x: 300.0, y: 100.0, pressure: 1.0 }, none);
    assert_eq!(app.session.tools.foreground, [0.0, 1.0, 0.0, 1.0], "the drag picked the green half before the release");
    tool_event(&mut app, ToolEvent::Up { x: 300.0, y: 100.0 }, none);
    assert_eq!(app.session.tools.foreground, [0.0, 1.0, 0.0, 1.0]);
    // Alt picks the background, and leaves the foreground.
    tool_event(&mut app, ToolEvent::Down { x: 100.0, y: 100.0, pressure: 1.0 }, egui::Modifiers::ALT);
    tool_event(&mut app, ToolEvent::Up { x: 100.0, y: 100.0 }, egui::Modifiers::ALT);
    assert_eq!(app.session.tools.background, [1.0, 0.0, 0.0, 1.0]);
    assert_eq!(app.session.tools.foreground, [0.0, 1.0, 0.0, 1.0]);
}

/// The sampling ring stays up for the whole drag, also through passes without pointer input (the
/// tools are rebuilt on every pass, and the ring used to vanish on those, so it flickered), and its
/// lower half keeps the colour the drag started from instead of turning into each new pick.
#[test]
fn the_sampling_ring_holds_still_through_idle_passes_and_keeps_the_old_colour() {
    let mut app = app(Tool::Eyedropper);
    let none = egui::Modifiers::NONE;
    let blue = [0.0, 0.0, 1.0];
    tool_event(&mut app, ToolEvent::Down { x: 100.0, y: 100.0, pressure: 1.0 }, none);
    tool_event(&mut app, ToolEvent::Move { x: 300.0, y: 100.0, pressure: 1.0 }, none);
    crate::canvas::testing::frame(&mut app);
    crate::canvas::testing::frame(&mut app);
    let ring = app.canvas_tools.eyedropper.ring.expect("the ring is still up between pointer moves");
    assert_eq!([ring.new.r, ring.new.g, ring.new.b], [0.0, 1.0, 0.0], "the upper half is the colour under the pointer");
    assert_eq!([ring.before.r, ring.before.g, ring.before.b], blue, "the lower half keeps the foreground from before the press");
    tool_event(&mut app, ToolEvent::Up { x: 300.0, y: 100.0 }, none);
    assert!(app.canvas_tools.eyedropper.ring.is_none(), "the ring goes with the release");
}
