extends Node
## Self-updater: checks GitHub Releases for a newer version, downloads this
## platform's zip, swaps it in place of the running app and relaunches.
##
## The running app is renamed aside (macOS and Windows both allow renaming a
## running executable) and the new one is moved into its place, so no helper
## script is needed. The old copy is deleted on the next launch.
## Where the app can't be replaced (a Gatekeeper-translocated or read-only
## copy, Linux, a source run) the player is sent to the release page instead.

signal status_changed

const REPO := "TinyBitAdventures/star-circuit"
const API_URL := "https://api.github.com/repos/%s/releases/latest" % REPO
const RELEASES_URL := "https://github.com/%s/releases/latest" % REPO
const ASSETS := {"macOS": "StarCircuit-macOS.zip", "Windows": "StarCircuit-Windows.zip"}

## idle, checking, current, available, downloading, installing, ready, error
var state := "idle"
var latest := ""
var notes := ""
var page_url := RELEASES_URL
var asset_url := ""
var asset_size := 0
var error := ""
var just_updated := "" # the version we came from, if the last launch updated

var _http: HTTPRequest
var work_dir := "user://update" # dev scenes use their own folder


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Game.is_dev_run():
		work_dir = "user://update_dev"
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 30.0
	add_child(_http)
	_cleanup_previous()
	if Sound.check_updates and _auto_check_allowed():
		check.call_deferred()


static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## "v0.4.0" / "0.4.0-beta" -> [0, 4, 0]
static func parse_version(v: String) -> Array:
	var s := v.strip_edges().trim_prefix("v").trim_prefix("V")
	s = s.split("-")[0].split("+")[0]
	var out := []
	for p in s.split("."):
		out.append(int(p) if p.is_valid_int() else 0)
	while out.size() < 3:
		out.append(0)
	return out


static func is_newer(a: String, b: String) -> bool:
	var x := parse_version(a)
	var y := parse_version(b)
	for i in 3:
		if x[i] != y[i]:
			return x[i] > y[i]
	return false


static func platform() -> String:
	if OS.has_feature("macos"):
		return "macOS"
	if OS.has_feature("windows"):
		return "Windows"
	return OS.get_name()


func _api_url() -> String:
	return OS.get_environment("STAR_CIRCUIT_UPDATE_URL") if OS.has_environment("STAR_CIRCUIT_UPDATE_URL") else API_URL


func _auto_check_allowed() -> bool:
	if OS.has_environment("STAR_CIRCUIT_UPDATE_URL"):
		return true
	return OS.has_feature("template") and not Game.is_dev_run()


func has_update() -> bool:
	return state in ["available", "downloading", "installing", "ready"] or (state == "error" and latest != "")


func busy() -> bool:
	return state in ["checking", "downloading", "installing"]


## The app bundle (macOS) or exe (Windows) that gets replaced.
func install_target() -> String:
	if OS.has_environment("STAR_CIRCUIT_UPDATE_TARGET"):
		return OS.get_environment("STAR_CIRCUIT_UPDATE_TARGET")
	var exe := OS.get_executable_path()
	if platform() == "macOS":
		# .../Star Circuit.app/Contents/MacOS/Star Circuit
		var app := exe.get_base_dir().get_base_dir().get_base_dir()
		return app if app.ends_with(".app") else ""
	return exe


