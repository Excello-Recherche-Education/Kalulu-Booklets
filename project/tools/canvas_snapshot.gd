extends SceneTree
## Draws a sample page with CanvasSurface, the preview's surface, and saves it
## as a PNG, to compare by eye with the same page in a PDF. Needs a window:
## --headless renders nothing.
##
##     godot --path project --script res://tools/canvas_snapshot.gd -- <out.png>

const A5 := Vector2(419.527559, 595.275591)
const SCALE := 2.0


func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(A5 * SCALE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.transparent_bg = false
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color.WHITE
	background.size = A5 * SCALE
	viewport.add_child(background)
	var page := Node2D.new()
	viewport.add_child(page)

	var folder := FontSet.pinned_folder()
	var script := FontFace.new(FileAccess.get_file_as_bytes(folder.path_join(FontSet.SCRIPT)), FontSet.SCRIPT)
	var cursive := FontFace.new(FileAccess.get_file_as_bytes(folder.path_join(FontSet.CURSIVE)), FontSet.CURSIVE)
	var art_folder := BookletArt.FOLDER
	var surface := CanvasSurface.new(A5, page.get_canvas_item(), SCALE)
	surface.save()
	surface.fill_color(Color(0.5, 0.2, 0.1))
	surface.stroke_color(Color(0.1, 0.2, 0.3))
	surface.line_width(0.8)
	surface.fill_alpha(0.4)
	surface.path([["m", 10.0, 10.0], ["l", 100.0, 10.0], ["c", 120.0, 10.0, 120.0, 40.0, 100.0, 40.0], ["h"]],
			true, true, false)
	surface.path([["re", 20.0, 60.0, 50.0, 30.0]], false, true, true)
	surface.restore()
	var picture := Image.create(4, 3, false, Image.FORMAT_RGBA8)
	picture.fill(Color(0.2, 0.4, 0.6, 0.5))
	surface.image("picture", picture, 200.0, 300.0, 40.0, 30.0)
	script.draw(surface, 50.0, 500.0, "la Lune", 16.0, Color.BLACK)
	cursive.draw(surface, 50.0, 450.0, "toujours", 14.6, Color(0.2, 0.2, 0.6), [1], Color(0.6, 0.6, 0.6),
			{}, null, [Color(0.3, 0.3, 0.3), 0.5])
	VectorArt.read(art_folder.path_join("kalulu-logo.svg")).draw(surface, 250.0, 580.0, 150.0)
	VectorArt.read(art_folder.path_join("cover-star.svg")).draw(surface, 250.0, 200.0, 100.0)

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
