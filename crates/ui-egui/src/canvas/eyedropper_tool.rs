//! The Eyedropper tool and the Alt stand-in that samples with a painting tool: PhotoCraft's two
//! uses of the framework's `EyedropperTool`.
//!
//! As the Eyedropper tool, a press and each drag sample the foreground (Alt: the background). As
//! the Alt stand-in, every sample goes to the foreground, because Alt is the key that called the
//! stand-in, and Shift+Alt adds a colour sampler at the clicked pixel instead (#11890). As the
//! Triangle or Custom Shape stand-in, a sample also becomes the tool's solid Fill, and Shift+Alt
//! samples as Alt does (#13364, #15856).

use craft::behavior::{CancelReason, Cursor, PointerButton};
use craft::color_ui::ui::{EyedropperTool, SampleSize, SampleSource};
use craft::keymap::Mods;
use craft::theme::Srgba;
use craft::ui::canvas::{CanvasTool, ToolAction, ToolContext, ToolHostResponse, ToolPath, ToolPointer};
use craft::ui::primitives::{Draw, PaintShape, StrokeWidth};
use craft::ui::style::{DataColor, StyleCx};
use serde_json::json;

use super::cursor_policy::shape_alt_sets_fill;
use super::document_display::CanvasHost;
use super::sampling;
use super::tools::{FamilyTool, ToolScope};
use crate::PhotocraftApp;

#[cfg(test)]
#[path = "../eyedropper_cmyk_tests.rs"]
mod cmyk_tests;

/// The gesture's flags, kept in `CanvasTools::eyedropper`.
#[derive(Debug, Default)]
pub(crate) struct EyedropperState {
    /// The running press added a colour sampler, so its drags sample nothing.
    sampler_added: bool,
    /// The sampling ring while the button is held. The tools are rebuilt on every pass, so the
    /// ring lives here: kept in the framework tool it was lost on every pass without pointer
    /// input, and the ring flickered.
    ring: Option<Ring>,
    /// The swatch colour the running gesture's first pick replaced: the ring's lower half.
    before: Option<Srgba>,
    /// The document pixel the gesture last sampled: a drag that stays on it samples nothing again.
    last_pixel: Option<(i64, i64)>,
}

/// The sampling ring's state: where it is and its two colours.
#[derive(Debug, Clone, Copy)]
struct Ring {
    /// The pointer, in screen points.
    at: egui::Pos2,
    /// The colour under the pointer now: the ring's upper half.
    new: Srgba,
    /// The colour the gesture replaces, as it was at the press: the lower half. Read from the
    /// swatch each pass, it turned into the new colour after the first pick, and both halves
    /// matched.
    before: Srgba,
}

/// The ring's outer radius in points (the framework ring's size).
const RING_OUTER_RADIUS: f32 = 105.0;
/// The width of each of the ring's two colour bands in points.
const RING_BAND: f32 = 17.0;
/// How many segments approximate a ring.
const RING_SEGMENTS: usize = 48;

/// The Eyedropper over PhotoCraft's sampling, options and colours. A pick applies only in the
/// `press` or `drag` call that took it, so a second pass in a frame, which gets no new pointer
/// input, picks nothing again.
pub(crate) struct PcEyedropper<'a> {
    scope: &'a ToolScope<'a>,
    state: &'a mut EyedropperState,
    inner: EyedropperTool<'a>,
    native: std::rc::Rc<std::cell::Cell<Option<[f32; 4]>>>,
    /// Runs as the Alt stand-in of a painting tool.
    stand_in: bool,
    /// Runs as a shape tool's Alt stand-in: a pick also sets the tool's Fill.
    shape_fill: bool,
    /// Show Sampling Ring (off with the Precise cursor preference). The ring is drawn here, from
    /// [`EyedropperState::ring`], not by the framework tool.
    show_ring: bool,
}

/// The Eyedropper tool, for `Tool::Eyedropper`.
pub(crate) fn tool<'a>(scope: &'a ToolScope<'a>, state: &'a mut EyedropperState, _host: CanvasHost) -> FamilyTool<'a> {
    Box::new(PcEyedropper::new(scope, state, false))
}

