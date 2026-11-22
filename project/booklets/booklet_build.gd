class_name BookletBuild
extends RefCounted
## The booklets of one pack, written as PDF files: what ``build`` does on the
## command line (cli/build_command.gd), and what the Prof Tool's "Build
## booklets…" will do.
##
## Each version goes to a folder of its own, ``<out>/<locale>/<version>/``, the
## printing copies (A4, imposed) beside the A5 ones. What cannot be printed as
## the pack asks (a chapter with nothing to print, sentences that do not fit
## their pages, a sentence its lesson cannot read yet, a letter a font has no
## glyph for) is listed after the files; it never stops the build. A font the
## pack names that is not in fonts/ does.
##
## What it says goes through ``say`` (what a terminal prints to stdout) and
## ``complain`` (stderr), one line at a time, as it is written.

## Called with each line of the report.
var say: Callable
## Called with each line of an error.
var complain: Callable


func _init(on_line: Callable = Callable(), on_error: Callable = Callable()) -> void:
	say = on_line if on_line.is_valid() else func(line: String) -> void: print(line)
	complain = on_error if on_error.is_valid() else func(line: String) -> void: printerr(line)


## Writes the booklets of the pack in ``pack_folder`` (its folder or its
## language.db): those of ``numbers`` (every booklet when empty), in the
## versions of ``versions`` the language prints (all of them when empty),
## into ``out``. ``shown_out`` is how ``out`` is named in the report (as the
## user typed it), ``out`` itself when empty. Returns the exit code: 0 done, 1
## nothing to build, 2 refused.
func build(pack_folder: String, numbers: Array[int] = [], versions: Array[String] = [], out: String = "",
		shown_out: String = "") -> int:
	if shown_out.is_empty():
		shown_out = out
	var reader := BookletPackReader.new()
	var pack := reader.read(pack_folder)
	if pack == null:
		complain.call("error: " + reader.error)
		return 2
	var replaced := {}
	var names := {}
	for role: String in pack.fonts:
		replaced[role] = pack.fonts[role].file
		names[role] = pack.fonts[role].name
	var found := FontSet.find(pack.folder, replaced)
	if not found["error"].is_empty():
		complain.call("error: " + found["error"])
		return 2
	var faces := FontSet.from_folder(found["folder"], replaced)

	var available := pack.booklets()
	if numbers.is_empty():
		numbers = available
	if numbers.is_empty():
		complain.call("%s: no lesson, so no booklet chapter" % pack.folder.path_join("language.db"))
		return 1
	if not pack.made_chapters_for.is_empty() and not pack.chapters.any(
			func(chapter: BookletPack.Chapter) -> bool: return chapter.id > 0):
		say.call("%s has no booklet chapter: one per lesson, from its GPs, all in booklet 1" % pack.locale)
	elif not pack.made_chapters_for.is_empty():
		say.call("%s: lesson(s) %s have no chapter: each gets one from its GPs"
				% [pack.locale, ", ".join(pack.made_chapters_for.map(func(lesson: int) -> String: return str(lesson)))])
	var missing := numbers.filter(func(number: int) -> bool: return not available.has(number))
	if not missing.is_empty():
		complain.call("error: %s has no booklet %s; it has %s" % [pack.locale, _joined(missing),
				_joined(available) if not available.is_empty() else "none"])
		return 2

	var asked: Array[String] = []
	for name in (versions if not versions.is_empty() else pack.versions()):
		if not asked.has(name):
			asked.append(name)
	var printed := pack.versions()
	var left_out := asked.filter(func(name: String) -> bool: return not printed.has(name))
	if not left_out.is_empty():
		say.call("%s prints no %s version (its BookletSettings): left out" % [pack.locale, ", ".join(left_out)])
	var chosen_versions: Array[BookletVersion] = []
	for name in asked:
		if printed.has(name):
			chosen_versions.append(BookletVersion.named(name))
	if chosen_versions.is_empty():
		complain.call("error: %s prints none of the versions asked" % pack.locale)
		return 2
	# A language printing both series names them in its files.
	var series_names := pack.series()
	if chosen_versions.any(func(version: BookletVersion) -> bool: return version.teacher) and not pack.chapters.any(
			func(chapter: BookletPack.Chapter) -> bool: return not pack.chapter_picture(chapter).is_empty()):
		say.call("%s: no Look & Learn or booklet image found (not checked out?): the teacher version has no teacher page"
				% pack.locale)

	var notes: Array[String] = []
	for number in numbers:
		# The content is the same in every version; only the layout differs. A
		# note from one version's layout is said once, with the versions that
		# gave it when not all of them did.
		var said := {}
		var runs := 0
		for series in series_names:
			var named := series if series_names.size() > 1 else ""
			for version in chosen_versions:
				var booklet := BookletContent.booklet(pack, number, series)
				var folder := out.path_join(pack.locale).path_join(version.name)
				var shown := shown_out.path_join(pack.locale).path_join(version.name)
				var file := version.file_name(pack.locale, number, false, named)
				var imposed := version.file_name(pack.locale, number, true, named) if version.printed else ""
				var pages := BookletWriter.write(booklet, faces, folder.path_join(file), version,
						folder.path_join(imposed) if not imposed.is_empty() else "")
				if pages < 0:
					complain.call("error: cannot write %s" % folder.path_join(file))
					return 2
				say.call("%s  (%d pages, %d chapter(s))" % [shown.path_join(file), pages, booklet.chapters.size()])
				if not imposed.is_empty():
					@warning_ignore("integer_division")
					var sides := pages / 2
					say.call("%s  (%d A4 sheet sides, for printing)" % [shown.path_join(imposed), sides])
				runs += 1
				var seen := {}
				for note in booklet.notes:
					if seen.has(note):
						continue
					seen[note] = true
					if not said.has(note):
						said[note] = []
					said[note].append("%s %s" % [version.name, series] if not named.is_empty() else version.name)
		for note: String in said:
			var by: Array = said[note]
			var which := "" if by.size() == runs else " [%s]" % ", ".join(by)
			notes.append("booklet %d, %s%s" % [number, note, which])
	notes.append_array(faces.missing_notes(names))
	if not notes.is_empty():
		say.call("\nTo look at:")
		for note in notes:
			say.call("  - " + note)
	return 0


static func _joined(numbers: Array) -> String:
	return ", ".join(numbers.map(func(number: int) -> String: return str(number)))
