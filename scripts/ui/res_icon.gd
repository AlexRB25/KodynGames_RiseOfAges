class_name ResIcon
extends Control
## Iconos dibujados para la barra de recursos (provisionales hasta tener arte).

var kind := ""


func _init(k: String = "") -> void:
	kind = k
	custom_minimum_size = Vector2(34, 30)


func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.22, 0.17, 0.12), true)
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.6, 0.47, 0.25), false, 1.5)
	var c := s * 0.5
	match kind:
		"comida":   # pieza de carne
			draw_circle(c + Vector2(-2, 0), 9, Color(0.75, 0.2, 0.18))
			draw_circle(c + Vector2(-3, -1), 5, Color(0.92, 0.55, 0.5))
			draw_line(c + Vector2(5, 3), c + Vector2(12, 8), Color(0.95, 0.92, 0.85), 4)
		"madera":   # troncos
			for i in 3:
				var p := c + Vector2(-9 + i * 9, 4 - (i % 2) * 7)
				draw_circle(p, 5, Color(0.55, 0.36, 0.18))
				draw_circle(p, 3, Color(0.82, 0.65, 0.4))
		"oro":      # pepitas
			draw_circle(c + Vector2(-5, 3), 6, Color(0.95, 0.78, 0.2))
			draw_circle(c + Vector2(5, 4), 5, Color(0.85, 0.65, 0.12))
			draw_circle(c + Vector2(0, -4), 5, Color(1.0, 0.88, 0.35))
		"piedra":   # rocas
			draw_colored_polygon(PackedVector2Array([c + Vector2(-11, 8), c + Vector2(-6, -6), c + Vector2(3, -8), c + Vector2(10, 0), c + Vector2(8, 8)]), Color(0.65, 0.65, 0.68))
			draw_line(c + Vector2(-4, -2), c + Vector2(4, 4), Color(0.45, 0.45, 0.5), 1.5)
		"era":      # pirámide
			for i in 4:
				var w := 22.0 - i * 5.0
				draw_rect(Rect2(c + Vector2(-w * 0.5, 8 - i * 5), Vector2(w, 5)), Color(0.95, 0.78, 0.25).darkened(i * 0.06))
		"pop":      # aldeano
			draw_circle(c + Vector2(0, -7), 5, Color(0.65, 0.45, 0.3))
			draw_rect(Rect2(c + Vector2(-6, -2), Vector2(12, 12)), Color(0.9, 0.87, 0.78))
