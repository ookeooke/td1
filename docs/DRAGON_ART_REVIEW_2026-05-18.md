# Dragon Hero — 5-Lens Art Review (2026-05-18)

Multi-perspective art critique of the Dragon hero (power-tier-3 IAP, MVP shipped
2026-05-17). The dragon is **100% procedural** — no bitmap assets. Five
`art-director` review passes ran in parallel: Silhouette, Palette, Animation,
VFX/Attack, Mobile/HUD. Findings are de-duplicated, severity-ordered, grouped by
file. Cited current values were spot-checked against source and are accurate.

**Scope:** review + implement-ready specs only. No code/`.tres` edited this
session. Heroes stay procedural-first (CORE RULE 21) — no bitmap pass proposed.

---

## Severity summary

| # | Sev | Finding | Lens | File |
|---|---|---|---|---|
| 1 | **P1** | Wings draw UNDER body — dragon's defining feature is overpainted | Silhouette | `UnitVisualDrawer.gd:672-692` |
| 2 | **P1** | Wing polygon self-intersects → bowtie fill, not membrane | Silhouette | `UnitVisualDrawer.gd:726-734` |
| 3 | **P1** | Projectile renders as `ARCANE_BOLT` (purple crystal shard), not fire | VFX | `DragonBreath.tscn:11`, `Arrow.gd:9,644` |
| 4 | **P1** | No mouth charge glow on the basic breath attack (only on skills) | VFX | `base_hero.gd:819-825,1196-1231` |
| 5 | P2 | Membrane color ≈ body color → near-zero wing/body separation | Silhouette+Palette | `UnitVisualDrawer.gd:668` |
| 6 | P2 | HUD disk color independently authored, mismatches body | Palette | `HeroHudPortrait.gd:229` |
| 7 | P2 | HUD glyph reads as butterfly/bird, not a dragon | Mobile | `HeroHudPortrait.gd:267-281` |
| 8 | P2 | No flight-bob; body static while wings flap → robotic | Animation | `base_hero.gd:1564`, `UnitVisualDrawer.gd` |
| 9 | P2 | Wing & tail share one phase clock (2:1 lock) → metronomic | Animation | `UnitVisualDrawer.gd:657-659` |
| 10 | P2 | Cast wind-up telegraph too short/subtle (0.15s, ~14px) | Animation+VFX | `base_hero.gd:198`, `UnitVisualDrawer.gd:819` |
| 11 | P2 | Dragon `_draw()` strokes ignore zoom-scale rule → fatten at 0.5x | Mobile | `UnitVisualDrawer.gd:654-825` |
| 12 | P2 | No muzzle burst at fire; impact VFX is arcane rune ring | VFX | `Arrow.gd:276-310` |
| 13 | P3 | Symmetric `sin()` flap — no downstroke snap | Animation | `UnitVisualDrawer.gd:658` |
| 14 | P3 | Head/neck buried under body; horns 2px hairlines | Silhouette | `UnitVisualDrawer.gd:780-810` |
| 15 | P3 | Back spines too short to break top contour | Silhouette | `UnitVisualDrawer.gd:751-762` |
| 16 | P3 | `flight_height_px=48` weak float separation; stale comment says 44 | Mobile | `visual_dragon.tres:15`, `base_hero.gd:2643` |
| 17 | P3 | Full-silhouette hit flash @ 0.08s re-armed every hit → strobe | VFX | `UnitVisualDrawer.gd:622-651`, `base_hero.gd:28,2288` |
| 18 | P3 | Mouth launch point collapses to body center at vertical aim | VFX | `base_hero.gd:1576-1578` |
| 19 | P3 | Tail swings as rigid pendulum (no travelling wave) | Animation | `UnitVisualDrawer.gd:698-708` |

