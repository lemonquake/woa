class_name BenchProbe
extends Node
## Benchmark helper (--bench only): two of these run first and last in every _process and _physics_process, so the
## span between them is the whole script time of the frame (every node's _process) and of each simulation tick.

static var proc_start := 0
static var phys_start := 0
static var proc_us := 0                  # this frame's script time in _process
static var phys_us := 0                  # this frame's script time in _physics_process (0 when no tick ran)
static var ticks := 0                    # simulation ticks in this frame
static var proc_end := 0                 # when the last _process of the frame finished
static var pre_draw := 0                 # RenderingServer.frame_pre_draw / frame_post_draw times
static var post_draw := 0
static var frame_start := 0              # the first _physics_process or _process of the frame
static var flush_us := 0                 # proc_end -> pre_draw: deferred calls, skeletons, transforms
static var draw_us := 0                  # pre_draw -> post_draw: the renderer on the main thread
static var gap_us := 0                   # post_draw -> next frame's start: input, physics server, waiting

var first := false

func _ready() -> void:
	if first:
		RenderingServer.frame_pre_draw.connect(_on_pre_draw)
		RenderingServer.frame_post_draw.connect(_on_post_draw)

## The rendering server outlives this node: let go of its signals when leaving (a lambda left connected crashed the
## game on quit after every benchmark).
func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)
	if RenderingServer.frame_post_draw.is_connected(_on_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_post_draw)

static func _on_pre_draw() -> void:
	pre_draw = Time.get_ticks_usec()

static func _on_post_draw() -> void:
	post_draw = Time.get_ticks_usec()
	flush_us = pre_draw - proc_end
	draw_us = post_draw - pre_draw

func _mark_start() -> void:
	var now := Time.get_ticks_usec()
	if post_draw > frame_start:
		gap_us = now - post_draw
		frame_start = now

func _process(_dt: float) -> void:
	if first:
		_mark_start()
		proc_start = Time.get_ticks_usec()
	else:
		proc_end = Time.get_ticks_usec()
		proc_us = proc_end - proc_start

func _physics_process(_dt: float) -> void:
	if first:
		_mark_start()
		phys_start = Time.get_ticks_usec()
	else:
		phys_us += Time.get_ticks_usec() - phys_start
		ticks += 1

## Read and reset the physics part (called once per rendered frame).
static func take_phys() -> Vector2i:
	var r := Vector2i(phys_us, ticks)
	phys_us = 0
	ticks = 0
	return r