/// The Alt stand-in of the tools where `cursor_policy::alt_eyedropper` holds, registered as
/// `stand_in(StandInKey::Alt, ..)`.
pub(crate) fn stand_in_tool<'a>(scope: &'a ToolScope<'a>, state: &'a mut EyedropperState, _host: CanvasHost) -> FamilyTool<'a> {
    Box::new(PcEyedropper::new(scope, state, true))
}

/// Nothing to drain: `press`, `release` and `cancel` clear the gesture's flags themselves. Kept for
/// the family shape of `CanvasTools`.
pub(crate) fn drain(_app: &mut PhotocraftApp, _state: &mut EyedropperState, _response: &ToolHostResponse) {}

impl<'a> PcEyedropper<'a> {
    fn new(scope: &'a ToolScope<'a>, state: &'a mut EyedropperState, stand_in: bool) -> Self {
        let (mut options, foreground, precise, shape_fill) = scope.with_app(|app| {
            let [r, g, b, _] = app.session.tools.foreground;
            let precise = app.session.prefs().cursors.other == photocraft_engine::prefs::OtherCursor::Precise;
            (app.ui.tool_options.eyedropper, Srgba::rgb(r, g, b), precise, shape_alt_sets_fill(app.ui.tool))
        });
        // Preferences › Cursors › Other Cursors = Precise wants the plain crosshair, so no ring.
        options.show_ring &= !precise;
        let show_ring = options.show_ring;
        options.show_ring = false;
        let native = std::rc::Rc::new(std::cell::Cell::new(None));
        let sampled_native = native.clone();
        let sample = move |at: [f64; 2], size: SampleSize, source: SampleSource| {
            scope
                .with_app(|app| {
                    let picked = sampling::native_pick(app, at, size, source);
                    sampled_native.set(picked.map(|(_, inks)| inks));
                    picked.map(|(rgb, _)| rgb).or_else(|| sampling::pick(app, at, size, source))
                })
                .map(|c| Srgba::rgb(c[0], c[1], c[2]))
        };
        PcEyedropper {
            scope,
            state,
            inner: EyedropperTool::new(options, sample).foreground(foreground),
            native,
            stand_in,
            shape_fill: stand_in && shape_fill,
            show_ring,
        }
    }

    /// Writes the newest pick to its swatch; as a shape tool's stand-in, also makes the tool's Fill
    /// solid, so it follows the foreground (`vector_ui::shapes::tool_paint`).
    /// Returns the pick and the swatch colour it replaced, or `None` when this call picked nothing
    /// (off the image).
    fn apply(&mut self) -> Option<(Srgba, Srgba)> {
        let pick = self.inner.take()?;
        let key = if !self.stand_in && pick.background { "background" } else { "foreground" };
        let c = pick.color;
        let shape_fill = self.shape_fill;
        let inks = self.native.get();
        Some(self.scope.with_app(|app| {
            let [r, g, b, _] = if key == "background" { app.session.tools.background } else { app.session.tools.foreground };
            let replaced = Srgba::rgb(r, g, b);
            // A held eyedropper samples on every pass, mostly the colour the swatch already has (the
            // pointer still, or a pen trembling over one colour). Setting that same colour again ran
            // the command and refreshed every colour panel each frame, which made a long hold lag;
            // an unchanged pick now changes nothing.
            let role = usize::from(key == "background");
            let same_inks = inks.is_none_or(|inks| app.session.tools.picked_role_cmyk(role) == Some(inks));
            let fill_set = !shape_fill || (app.ui.tool_options.shape_fill && app.ui.tool_options.shape_fill_gradient.is_none());
            if [c.r, c.g, c.b] == [r, g, b] && same_inks && fill_set {
                return (c, replaced);
            }
            let mut params = json!({ key: [c.r, c.g, c.b, 1.0] });
            if let Some(inks) = inks {
                params[format!("{key}Cmyk")] = json!(inks);
            }
            if app.run("tools.setColors", params).is_ok() && shape_fill {
                app.ui.tool_options.shape_fill = true;
                app.ui.tool_options.shape_fill_gradient = None;
            }
            (c, replaced)
        }))
    }