Accepted as-is (no change): projectile internal color cohesion is good;
contrast vs backgrounds adequate (rely on outline, don't lighten body);
color-blind safe (red is cosmetic identity, never game state); `radius=52`
boss-scale is intentional.

---

## Cross-lens conflicts (resolve before implementing)

- **Membrane color (#5).** Silhouette wants a *visibly darker, opaque*
  `Color(0.40, 0.06, 0.05, 1.0)` for body/wing separation. Palette wants a
  hue-locked derived blend `body_col.lerp(accent_color, 0.45)` ≈
  `Color(0.824, 0.276, 0.098, 0.82)` (near-identical look, just centralized).
  **Resolution:** the separation problem (#1/#2/#5) outranks pure
  centralization — adopt the Silhouette dark value but express it as a derived
  expression so it stays hue-locked: `body_col.darkened(0.45)` with `a = 1.0`
  (≈ `Color(0.374,0.060,0.044,1)`, matches Silhouette intent and references
  `body_color`). Only meaningful once #1/#2 land (wings currently invisible).
- **HUD (#6 vs #7).** Not a conflict — complementary. Fix BOTH the disk color
  (Palette) and the glyph shape (Mobile).

---

## Implement-ready specs, grouped by file

### `systems/UnitVisualDrawer.gd`

**P1 — Spec S-A (z-order):** in `_draw_dragon_premium` move the
`_draw_dragon_wings(...)` call (currently `:673`, right after tail) to
**after** `_draw_dragon_legs(...)` (`:691`) and **before**
`_draw_dragon_head(...)` (`:692`). Wings then overpaint the body (reads
wings-spread); head stays on top.

**P1 — Spec S-B (rebuild wing as non-self-intersecting fan):** replace the
`wing` PackedVector2Array at `:726-734` with a single non-crossing loop
(face_x=1 ref, `*y_sign`, `lift` as today):
```
root        = (-0.08r,  0.10r)
shoulder    = ( 0.34r,  0.04r)
front_tip   = ( 0.96r,  0.70r + lift*0.18)
tip         = ( 0.10r,  2.30r + lift)
mid_notch   = (-0.34r,  1.65r + lift*0.55)
knuckle     = (-0.70r,  1.10r + lift*0.38)
rear_notch  = (-0.95r,  0.70r + lift*0.22)
```
Order `[root, shoulder, front_tip, tip, mid_notch, knuckle, rear_notch]`.
Leading edge X monotone up, trailing edge X monotone back — verify no segment
crosses. Keep struts `root→tip` (main spar), `root→shoulder`,
`shoulder→front_tip`, `knuckle→tip`, `knuckle→mid_notch`. If the triangulator
dislikes the concavity, flip winding.

**P2 — Spec S-C (membrane separation, conflict-resolved):** `:668`
`Color(0.92,0.20,0.08,0.82)` → `var membrane: Color = body_col.darkened(0.45); membrane.a = 1.0`
(≈ `Color(0.374,0.060,0.044,1)`). Keep back-wing `membrane.darkened(0.10)`.

**P2 — Spec S-D (decouple wing/tail clocks):** `:657-659` replace single
`theta` with independent rates — `wing_w = maxf(2.0, v.walk_bob_speed)*1.65`
(≈6.93 rad/s), `tail_w = 2.35` *absolute* (NOT a wing harmonic),
`tail_phase = t*tail_w + walk_phase*1.7 + 0.6`. `wing_flap` uses `_flap_curve`
(Spec S-E); `tail_sway = sin(tail_phase) * r * 0.12`.

**P3 — Spec S-E (asymmetric flap):** add static helper, use for the wing term:
```
static func _flap_curve(p: float) -> float:
    var x := fposmod(p, TAU) / TAU
    return -cos(x / 0.35 * PI) if x < 0.35 else cos((x - 0.35) / 0.65 * PI)
```
Fast 35% downstroke, slow 65% recovery. Amplitude stays `r*0.24`.

**P3 — Spec S-F (head terminus):** `:780-785` add `+0.10r` to neck X pts 2-3;
`:788-803` add `+0.18r` to all head+jaw X; scale head poly 1.25× about
centroid `(1.25r,-0.08r)`. Replace each horn `draw_line` (`:810`) with a filled
triangle base `r*0.10`, length `r*0.42`, swept back, fill
`Color(1.0,0.82,0.52,1)` + 1.4px outline.

**P3 — Spec S-G (taller spines):** `:755` `r*lerpf(0.16,0.24,…)` →
`r*lerpf(0.26,0.40,…)`; `:754` ridge `-r*(0.46+0.09*sin)` → `-r*(0.50+0.10*sin)`.

**P3 — Spec S-H (travelling-wave tail):** `:698-708` phase-delay tail verts —
mid `sin(tail_phase-0.35)`, tip `sin(tail_phase-0.7)`, barb
`sin(tail_phase-0.9)`; keep `1.0/0.8/0.7` amplitude falloff.

**P2 — Spec S-I (zoom-scale strokes):** thread `ctx["zoom_scale"] = zs` from
`base_hero.gd` (~`:2648`, `zs` already at `:2579`; default `1.0` for
enemy/soldier callers). In `_draw_dragon_premium:664`:
`zss = clampf(float(ctx.get("zoom_scale",1.0)),0.5,2.0)`, then
`outline_w = maxf(2.0, v.outline_width*0.58) * zss`. Propagate `zss` into
`_wings/_tail/_spines/_legs/_head`, multiply every `draw_line`/`draw_polyline`
width (incl. bare `1.2` at `:762` → `maxf(1.0,1.2*zss)`). Leave `draw_circle`
radii (size, not stroke).

**P3 — Spec S-J (tame hit flash):** in `_draw_dragon_hit_flash` (`:622-651`)
remove the two wing polygons (`:624-635`); keep body ellipse, head/neck, tail
wedge. (Pair with V-D.)

### `heroes/data/visual_dragon.tres`

**P3 — Spec T-A (stronger float):** `flight_height_px = 48.0` → `70.0` (stays
< `_MAX_FLIGHT_HEIGHT=80`; shadow shrinks/dims, reads airborne). Grep
`flight_height_px` across `balance/` + `docs/COMBAT_BLOCKING_DOCTRINE.md`
first — confirm no combat/balance code keys off `==48`.

**(Optional) Spec T-B:** if per-line `*zss` route (S-I) is rejected,
`outline_width 6.0 → 8.0` instead (also thickens body outline — desirable).
Don't apply both.

### `ui/HeroHudPortrait.gd`

**P2 — Spec H-A (disk color):** `:229` dragon `Color(0.50,0.18,0.14)` →
`Color(0.68,0.11,0.08)` to match body. If adding palette entries,
`ThemeColors.DRAGON_EMBER = Color(0.68,0.11,0.08)` (== current body, zero
visual drift, centralizes the 4-file ember identity) and reference it here.
Do NOT reuse `ACCENT_RED`/`BANNER_RED` (visibly duller).

**P2 — Spec H-B (dragon-shaped glyph):** replace symmetric-triangle block
`:267-281` with asymmetric side-profile (forward head + back-swept wing +
horn), `r = disk_radius*0.55`:
```
wing  = [(-0.10r,0.10r),(-0.95r,-0.65r),(-0.30r,-0.05r),(-0.80r,0.55r)]
body  = [(-0.30r,0.30r),(0.10r,-0.05r),(0.30r,0.05r),(0.05r,0.45r)]
head  = [(0.25r,-0.05r),(0.95r,-0.20r),(0.80r,0.12r),(0.45r,0.18r)]
horn  = draw_line((0.45r,-0.12r),(0.15r,-0.55r), fg, 3.0)
```
All filled `fg` (no new color), within ±r of `c`. Reads "dragon at a glance",
distinct from mage star / ranger bow.

### `projectiles/DragonBreath.tscn` + `projectiles/Arrow.gd`

**P1 — Spec V-A (real fire shape):** `Arrow.gd:9` append
`FIRE_BREATH` (=7, never reorder). Add `Shape.FIRE_BREATH:
_draw_fire_breath_shape()` to the draw match (`:561-575`) and to the impact
match (`:276`). New `_draw_fire_breath_shape()`: 3 stacked teardrop lobes —
outer `r=16*pulse` `Color(1.0,0.34,0.08,0.55)` (`pulse=1+sin(_time*9)*0.12`),
mid `r=11` `Color(1.0,0.62,0.16,0.85)`, hot core `r=6`
`Color(1.0,0.95,0.62,0.95)`, forward lick triangle. No white core, no runes.
Set `DragonBreath.tscn:11 shape = 7`.

**P1 — Spec V-B (charge glow + muzzle on basic attack):** add
`const BREATH_WIND_DURATION := 0.18` + `var _breath_wind_t := 0.0` near
`base_hero.gd:198`. At the dragon basic-attack trigger (the site computing the
mouth spawn at `:1577`): set `_breath_wind_t`, defer the `Arrow` instantiation
until it expires (mirror `_apply_pending_skill` deferral `:1236`), decrement in
`_physics_process` alongside `_cast_t` (`:1426-1437`). In the DRAGON_PREMIUM
ctx builder (`:2720-2736`): `ctx["wind_t"] = clampf(_breath_wind_t/BREATH_WIND_DURATION,0,1)`
— drives the existing `_draw_dragon_head` charge path, no drawer change. On
fire: spawn `_FireMuzzleVFX` at the mouth (6–8 ember streaks, `LIFE=0.16`,
`Color(1.0,0.95,0.62)→Color(1.0,0.34,0.08,0)`, 14–22px, ±35° around face_x).

**P3 — Spec V-C (robust vertical-aim anchor):** `base_hero.gd:1576-1578` when
`absf(face_x)<0.08`, set `dragon_mouth_local = (target_world - global_pos).normalized()*body_r*1.64 + Vector2(0,-body_r*0.04)`
instead of collapsing to center. Leave the L/R path unchanged.

**P3 — Spec V-D (fire impact + flash):** new `_FireImpactVFX` in `Arrow.gd`
(`LIFE=0.30`): dark scorch ellipse 18×6px, 7 embers scattering 0→34px, one
flame puff 8→22px — no expanding ring, no rune flashes; route via the V-A
impact case. Pair with S-J; `base_hero.gd:28` `HIT_FLASH_DURATION 0.08→0.12`
and at `:2288` only re-arm if `_hit_flash_t < HIT_FLASH_DURATION*0.45`.

**P2 — Spec V-E (telegraph strength, with V-B):** `base_hero.gd:198`
`CAST_WIND_DURATION 0.15→0.32`; `UnitVisualDrawer.gd:819`
`maxf(cast_t, wind_t*0.55)` → `wind_t*0.85`; `:824` mouth radius
`r*(0.18+charge*0.16)` → `r*(0.20+charge*0.34)`; `:823` multiply flame alpha by
`(0.78+0.22*sin(Time.get_ticks_msec()*0.018))` for a charging pulse.

---

## Recommended execution order

1. **S-A + S-B together** (P1 — z-order + wing polygon). Gate every other
   silhouette/palette fix; nothing else is visible until wings render right.
   Screenshot Level6 at zoom 1.0 and 0.5 before continuing.
2. **V-B** (P1 — basic-attack charge windup). Highest VFX impact; precondition
   for V-A/V-E continuity to be visible at all.
3. **V-A** (P1 — fire shape) once V-B lands.
4. **H-A + H-B** (P2, UI-only, zero blast radius — safe quick win).
5. S-C, S-D/S-E, S-I, V-E, T-A, then P3 polish (S-F/G/H, V-C/D, S-J).

## Risks / caveats

- All five reviews were static (source-derived), no in-editor/in-game capture.
  Perceived severity of #1/#2 at 60px and against `level_6_bg.png` is
  high-confidence but unverified by screenshot. Capture a Level6 pass at
  zoom 1.0/0.5/2.0 and phone aspect after each P1 lands.
- Specs touching working scripts (`base_hero.gd` V-B/V-E, `CAST_WIND_DURATION`
  gates real skill-apply timing; S-I changes the shared drawer ctx signature):
  per CORE RULE 1/9 add as new dragon-only branches, don't modify shared paths;
  default `ctx` guards keep enemy/soldier callers safe — test headless + visual.
- Spec winding (S-B, S-F) may need a CW/CCW flip if `draw_colored_polygon`'s
  triangulator rejects the new concavity — verify visually.

---

## Status — 2026-05-18 (closed)

**Implemented + visually verified in-game (MCP, Level6, zoom 0.5/1.0/2.2/3.0):**
S-A, S-B, S-C, S-D, S-E, S-F, S-G, S-H, S-I, S-J, V-A, V-B, V-E (visual only),
H-A, H-B, T-A. Plus an unplanned fix: the S-B wing rebuild left the `root→tip`
bone spar near-vertical (a seam bisecting the body) — rerouted along the wing
arm (root→knuckle→tip).

**Deviations from the original specs (deliberate, lower risk):**
- V-B implemented as a cooldown-driven pre-fire telegraph, NOT projectile
  deferral (deferral would shift damage/cooldown timing → balance risk).
- V-E: only the dragon-only visual strength (pts 2–4) applied; the shared
  `CAST_WIND_DURATION` change (pt 1) was NOT made.

**Won't do — user decision 2026-05-18 ("skip both"):** V-E pt1 (raise shared
CAST_WIND_DURATION) and hit-flash duration/re-arm tuning — both change
game-wide feel; not worth the blast radius without a dedicated feel pass.
Optional S-D hover-vs-forward flap differentiation also left unbuilt (pure
polish, no demand). **This review is closed.**
