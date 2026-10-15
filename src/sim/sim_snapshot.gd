class_name SimSnapshot
extends RefCounted
## The whole match as bytes, and back: for a multiplayer player who joins late, comes back after a dropped
## connection, or whose game drifted from the host's (a desync). Every simulation object reachable from the world is
## written with its script fields; objects and dictionaries keep their identity (a dictionary two objects share is
## still one dictionary after loading). The map's fixed parts are rebuilt from its seed on the receiving machine; only
## what changes during a match (trees, walkable cells, sight blockers) travels. Caches (sight stamps, ray templates)
## are left out and rebuilt.

const FORMAT := 1
const MARK := "__snapshot_id"
## Fields that are caches or tool switches, rebuilt or reset after loading.
const TRANSIENT := {"_stamps": true, "_stamp_rev": true, "_team_img": true, "_static_img": true, "_static": true,
	"_templates": true, "prof": true, "profiling": true, "_power_cache": true, "_power_tick": true, "_bld": true,
	"_nb_cache": true, "_nb_tick": true, "_val_cache": true}

## The world at this tick boundary (call between steps, after its events were read), compressed.
static func capture(w: SimWorld) -> PackedByteArray:
	var wr := _Writer.new()
	var root = wr.enc(w)
	var m := w.map
	var out := {"format": FORMAT, "root": root, "objs": wr.objs, "dicts": wr.dicts,
		"map": {"seed": m.seed_value, "trees": m.trees.duplicate(true), "walkable": m.walkable, "tree_cell": m.tree_cell,
			"vision_block": m.vision_block, "vision_rev": m.vision_rev}}
	wr.cleanup()
	var raw := var_to_bytes(out)
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var head := PackedByteArray()
	head.resize(4)
	head.encode_u32(0, raw.size())
	return head + packed

## A new world from capture() bytes, on `map` (built from the same seed; its changing parts are overwritten).
## Returns null if the bytes are not a snapshot of this format.
static func restore(bytes: PackedByteArray, map: SimMap) -> SimWorld:
	if bytes.size() < 8:
		return null
	var size := bytes.decode_u32(0)
	if size <= 0 or size > 256 * 1024 * 1024:
		return null
	var raw := bytes.slice(4).decompress(size, FileAccess.COMPRESSION_ZSTD)
	var data = bytes_to_var(raw)
	if not (data is Dictionary) or int(data.get("format", 0)) != FORMAT:
		return null
	if int(data.map.seed) != map.seed_value:
		return null
	_restore_map(map, data.map)
	var rd := _Reader.new()
	rd.objs_in = data.objs
	rd.dicts_in = data.dicts
	rd.map = map
	var w = rd.dec(data.root)
	if not (w is SimWorld):
		return null
	w.map = map
	w.events = []
	w.vision.static_dirty = true
	w.vision._stamp_rev = -1
	# the hero's view of its courier's bags is the courier's own array
	for h in w.heroes:
		var c: SimUnit = w.get_unit(h.courier_id)
		if c != null:
			h.courier_items = c.inventory
	return w

static func _restore_map(m: SimMap, d: Dictionary) -> void:
	m.trees = d.trees
	m.tree_cell = d.tree_cell
	m.vision_block = d.vision_block
	m.vision_rev = int(d.vision_rev) + 1
	m.vision_changes.clear()                 # no list of changes: SimVision drops its whole sight cache
	var walk: PackedByteArray = d.walkable
	var n := SimMap.N
	for y in n:
		for x in n:
			var i := y * n + x
			if walk[i] != m.walkable[i]:
				m.astar.set_point_solid(Vector2i(x, y), walk[i] == 0)
	m.walkable = walk

