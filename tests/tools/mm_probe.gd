extends SceneTree
## Matchmaking with your accept: how many offers fail and why, on the ladder in WOA_RANKED_FILE.
##   WOA_RANKED_FILE=<copy of ranked.json> godot --headless --path . -s tests/tools/mm_probe.gd -- --offers=200

func _init() -> void:
	var offers := 200
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--offers="):
			offers = int(a.substr(9))
	Ranked.load_data()
	var mm := Matchmaker.new()
	mm.start([1, 2, 3, 4, 5])
	var made := 0
	var ok := 0
	var failed := 0
	var why := {}
	var secs := 0.0
	var ok_secs: Array = []
	var since := 0.0
	var run := 0
	var worst_run := 0
	var worst_wait := 0.0
	while made < offers and secs < 36000.0:
		var was := mm.state
		mm.step(0.1)
		secs += 0.1
		since += 0.1
		if mm.state == "found" and was == "searching":
			made += 1
			mm.accept()
			for id in mm.lineup.fails:
				var p := Ranked.profile(String(id))
				var k := "behavior %d" % (int(p.get("behavior", -1)) / 1000 * 1000)
				why[k] = int(why.get(k, 0)) + 1
		elif mm.state == "ready":
			ok += 1
			ok_secs.append(since)
			worst_wait = maxf(worst_wait, since)
			since = 0.0
			run = 0
			mm.start([1, 2, 3, 4, 5])
		elif was == "found" and mm.state == "searching":
			failed += 1
			run += 1
			worst_run = maxi(worst_run, run)
		elif mm.state == "failed":
			print("you did not accept?")
			mm.cancel()
			mm.start([1, 2, 3, 4, 5])
	print("offers %d, everyone accepted %d, a player failed %d (%.0f%%), %.0f s simulated" % [made, ok, failed,
		100.0 * failed / maxf(1.0, made), secs])
	print("failers by behaviour: %s" % str(why))
	var avg := 0.0
	for s in ok_secs:
		avg += float(s)
	print("average wait to a full accept: %.1f s, longest %.1f s; most failed accepts in one queue: %d" % [
		avg / maxf(1.0, ok_secs.size()), worst_wait, worst_run])
	quit()
