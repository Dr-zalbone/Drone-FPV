class_name GameEnums
extends RefCounted

enum ViewMode { FPV, THIRD_PERSON, FLYER }
enum FlightMode { CINE, NORMAL, SPORT, MANUAL }
enum Quality { LOW, MEDIUM, HIGH }

const QUALITY_NAMES := {
	Quality.LOW: "Low (Quest 2)",
	Quality.MEDIUM: "Medium (Quest 3S)",
	Quality.HIGH: "High (PC VR)",
}

## Per-preset LOD / performance settings.
##   lod_threshold: Viewport.mesh_lod_threshold in pixels (higher = coarser LODs sooner)
##   view_distance: metres; map chunks beyond it are culled and hidden by fog
##   msaa: Viewport.MSAA_* ; render_scale: OpenXR render target multiplier
const QUALITY_SETTINGS := {
	Quality.LOW: {"lod_threshold": 6.0, "view_distance": 700.0, "msaa": 0, "render_scale": 0.8},
	Quality.MEDIUM: {"lod_threshold": 2.5, "view_distance": 1500.0, "msaa": 1, "render_scale": 1.0},
	Quality.HIGH: {"lod_threshold": 1.0, "view_distance": 4000.0, "msaa": 2, "render_scale": 1.0},
}

const VIEW_NAMES := {
	ViewMode.FPV: "FPV (goggles)",
	ViewMode.THIRD_PERSON: "3rd person",
	ViewMode.FLYER: "Flyer (pilot)",
}

const FLIGHT_NAMES := {
	FlightMode.CINE: "Cine",
	FlightMode.NORMAL: "Normal",
	FlightMode.SPORT: "Sport",
	FlightMode.MANUAL: "Manual (acro)",
}