    /// Keeps the sampling ring for the pick a press or drag at `pointer` made: the new colour over
    /// the one the gesture's first pick replaced. No pick (the pointer left the image) hides it.
    fn track_ring(&mut self, pointer: &ToolPointer, picked: Option<(Srgba, Srgba)>) {
        self.state.ring = picked.map(|(new, replaced)| Ring { at: pointer.pos, new, before: *self.state.before.get_or_insert(replaced) });
    }

    /// The painting tools' Shift+Alt stand-in adds a colour sampler.
    fn shift_adds_samplers(&self) -> bool {
        self.stand_in && !self.shape_fill
    }

    /// Shift+Alt: adds a colour sampler at the clicked pixel, as the Color Sampler tool places one.
    /// Returns whether the press did; a press on an existing point is not measured again and samples
    /// instead.
    fn add_sampler(&mut self, pointer: &ToolPointer, cx: &ToolContext<'_>) -> bool {
        let Some(space) = cx.space() else { return false };
        let p = space.view.to_doc(pointer.pos);
        let (x, y) = (p.x, p.y);
        self.scope.with_app(|app| {
            if on_sampler(app, x, y) {
                return false;
            }
            let size = app.session.active().map(|d| d.doc.size);
            let inside = size.is_some_and(|s| (0.0..f64::from(s.width)).contains(&x) && (0.0..f64::from(s.height)).contains(&y));
            // The Color Sampler tool places no point off the canvas and says nothing.
            if inside && let Err(e) = app.run("view.colorSamplers.add", json!({"x": x, "y": y})) {
                // Only the limit is a plain report; any other refusal (a failed Pen draft left in
                // another document) stays an error, also when the document is full.
                let limit = e == photocraft_engine::sampler_cmds::limit_message();
                app.ui.status = e;
                app.ui.status_error = !limit;
            }
            true
        })
    }
}

/// The document pixel under `pointer`, or `None` without a canvas space.
fn pixel_at(pointer: &ToolPointer, cx: &ToolContext<'_>) -> Option<(i64, i64)> {
    let p = cx.space()?.view.to_doc(pointer.pos);
    (p.x.is_finite() && p.y.is_finite()).then(|| (p.x.floor() as i64, p.y.floor() as i64))
}

/// The points of the arc of `radius` from angle `from` to `to` around `center`.
fn arc(center: egui::Pos2, radius: f32, from: f32, to: f32) -> Vec<egui::Pos2> {
    (0..=RING_SEGMENTS)
        .map(|i| {
            let angle = from + (to - from) * i as f32 / RING_SEGMENTS as f32;
            center + egui::vec2(angle.cos(), angle.sin()) * radius
        })
        .collect()
}

/// The sampling ring around `ring.at`: the new colour in the upper half, the colour it replaces in
/// the lower half, between a grey rule and two halo hairlines (the framework ring's look).
fn paint_ring(draw: &Draw<'_>, style: &StyleCx<'_>, ring: Ring) {
    use std::f32::consts::{PI, TAU};
    let inner = RING_OUTER_RADIUS - 2.0 * RING_BAND;
    let band = |(from, to): (f32, f32), color: Srgba| {
        let mut outline = arc(ring.at, inner, from, to);
        outline.extend(arc(ring.at, inner + RING_BAND, from, to).into_iter().rev());
        draw.data_fill(&PaintShape::Polygon(outline), DataColor::new(egui::Color32::from(color)));
    };
    band((PI, TAU), ring.new);
    band((0.0, PI), ring.before);
    let circle = |radius: f32| {
        let mut points = arc(ring.at, radius, 0.0, TAU);
        points.truncate(RING_SEGMENTS);
        if let Some(&first) = points.first() {
            points.push(first);
        }
        PaintShape::Path(points)
    };
    let tokens = style.tokens;
    draw.stroke(&circle(inner + RING_BAND * 1.5), StrokeWidth::Thick, style.color(tokens.color.overlay.grid));
    draw.stroke(&circle(RING_OUTER_RADIUS), StrokeWidth::Hairline, style.color(tokens.color.overlay.halo));
    draw.stroke(&circle(inner), StrokeWidth::Hairline, style.color(tokens.color.overlay.halo));
}

