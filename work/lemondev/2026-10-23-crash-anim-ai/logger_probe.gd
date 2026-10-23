extends SceneTree

class L extends Logger:
	var n := 0
	func _log_error(_f: String, _file: String, _line: int, _code: String, _r: String, _e: bool, _t: int,
			_bt: Array[ScriptBacktrace]) -> void:
		n += 1

func _bad() -> void:
	var d := {}
	var x = d.nope
	print(x)

func _init() -> void:
	var l := L.new()
	OS.add_logger(l)
	_bad()
	OS.remove_logger(l)
	print("errors seen: ", l.n)
	quit()