## Empty when an in-place install can work, otherwise why not.
func install_blocker() -> String:
	if not ASSETS.has(platform()):
		return "Automatic updates aren't available on %s yet." % platform()
	if asset_url == "":
		return "This release has no %s download yet." % platform()
	if not OS.has_feature("template") and not OS.has_environment("STAR_CIRCUIT_UPDATE_TARGET"):
		return "You're running from source. Pull the latest code instead."
	var target := install_target()
	if target == "":
		return "Couldn't find the app to replace."
	if "/AppTranslocation/" in target:
		return "macOS is running the game from a temporary copy. Move Star Circuit to your Applications folder, open it from there and try again."
	var probe := target.get_base_dir().path_join(".star-circuit-write-test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return "The folder holding the game is read-only. Move it somewhere you can write to, like Applications or Documents."
	f.close()
	DirAccess.remove_absolute(probe)
	return ""


func check() -> void:
	if busy():
		return
	_set_state("checking")
	_http.download_file = ""
	var err := _http.request(_api_url(), ["Accept: application/vnd.github+json", "User-Agent: StarCircuit/%s" % current_version()])
	if err != OK:
		_fail("Couldn't reach GitHub.")
		return
	var res: Array = await _http.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_fail("Couldn't check for updates (%s)." % (("HTTP %d" % res[1]) if res[0] == HTTPRequest.RESULT_SUCCESS else "offline"))
		return
	var data = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or not data.has("tag_name"):
		_fail("The update server sent something unexpected.")
		return
	var tag := str(data.tag_name)
	if not is_newer(tag, current_version()):
		latest = ""
		_set_state("current")
		return
	latest = tag.trim_prefix("v")
	notes = str(data.get("body", ""))
	page_url = str(data.get("html_url", RELEASES_URL))
	asset_url = ""
	asset_size = 0
	var want: String = ASSETS.get(platform(), "")
	for a in data.get("assets", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("name", "")) == want:
			asset_url = str(a.get("browser_download_url", ""))
			asset_size = int(a.get("size", 0))
	_set_state("available")
	if OS.get_environment("STAR_CIRCUIT_UPDATE_AUTO") == "1": # end-to-end test hook
		install()


## Downloads and installs; on success relaunches the new version and quits.
## Callers save first (see "Save & Update").
func install() -> void:
	if busy() or latest == "":
		return
	var why := install_blocker()
	if why != "":
		_fail(why)
		return
	DirAccess.make_dir_recursive_absolute(work_dir)
	var zip := ProjectSettings.globalize_path(work_dir.path_join(ASSETS[platform()]))
	DirAccess.remove_absolute(zip)
	_set_state("downloading")
	_http.download_file = zip
	var err := _http.request(asset_url, ["User-Agent: StarCircuit/%s" % current_version()])
	if err != OK:
		_http.download_file = ""
		_fail("Couldn't start the download.")
		return
	var res: Array = await _http.request_completed
	_http.download_file = ""
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_fail("The download failed (%s). Try again in a moment." % (("HTTP %d" % res[1]) if res[0] == HTTPRequest.RESULT_SUCCESS else "connection lost"))
		return
	if asset_size > 0 and FileAccess.get_size(zip) != asset_size:
		_fail("The download came through incomplete. Try again.")
		return
	_set_state("installing")
	# let the UI draw "Installing" before the blocking unpack
	await get_tree().process_frame
	await get_tree().process_frame
	var launch := _install_macos(zip) if platform() == "macOS" else _install_windows(zip)
	DirAccess.remove_absolute(zip)
	if launch.is_empty():
		return # _fail already called
	var f := FileAccess.open(work_dir.path_join("updated_from.txt"), FileAccess.WRITE)
	if f:
		f.store_string(current_version())
		f.close()
	_set_state("ready")
	if OS.has_environment("STAR_CIRCUIT_UPDATE_NO_RELAUNCH"):
		return
	Game.save_game() # again, in case play went on while it downloaded (no-op outside a game)
	OS.create_process(launch[0], launch.slice(1))
	get_tree().quit()


## Download progress 0..1 (or -1 when the size is unknown).
func progress() -> float:
	if state != "downloading":
		return 1.0 if state in ["installing", "ready"] else 0.0
	var total := asset_size if asset_size > 0 else _http.get_body_size()
	return clampf(float(_http.get_downloaded_bytes()) / total, 0.0, 1.0) if total > 0 else -1.0


func downloaded_mb() -> float:
	return _http.get_downloaded_bytes() / 1048576.0


func open_release_page() -> void:
	OS.shell_open(page_url)


# Install
# --------------------------------------------------------------------------

func _install_macos(zip: String) -> Array:
	var app := install_target()
	var parent := app.get_base_dir()
	# unpack beside the app so the swap is a rename on one volume
	var stage := parent.path_join(".star-circuit-update")
	OS.execute("/bin/rm", ["-rf", stage])
	var out := []
	if OS.execute("/usr/bin/ditto", ["-x", "-k", zip, stage], out, true) != 0:
		OS.execute("/bin/rm", ["-rf", stage])
		_fail("Couldn't unpack the update.")
		return []
	var new_app := ""
	for d in DirAccess.get_directories_at(stage):
		if d.ends_with(".app"):
			new_app = stage.path_join(d)
			break
	if new_app == "" or not FileAccess.file_exists(new_app.path_join("Contents/Info.plist")):
		OS.execute("/bin/rm", ["-rf", stage])
		_fail("The update didn't contain the game.")
		return []
	OS.execute("/usr/bin/xattr", ["-cr", new_app])
	var old := parent.path_join(".%s.old.app" % app.get_file().get_basename())
	OS.execute("/bin/rm", ["-rf", old])
	if DirAccess.rename_absolute(app, old) != OK:
		OS.execute("/bin/rm", ["-rf", stage])
		_fail("Couldn't move the old version aside.")
		return []
	if DirAccess.rename_absolute(new_app, app) != OK:
		DirAccess.rename_absolute(old, app)
		OS.execute("/bin/rm", ["-rf", stage])
		_fail("Couldn't put the new version in place.")
		return []
	OS.execute("/bin/rm", ["-rf", stage])
	_remember_old(old)
	return ["/usr/bin/open", "-n", app]


func _install_windows(zip: String) -> Array:
	var exe := install_target()
	var reader := ZIPReader.new()
	if reader.open(zip) != OK:
		_fail("Couldn't open the update.")
		return []
	var entry := ""
	for n in reader.get_files():
		if n.get_file().to_lower().ends_with(".exe"):
			entry = n
			break
	if entry == "":
		reader.close()
		_fail("The update didn't contain the game.")
		return []
	var bytes := reader.read_file(entry)
	reader.close()
	var fresh := exe.get_base_dir().path_join("StarCircuit.new.exe")
	var f := FileAccess.open(fresh, FileAccess.WRITE)
	if f == null:
		_fail("Couldn't write the new version.")
		return []
	f.store_buffer(bytes)
	f.close()
	if FileAccess.get_size(fresh) != bytes.size():
		DirAccess.remove_absolute(fresh)
		_fail("Couldn't write the new version (disk full?).")
		return []
	var old := exe.get_basename() + ".old.exe"
	DirAccess.remove_absolute(old)
	if DirAccess.rename_absolute(exe, old) != OK:
		DirAccess.remove_absolute(fresh)
		_fail("Couldn't move the old version aside.")
		return []
	if DirAccess.rename_absolute(fresh, exe) != OK:
		DirAccess.rename_absolute(old, exe)
		_fail("Couldn't put the new version in place.")
		return []
	_remember_old(old)
	return [exe]


func _remember_old(path: String) -> void:
	var f := FileAccess.open(work_dir.path_join("old_path.txt"), FileAccess.WRITE)
	if f:
		f.store_string(path)
		f.close()


## Runs on every launch: delete the version we replaced and note what we came from.
func _cleanup_previous() -> void:
	var from_path := work_dir.path_join("updated_from.txt")
	if FileAccess.file_exists(from_path):
		just_updated = FileAccess.get_file_as_string(from_path).strip_edges()
		DirAccess.remove_absolute(from_path)
		if not is_newer(current_version(), just_updated):
			just_updated = "" # somehow still the old version: don't claim success
	var old_path := work_dir.path_join("old_path.txt")
	if not FileAccess.file_exists(old_path) or just_updated == "":
		return
	var old := FileAccess.get_file_as_string(old_path).strip_edges()
	DirAccess.remove_absolute(old_path)
	if old == "" or not (".old" in old.get_file()):
		return
	if DirAccess.dir_exists_absolute(old):
		OS.execute("/bin/rm", ["-rf", old])
	else:
		DirAccess.remove_absolute(old)


func _set_state(s: String) -> void:
	state = s
	if s != "error":
		error = ""
	status_changed.emit()


func _fail(msg: String) -> void:
	error = msg
	_set_state("error")
