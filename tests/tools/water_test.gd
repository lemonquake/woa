extends SceneTree
func _init() -> void:
	var sh := load("res://src/game/water.gdshader") as Shader
	var m := ShaderMaterial.new()
	m.shader = sh
	print("shader code len ", sh.code.length())
	print(RenderingServer.shader_get_parameter_list(sh.get_rid()).size())
	quit()