/// Whether document point (x, y) is on a colour sampler, within the Color Sampler tool's reach of one.
fn on_sampler(app: &PhotocraftApp, x: f64, y: f64) -> bool {
    let tol = app.tool_reach();
    app.session.active().is_some_and(|d| d.color_samplers.iter().any(|q| (q[0] - x).hypot(q[1] - y) <= tol))
}

impl CanvasTool for PcEyedropper<'_> {
    fn press(&mut self, pointer: &ToolPointer, cx: &mut ToolContext<'_>) -> ToolAction {
        self.state.sampler_added = false;
        self.state.ring = None;
        self.state.before = None;
        self.state.last_pixel = None;
        if self.shift_adds_samplers() && pointer.mods.shift && self.add_sampler(pointer, cx) {
            self.state.sampler_added = true;
            return ToolAction::Claimed;
        }
        let action = self.inner.press(pointer, cx);
        self.state.last_pixel = pixel_at(pointer, cx);
        let picked = self.apply();
        self.track_ring(pointer, picked);
        action
    }

    fn drag(&mut self, pointer: &ToolPointer, cx: &mut ToolContext<'_>) {
        // While Shift+Alt stay held after a press that added a sampler, moves sample nothing.
        if self.state.sampler_added || (self.shift_adds_samplers() && pointer.mods.shift) {
            return;
        }
        // A move that stays on the pixel last sampled reads the same colour: only the ring follows the
        // pointer. Each sample composites the layers under the point, which on a large document is
        // the cost a long hold kept paying on every pass.
        let pixel = pixel_at(pointer, cx);
        if pixel.is_some() && pixel == self.state.last_pixel {
            if let Some(ring) = self.state.ring.as_mut() {
                ring.at = pointer.pos;
            }
            return;
        }
        self.state.last_pixel = pixel;
        self.inner.drag(pointer, cx);
        let picked = self.apply();
        self.track_ring(pointer, picked);
    }

    fn release(&mut self, pointer: &ToolPointer, cx: &mut ToolContext<'_>) {
        self.state.sampler_added = false;
        self.state.ring = None;
        self.state.before = None;
        self.state.last_pixel = None;
        self.inner.release(pointer, cx);
    }

    fn cancel(&mut self, reason: CancelReason, cx: &mut ToolContext<'_>) {
        self.state.sampler_added = false;
        self.state.ring = None;
        self.state.before = None;
        self.state.last_pixel = None;
        self.inner.cancel(reason, cx);
    }

    /// The sampling ring while the button is held: the new colour over the one the gesture
    /// replaces, drawn on every pass from [`EyedropperState::ring`].
    fn paint(&self, draw: &Draw<'_>, cx: &ToolContext<'_>) {
        if let (true, Some(ring), Some(style)) = (self.show_ring, self.state.ring, cx.style()) {
            paint_ring(draw, style, ring);
        }
    }

    /// `EyedropperTool::cursor`: the pipette, the precise crosshair with Caps Lock or the preference.
    fn cursor(&self, cx: &ToolContext<'_>) -> Cursor {
        self.inner.cursor(cx)
    }

    fn takes(&self, button: PointerButton, mods: Mods) -> bool {
        // ⌘ is the Move stand-in's, here as with the painting tools.
        button == PointerButton::Primary && (self.stand_in || !mods.cmd)
    }

    fn autoscrolls(&self) -> bool {
        false
    }

    fn command_form(&self) -> ToolPath {
        self.inner.command_form()
    }
}

#[cfg(test)]
mod tests;

#[cfg(test)]
#[path = "../brush_shift_alt_sampler_tests.rs"]
mod brush_shift_alt_sampler_tests;
