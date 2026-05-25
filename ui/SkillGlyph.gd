extends RefCounted
class_name SkillGlyph

# Procedural skill glyphs — shared by every UI surface that displays a skill
# (in-level CooldownButton, HeroesHub equip-picker tiles/slots, future skill
# tree nodes). Keyed by the `pictogram` string on SkillData.
#
# Dispatch via SkillGlyph.draw(ci, key, center, g, white, dark).
# g = glyph half-extent in pixels. Caller sizes it to whatever the host
# widget can spare (radius * 0.55 in CooldownButton, ~22-28px in tiles).


static func draw(ci: CanvasItem, glyph: String, center: Vector2, g: float, white: Color, dark: Color) -> void:
	match glyph:
		"warrior_summon":
			var pole_x: float = center.x - g * 0.55
			ci.draw_line(Vector2(pole_x, center.y - g * 0.90), Vector2(pole_x, center.y + g * 0.78), white, 3.0)
			var banner: PackedVector2Array = PackedVector2Array([
				Vector2(pole_x, center.y - g * 0.85),
				Vector2(center.x + g * 0.55, center.y - g * 0.68),
				Vector2(center.x + g * 0.32, center.y - g * 0.34),
				Vector2(pole_x, center.y - g * 0.44),
			])
			ci.draw_colored_polygon(banner, white)
			ci.draw_line(Vector2(pole_x + g * 0.18, center.y - g * 0.62), Vector2(center.x + g * 0.36, center.y - g * 0.52), dark, 2.0)
			for s in [-1.0, 1.0]:
				var helm_c: Vector2 = center + Vector2(s * g * 0.34, g * 0.26)
				ci.draw_circle(helm_c, g * 0.24, white)
				ci.draw_rect(Rect2(helm_c + Vector2(-g * 0.24, -g * 0.02), Vector2(g * 0.48, g * 0.26)), white)
				ci.draw_line(helm_c + Vector2(-g * 0.18, g * 0.08), helm_c + Vector2(g * 0.18, g * 0.08), dark, 2.0)
		"warrior_bless":
			for i in 8:
				var ang: float = TAU * float(i) / 8.0
				var dir: Vector2 = Vector2(cos(ang), sin(ang))
				ci.draw_line(center + dir * g * 0.56, center + dir * g * 0.98, white, 2.2)
			var shield: PackedVector2Array = PackedVector2Array([
				center + Vector2(-g * 0.44, -g * 0.46),
				center + Vector2(g * 0.44, -g * 0.46),
				center + Vector2(g * 0.38, g * 0.12),
				center + Vector2(0.0, g * 0.72),
				center + Vector2(-g * 0.38, g * 0.12),
			])
			ci.draw_colored_polygon(shield, white)
			ci.draw_line(center + Vector2(0.0, -g * 0.32), center + Vector2(0.0, g * 0.40), dark, 2.4)
			ci.draw_line(center + Vector2(-g * 0.24, -g * 0.02), center + Vector2(g * 0.24, -g * 0.02), dark, 2.4)
		"warrior_shield_bash":
			var bash_shield: PackedVector2Array = PackedVector2Array([
				center + Vector2(-g * 0.62, -g * 0.54),
				center + Vector2(g * 0.16, -g * 0.44),
				center + Vector2(g * 0.10, g * 0.20),
				center + Vector2(-g * 0.34, g * 0.72),
				center + Vector2(-g * 0.66, g * 0.16),
			])
			ci.draw_colored_polygon(bash_shield, white)
			ci.draw_line(center + Vector2(-g * 0.32, -g * 0.34), center + Vector2(-g * 0.30, g * 0.42), dark, 2.6)
			ci.draw_line(center + Vector2(-g * 0.55, -g * 0.02), center + Vector2(g * 0.02, g * 0.02), dark, 2.6)
			for i in 3:
				var y: float = -g * 0.36 + float(i) * g * 0.34
				var p0: Vector2 = center + Vector2(g * 0.34, y)
				var p1: Vector2 = center + Vector2(g * 0.94, y + g * 0.05)
				ci.draw_line(p0, p1, white, 3.4)
				ci.draw_line(p1, p1 + Vector2(-g * 0.18, -g * 0.12), white, 2.4)
				ci.draw_line(p1, p1 + Vector2(-g * 0.18, g * 0.12), white, 2.4)
		"warrior_rally":
			var bell: PackedVector2Array = PackedVector2Array([
				center + Vector2(-g * 0.82, -g * 0.30),
				center + Vector2(-g * 0.38, -g * 0.18),
				center + Vector2(g * 0.62, -g * 0.52),
				center + Vector2(g * 0.88, -g * 0.16),
				center + Vector2(g * 0.86, g * 0.38),
				center + Vector2(g * 0.58, g * 0.06),
				center + Vector2(-g * 0.36, g * 0.20),
				center + Vector2(-g * 0.82, g * 0.18),
			])
			ci.draw_colored_polygon(bell, white)
			ci.draw_line(center + Vector2(g * 0.82, -g * 0.12), center + Vector2(g * 0.80, g * 0.36), dark, 2.8)
			ci.draw_line(center + Vector2(-g * 0.20, -g * 0.12), center + Vector2(-g * 0.02, g * 0.16), dark, 2.2)
			ci.draw_line(center + Vector2(g * 0.16, -g * 0.22), center + Vector2(g * 0.34, g * 0.08), dark, 2.2)
			var pennant: PackedVector2Array = PackedVector2Array([
				center + Vector2(-g * 0.48, g * 0.30),
				center + Vector2(-g * 0.02, g * 0.38),
				center + Vector2(-g * 0.22, g * 0.78),
			])
			ci.draw_colored_polygon(pennant, white)
		"soldiers":
			for s in [-1.0, 1.0]:
				var fc: Vector2 = center + Vector2(s * g * 0.45, -g * 0.05)
				ci.draw_circle(fc + Vector2(0.0, -g * 0.35), g * 0.20, white)
				var body: PackedVector2Array = PackedVector2Array([
					fc + Vector2(-g * 0.28, -g * 0.10),
					fc + Vector2(g * 0.28, -g * 0.10),
					fc + Vector2(g * 0.18, g * 0.55),
					fc + Vector2(-g * 0.18, g * 0.55),
				])
				ci.draw_colored_polygon(body, white)
				ci.draw_line(fc + Vector2(0.0, -g * 0.10), fc + Vector2(0.0, g * 0.55), dark, 2.0)
		"sunburst":
			for i in 8:
				var ang: float = TAU * float(i) / 8.0
				var dir: Vector2 = Vector2(cos(ang), sin(ang))
				var perp: Vector2 = Vector2(-dir.y, dir.x)
				var ray: PackedVector2Array = PackedVector2Array([
					center + dir * g * 0.45 + perp * g * 0.10,
					center + dir * g * 0.45 - perp * g * 0.10,
					center + dir * g * 1.05,
				])
				ci.draw_colored_polygon(ray, white)
			ci.draw_circle(center, g * 0.42, white)
			ci.draw_arc(center, g * 0.42, 0.0, TAU, 18, dark, 2.0)
		"bubble_shield":
			ci.draw_circle(center, g * 0.85, white)
			ci.draw_arc(center, g * 0.85, 0.0, TAU, 24, dark, 2.5)
			ci.draw_arc(center, g * 0.62, PI * 1.05, PI * 1.45, 10, dark, 3.0)
		"fireball":
			ci.draw_circle(center + Vector2(0.0, g * 0.15), g * 0.50, white)
			for i in 4:
				var ang2: float = -PI * 0.5 + (i - 1.5) * 0.55
				var dir2: Vector2 = Vector2(cos(ang2), sin(ang2))
				var perp2: Vector2 = Vector2(-dir2.y, dir2.x)
				var tip: Vector2 = center + dir2 * g * 1.0
				var base_l: Vector2 = center + dir2 * g * 0.35 + perp2 * g * 0.20
				var base_r: Vector2 = center + dir2 * g * 0.35 - perp2 * g * 0.20
				ci.draw_colored_polygon(PackedVector2Array([base_l, base_r, tip]), white)
			ci.draw_circle(center + Vector2(0.0, g * 0.15), g * 0.25, dark)
		"volley":
			var origin: Vector2 = center + Vector2(-g * 0.65, g * 0.55)
			for i in 3:
				var ang3: float = -PI * 0.42 + i * 0.22
				var dir3: Vector2 = Vector2(cos(ang3), sin(ang3))
				var perp3: Vector2 = Vector2(-dir3.y, dir3.x)
				var tip3: Vector2 = origin + dir3 * g * 1.50
				ci.draw_line(origin, tip3, white, 3.0)
				ci.draw_line(tip3, tip3 - dir3 * g * 0.25 + perp3 * g * 0.18, white, 3.0)
				ci.draw_line(tip3, tip3 - dir3 * g * 0.25 - perp3 * g * 0.18, white, 3.0)
		"trap":
			for s in [-1.0, 1.0]:
				var arc_c: Vector2 = center + Vector2(0.0, s * g * 0.10)
				ci.draw_arc(arc_c, g * 0.75, PI * 0.10 if s > 0 else PI * 1.10, PI * 0.90 if s > 0 else PI * 1.90, 16, white, 3.5)
				for i in 5:
					var t: float = float(i) / 4.0
					var ang4: float = lerp(PI * 0.10, PI * 0.90, t) if s > 0 else lerp(PI * 1.10, PI * 1.90, t)
					var dir4: Vector2 = Vector2(cos(ang4), sin(ang4))
					var jaw: Vector2 = arc_c + dir4 * g * 0.75
					var inward: Vector2 = (center - jaw).normalized()
					var perp4: Vector2 = Vector2(-inward.y, inward.x)
					ci.draw_colored_polygon(PackedVector2Array([
						jaw + perp4 * g * 0.08,
						jaw - perp4 * g * 0.08,
						jaw + inward * g * 0.22,
					]), white)
		"shield_strike":
			var sh: PackedVector2Array = PackedVector2Array([
				center + Vector2(-g * 0.55, -g * 0.55),
				center + Vector2(g * 0.35, -g * 0.55),
				center + Vector2(g * 0.35, g * 0.05),
				center + Vector2(-g * 0.10, g * 0.75),
				center + Vector2(-g * 0.55, g * 0.05),
			])
			ci.draw_colored_polygon(sh, white)
			ci.draw_line(center + Vector2(-g * 0.10, -g * 0.40), center + Vector2(-g * 0.10, g * 0.40), dark, 3.0)
			ci.draw_line(center + Vector2(-g * 0.45, -g * 0.05), center + Vector2(g * 0.25, -g * 0.05), dark, 3.0)
			for i in 3:
				var yo: float = -g * 0.35 + i * g * 0.35
				ci.draw_line(center + Vector2(g * 0.55, yo), center + Vector2(g * 1.00, yo), white, 3.5)
		"horn":
			var horn: PackedVector2Array = PackedVector2Array([
				center + Vector2(-g * 0.80, -g * 0.10),
				center + Vector2(-g * 0.50, -g * 0.30),
				center + Vector2(g * 0.55, -g * 0.55),
				center + Vector2(g * 0.90, -g * 0.15),
				center + Vector2(g * 0.90, g * 0.45),
				center + Vector2(g * 0.55, g * 0.05),
				center + Vector2(-g * 0.45, g * 0.15),
				center + Vector2(-g * 0.80, g * 0.10),
			])
			ci.draw_colored_polygon(horn, white)
			ci.draw_line(center + Vector2(g * 0.90, -g * 0.15), center + Vector2(g * 0.90, g * 0.45), dark, 3.0)
		"snowflake":
			for i in 6:
				var ang5: float = (TAU / 6.0) * float(i)
				var dir5: Vector2 = Vector2(cos(ang5), sin(ang5))
				var tip5: Vector2 = center + dir5 * g * 0.85
				ci.draw_line(center, tip5, white, 3.5)
				var perp5: Vector2 = Vector2(-dir5.y, dir5.x)
				var fork_back: Vector2 = tip5 - dir5 * g * 0.25
				ci.draw_line(tip5, fork_back + perp5 * g * 0.18, white, 2.5)
				ci.draw_line(tip5, fork_back - perp5 * g * 0.18, white, 2.5)
			ci.draw_circle(center, g * 0.18, white)
		"meteor":
			var ball: Vector2 = center + Vector2(g * 0.35, -g * 0.10)
			ci.draw_circle(ball, g * 0.42, white)
			ci.draw_arc(ball, g * 0.42, 0.0, TAU, 18, dark, 2.0)
			var trail: PackedVector2Array = PackedVector2Array([
				ball + Vector2(-g * 0.30, -g * 0.18),
				ball + Vector2(-g * 0.30, g * 0.18),
				center + Vector2(-g * 0.90, g * 0.70),
			])
			ci.draw_colored_polygon(trail, white)
			ci.draw_line(ball, center + Vector2(-g * 0.65, g * 0.50), dark, 3.0)
		"crosshair":
			ci.draw_arc(center, g * 0.78, 0.0, TAU, 24, white, 3.5)
			ci.draw_line(center + Vector2(-g * 0.95, 0.0), center + Vector2(-g * 0.20, 0.0), white, 3.0)
			ci.draw_line(center + Vector2(g * 0.20, 0.0), center + Vector2(g * 0.95, 0.0), white, 3.0)
			ci.draw_line(center + Vector2(0.0, -g * 0.95), center + Vector2(0.0, -g * 0.20), white, 3.0)
			ci.draw_line(center + Vector2(0.0, g * 0.20), center + Vector2(0.0, g * 0.95), white, 3.0)
			ci.draw_circle(center, g * 0.12, white)
		"target":
			ci.draw_arc(center, g * 0.95, 0.0, TAU, 26, white, 3.0)
			ci.draw_arc(center, g * 0.62, 0.0, TAU, 22, white, 2.8)
			ci.draw_arc(center, g * 0.30, 0.0, TAU, 16, white, 2.5)
			ci.draw_circle(center, g * 0.10, white)
		"falcon":
			var body_c: Vector2 = center + Vector2(0.0, g * 0.05)
			var lw: PackedVector2Array = PackedVector2Array([
				body_c + Vector2(0.0, -g * 0.05),
				body_c + Vector2(-g * 0.55, -g * 0.55),
				body_c + Vector2(-g * 0.95, -g * 0.10),
				body_c + Vector2(-g * 0.50, 0.0),
				body_c + Vector2(-g * 0.10, g * 0.10),
			])
			ci.draw_colored_polygon(lw, white)
			var rw: PackedVector2Array = PackedVector2Array([
				body_c + Vector2(0.0, -g * 0.05),
				body_c + Vector2(g * 0.55, -g * 0.55),
				body_c + Vector2(g * 0.95, -g * 0.10),
				body_c + Vector2(g * 0.50, 0.0),
				body_c + Vector2(g * 0.10, g * 0.10),
			])
			ci.draw_colored_polygon(rw, white)
			ci.draw_colored_polygon(PackedVector2Array([
				body_c + Vector2(0.0, -g * 0.15),
				body_c + Vector2(g * 0.10, g * 0.10),
				body_c + Vector2(0.0, g * 0.55),
				body_c + Vector2(-g * 0.10, g * 0.10),
			]), white)
		_:
			ci.draw_circle(center, g * 0.55, white)