class _Writer:
	var objs: Array = []                   # [script path, {field: encoded value}]
	var dicts: Array = []                  # [keys, values] per shared dictionary
	var _oid := {}                         # object instance id -> index in objs
	var _marked: Array = []                # dictionaries carrying MARK while writing

	func enc(v):
		match typeof(v):
			TYPE_OBJECT:
				if v == null:
					return null
				if v is SimMap:
					return {"@map": 0}
				if v is RandomNumberGenerator:
					return {"@rng": [v.seed, v.state]}
				if not (v is RefCounted) or v.get_script() == null:
					return null                  # images and other caches: rebuilt after loading
				var iid: int = v.get_instance_id()
				if _oid.has(iid):
					return {"@o": _oid[iid]}
				var idx := objs.size()
				_oid[iid] = idx
				objs.append(null)
				var fields := {}
				for p in v.get_property_list():
					if not (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
						continue
					var n := String(p.name)
					if TRANSIENT.has(n):
						continue
					fields[n] = enc(v.get(n))
				objs[idx] = [(v.get_script() as Script).resource_path, fields]
				return {"@o": idx}
			TYPE_DICTIONARY:
				var d: Dictionary = v
				if d.has(MARK):
					return {"@d": d[MARK]}
				var sid := dicts.size()
				dicts.append(null)
				# marked before its contents are written, so a dictionary reached again inside itself is a reference
				if not d.is_read_only():
					d[MARK] = sid
					_marked.append(d)
				var keys := []
				var vals := []
				for k in d:
					if k is String and k == MARK:
						continue
					keys.append(enc(k))
					vals.append(enc(d[k]))
				dicts[sid] = [keys, vals]
				return {"@d": sid}
			TYPE_ARRAY:
				var a: Array = v
				var out := []
				out.resize(a.size())
				for i in a.size():
					out[i] = enc(a[i])
				var spath := ""
				var sc = a.get_typed_script()
				if sc is Script:
					spath = (sc as Script).resource_path
				return {"@a": out, "tb": a.get_typed_builtin(), "tc": String(a.get_typed_class_name()), "ts": spath}
		return v

	func cleanup() -> void:
		for d in _marked:
			d.erase(MARK)
		_marked.clear()

class _Reader:
	var objs_in: Array
	var dicts_in: Array
	var map: SimMap
	var _objs := {}
	var _dicts := {}

	func dec(v):
		if not (v is Dictionary):
			return v
		var d: Dictionary = v
		if d.has("@o"):
			return _obj(int(d["@o"]))
		if d.has("@d"):
			return _dict(int(d["@d"]))
		if d.has("@a"):
			var src: Array = d["@a"]
			var plain := []
			plain.resize(src.size())
			for i in src.size():
				plain[i] = dec(src[i])
			var tb := int(d.get("tb", TYPE_NIL))
			if tb == TYPE_NIL:
				return plain
			var sc = null
			if String(d.get("ts", "")) != "":
				sc = load(String(d.ts))
			return Array(plain, tb, StringName(String(d.get("tc", ""))), sc)
		if d.has("@rng"):
			var r := RandomNumberGenerator.new()
			r.seed = int(d["@rng"][0])
			r.state = int(d["@rng"][1])
			return r
		if d.has("@map"):
			return map
		return null

	func _obj(i: int) -> Object:
		if _objs.has(i):
			return _objs[i]
		var e: Array = objs_in[i]
		var path := String(e[0])
		if not path.begins_with("res://src/sim/"):
			return null                          # only simulation classes are ever made from a snapshot
		var o: Object
		if path.ends_with("/sim_world.gd"):
			o = SimWorld.new(1, map)
		else:
			o = (load(path) as GDScript).new()
		_objs[i] = o
		var fields: Dictionary = e[1]
		for k in fields:
			o.set(k, dec(fields[k]))
		return o

	func _dict(i: int) -> Dictionary:
		if _dicts.has(i):
			return _dicts[i]
		var out := {}
		_dicts[i] = out
		var e: Array = dicts_in[i]
		var keys: Array = e[0]
		var vals: Array = e[1]
		for j in keys.size():
			out[dec(keys[j])] = dec(vals[j])
		return out
