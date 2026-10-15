# Space Blast — Visual + HUD + VFX + Tutorial Upgrade

## Context

`lib/features/games/arcade/space_blast_game.dart` (~1442 LOC) already
implements a working retro space shooter: drag-to-position starship,
auto-firing lasers, V/Line/Diamond/Zigzag alien formations, weapon
upgrades (spread/beam/shield), 3 parallax starfield layers, particle
bursts, shockwaves, wave-clear banner, GAME OVER.

But visual fidelity doesn't match the spec'd reference:

1. **Canvas** is a simple `LinearGradient(#0F172A → #1E1B4B)` — spec
   asks for deep navy/purple space canvas with **animated
   multi-layered scrolling vector starfields** (kept) and **distant
   glowing nebula clouds**.
2. **HUD** is 4 dark `_Chip` pills (Score/Wave/Lives/Weapon) — spec
   asks for a complete HUD: white circular Pause button + current
   stage badge (`Stage 4`) on left, rounded white `SCORE 3,850` card
   centre, red heart-lives pill (`3/3`) on right.
3. **Starship** has functional body + flame + cockpit but no thick
   dark outline + kawaii face — spec asks for cute vector spaceship
   with **thick dark outlines**, **bright cyan wings**, **glossy
   cockpit glass**, and **animated flame engine thruster**.
4. **Aliens** are simple ovals with eyes + radial gradient — spec
   asks for kawaii alien invaders with **rotating space rocks /
   asteroids** moving downward in distinct patterns (zigzag, swoop,
   grid).
5. **Lasers** are flat coloured rectangles — spec asks for **bright
   pink or glowing neon yellow** vector lasers.
6. **Floaters** are plain TextPainter labels — spec asks for
   **cartoon text popups** (`BOOST!`, `BLAST! +150`) with star
   sparkles.
7. **Power-ups** drop from killed aliens (kept) — spec also asks
   for **star coins** as collectibles that glide toward the player.
8. **No tutorial overlay** — spec asks for floating white capsule
   pill at the bottom with bold text ("Drag to move & shoot!") +
   animated vector hand demonstrating a left-to-right dragging motion
   underneath the starship.
9. **No direct `HapticFeedback.*Impact`** calls — currently routed
   via host proxy. Spec wants `HapticFeedback.selectionClick()` on
   enemy hits, `HapticFeedback.mediumImpact()` on power-up pickup.
10. **No pause** — the previous engine had no pause; spec asks for a
    Pause button on the HUD.

The class signature
`SpaceBlastGame({super.key, required super.callbacks})` and
dispatcher wiring (`case 'space-blast'`) stay byte-identical.

---

## Scope

### File modified (1)
- `lib/features/games/arcade/space_blast_game.dart` — visual + HUD +
  chrome + VFX + tutorial rewrite (~1900 LOC; +460 over current).

### Reused (no edits)
- `lib/features/games/mini_game.dart` — `MiniGame` / `MiniGameState`
- `lib/features/games/widgets/game_scaffold.dart` — `GameScaffold`
  (kept in reserve; the game drives the full-screen canvas + HUD
  with its own Stack layout).
- `lib/features/games/widgets/game_artwork.dart` — catalogue card
  icon, unchanged.
- `lib/core/widgets/scale_tap_button.dart` — wrap Pause button.
- `lib/data/registry/game_registry.dart` — entry unchanged.
- `lib/features/game_player/games_dispatcher.dart` — `case 'space-blast'`
  unchanged.

---

## Design

### A. Deep Space Canvas (navy/purple gradient + nebula clouds)

#### A.1 Base gradient
Linear top-to-bottom `#0F172A → #1E1B4B → #2E1065` (deep navy →
indigo → purple).

#### A.2 Nebula clouds
Two large soft elliptical `RadialGradient` clouds at fixed positions:
- Top-left: magenta `Color(0xFFA855F7)` 18 % alpha, blurred via
  `MaskFilter.blur(normal, 60)`.
- Bottom-right: cyan `Color(0xFF22D3EE)` 12 % alpha, same blur.
- A middle cloud: pink `Color(0xFFFB7185)` 10 % alpha.

These give the impression of distant glowing nebulae drifting behind
the starfield. Rendered **before** the stars in the painter.

#### A.3 Starfield (kept + tweaked)
3 parallax layers (60/140/240 dp/s, with twinkling alpha via
`sin(idleTime * 3 + s.phase)`).

### B. Top HUD Bar (white cards)

#### B.1 Left pill — Pause + Stage badge
A horizontal white pill:
- **44 dp circular white Pause button** with `Icons.pause_rounded`
  in `Color(0xFF1E3A8A)`. Wrapped in `ScaleTapButton`. Toggles to
  red `▶` when `_paused`.
- Adjacent rounded capsule with `Icons.rocket_launch_rounded` cyan +
  bold `STAGE N` text in `Color(0xFF1E3A8A)`.
- Stage = wave number.

#### B.2 Centre — SCORE card
Rounded white card `BorderRadius.circular(20)`:
- 10 dp uppercase `SCORE` label `Color(0xFF1E3A8A)`.
- Score with thousands separator: `3,850` (22 dp, tabular figures,
  `Color(0xFF0F172A)`).
- Star icon (`Icons.star_rounded`, `Color(0xFFFFC837)`, 20 dp) on
  the left.

#### B.3 Right pill — Hearts
White capsule with red heart icon + bold `3/3` (decrement on player
hit). Pulses red on every slice / power-up pickup.

#### B.4 SHIELD/POWER-UP gauge underneath the player ship
A small rounded white capsule with `Icons.shield_rounded` cyan +
`SHIELD` text + horizontal progress bar that fills as the player
gains XP / combo / etc. For this implementation we use a
**wave-progress gauge**: `Wave N / 10` style bar that fills as
aliens in the current wave are killed. Visual: rounded white pill
with thin progress fill bar `Color(0xFF22D3EE)` cyan. Position:
above the player ship (top of bottom HUD area) per spec.

### C. Kawaii Starship

#### C.1 Ship body
- Rounded teardrop body (cyan-white gradient) with **thick dark
  outline** (`Color(0xFF0F172A)` 2.0 dp stroke).
- Bright cyan wings — `Color(0xFF22D3EE)` swept-back triangles with
  dark outline.
- Glossy cockpit glass — radial gradient (light blue → deep navy)
  with white highlight crescent at top-left.
- Engine thruster flame — animated teardrop flame in
  orange→red gradient with white core, flicker via `sin(flameTime *
  30)`.

#### C.2 Invincibility + Shield
- Invincibility flicker (kept) + small white dotted ring around the
  ship during the 0.6 s window.
- Shield bubble (yellow) — bigger dome with cyan accent.

### D. Kawaii Aliens + Rotating Asteroids

#### D.1 Alien kinds

```dart
enum _AlienKind { grunt, shooter, tank }
```

- **Grunt** (pink): pink body with cute eyes + smile + antenna,
  drops with 20 pts.
- **Shooter** (yellow): yellow body with eyes + a small antenna +
  gun barrel, drops with 30 pts.
- **Tank** (purple): purple body with eyes + thick armor plates,
  drops with 50 pts (2 HP).

All aliens have **thick dark outlines** (`Color(0xFF1F2937)` 2 dp).

#### D.2 Rotating space rocks / asteroids
A new entity `_Asteroid` (irregular polygon path) that:
- Spins on its own axis (`rotation += spin * dt`).
- Falls straight down at `60 + rng.nextInt(40)` dp/s.
- Has 1 HP; on hit: small explosion + 10 pts.
- Spawned at random intervals (every 1.2–2.5 s) from above the
  playfield.

#### D.3 Spawn patterns (kept + refined)
The existing V/Line/Diamond/Zigzag formations are kept. The
asteroids add a second interleaved spawn timer that drops rocks
every 1.5 s alongside the formations.

### E. Vector Lasers (pink + neon yellow)

- **Normal weapon**: **glowing neon yellow** laser
  (`Color(0xFFFACC15)` 3 dp wide) — outer glow + yellow core + white
  spine.
- **Spread weapon**: cyan 3-fan (kept).
- **Beam weapon**: bright pink (`Color(0xFFFB7185)` 6 dp) — outer
  pink glow + pink core + white spine.

Spec asks for bright pink **or** glowing neon yellow; we use yellow
for normal (matches retro arcade) and pink for beam (matches the
"bigger gun" theme).

### F. 3-D Floaters + Star Sparkles

When killing an alien:
- A `_Floater` with 3D text effect (mirrors Basket Bounce / Snake
  Master / Fruit Slice layered TextPainter passes):
  - Outer yellow `MaskFilter.blur(outer, 12)` glow.
  - Yellow stroke `strokeWidth: 4` via `foreground: Paint()`.
  - Drop shadow TextPainter.
  - White base TextPainter.
- 8 small 4-point star sparkles fly outward from the kill centroid.

For tank kills (≥2 HP): big `BLAST! +50` 3D popup.
For power-up pickups: `BOOST!` / `SPREAD!` / `BEAM!` / `SHIELD!` 3D
popup.

### G. Star Coins (new collectible)

A new `_Coin` entity that drops from aliens with 10 % chance:
- 12 dp yellow coin with `$` glyph.
- Falls slowly + glides toward the player (homing) once spawned.
- Worth 25 pts on pickup.
- 3D `+25` popup on collect.

### H. Tutorial Overlay

Stateful overlay widget rendered at the bottom on first 6 s of
play (or until first drag):

```
  Capsule: rounded white BorderRadius.circular(28)
           padding: 18 × 12
           BoxShadow: Color(0x14000000) blurRadius 18 offset (0, 6)
           Bottom: 110 dp from bottom edge

  Layout: [ HAND ]  Drag to move & shoot!
```

- **Hand** same yellow palm + index-finger design as Racing Rush /
  Snake Master / Basket Bounce / Fruit Slice, but the **finger
  orientation is horizontal** (rotated -0.3 rad) — it performs a
  slow left-to-right drag motion: `sin(idleTime * 4) * 14` on x.
- **Slide-up animation**: 280 ms `Curves.easeOutCubic`.
- **Auto-dismiss** after 6 s OR on first `_onPanStart` call.

State:
```
bool _showTutorial = true;
double _tutorialElapsed = 0;
bool _tutorialDismissed = false;
```
`_dismissTutorial()` is called from `_onPanStart`.

### I. Direct HapticFeedback Calls

Add `import 'package:flutter/services.dart';`. Replace host-proxy
haptics:

- **Enemy kill**: `HapticFeedback.selectionClick()`.
- **Power-up pickup**: `HapticFeedback.mediumImpact()`.
- **Player hit (lose life)**: `HapticFeedback.heavyImpact()`.
- **Wave clear**: `HapticFeedback.heavyImpact()`.

Host-proxy `haptic(HapticFeedbackType.X)` calls kept as fallback
for audio cue compatibility.

### J. State & Architecture (delta only)

```dart
class _State extends MiniGameState<SpaceBlastGame>
    with TickerProviderStateMixin {  // CHANGED: add IdleTicker for tutorial hand + stars

  // NEW state:
  bool _paused = false;
  int _stage = 1;  // matches wave

  bool _showTutorial = true;
  double _tutorialElapsed = 0;
  bool _tutorialDismissed = false;

  // NEW records:
  // _Asteroid (rotating space rock)
  // _Coin (star coin collectible)
  // _StarSparkle (4-point star trail particle)

  // NEW widgets:
  class _TopHudSpace extends StatelessWidget  // white-cards spec HUD
  class _ShieldGauge extends StatelessWidget  // wave-progress bar
  class _TutorialOverlaySpace extends StatefulWidget  // capsule + hand
  class _SpaceHandPainter extends CustomPainter  // horizontal swipe
}
```

### K. Painter delta — `_SpacePainter.paint`

Updated section order:

```
  1. Nebula clouds          (NEW)
  2. Stars (parallax)       (kept + twinkle)
  3. Aliens                 (UPDATED: thick outline + smile + dark outline)
  4. Asteroids              (NEW)
  5. Alien lasers           (kept)
  6. Power-ups              (kept)
  7. Coins                  (NEW)
  8. Shocks                 (kept)
  9. Particles              (kept)
 10. Star sparkles          (NEW: 4-point stars)
 11. Player ship            (UPDATED: thick outline + cyan wings + glass)
 12. Lasers                 (UPDATED: yellow/pink layered)
 13. Floaters (3D)          (UPDATED: 3-D layered text)
 14. Wave-clear banner      (kept)
```

---

## Critical files

### Modified (1)
- `lib/features/games/arcade/space_blast_game.dart` — visual +
  chrome + VFX + tutorial rewrite (~1900 LOC)

### Reused (no edits)
- `lib/features/games/mini_game.dart` — base class
- `lib/features/games/widgets/game_scaffold.dart` — kept in reserve
- `lib/features/games/widgets/game_artwork.dart` — card icon,
  unchanged
- `lib/core/widgets/scale_tap_button.dart` — wrap Pause button
- `lib/data/registry/game_registry.dart` — entry unchanged
- `lib/features/game_player/games_dispatcher.dart` — dispatcher
  entry unchanged

---

## Verification

1. `flutter analyze` → 0 issues across the full project.
2. `flutter test` → 266 passing / 8 failing baseline unchanged.
3. **Visual smoke (manual):**
   * Launch any `space-blast` stage → deep navy → indigo → purple
     gradient canvas with magenta/cyan/pink soft glowing nebula
     clouds drifting behind the starfield.
   * Top HUD: white Pause + `STAGE 1` badge on left, white
     `SCORE 0` card centre (increments with thousands separator),
     red hearts pill `3/3` on right.
   * SHIELD/POWER-UP progress bar above the player ship fills as
     aliens in the current wave are killed.
   * Kawaii starship with thick dark outlines, bright cyan wings,
     glossy cockpit glass, animated flame thruster.
   * Drag the ship → smooth follow with zero input lag; ship tilts
     toward drag direction.
   * Continuous auto-firing neon yellow lasers stream from the
     nose. Spread (cyan) and beam (pink) variants show on pickup.
   * Aliens spawn in V/Line/Diamond/Zigzag formations; rotating
     space rocks fall straight down between waves.
   * Killing alien → 16-particle radial burst + shockwave ring +
     star sparkles + `+20`/`+50`/`BLAST!` 3D popup + light haptic.
   * 10 % chance to drop a star coin that homes toward the ship.
     25 % chance to drop a weapon/shield power-up (kept).
   * Wave clear → orange `WAVE N CLEAR!` banner + heavy haptic +
     auto-spawn next wave.
   * Player hit → lose 1 heart, screen shake, 0.6 s invincibility,
     heavy haptic. At 0 hearts → GAME OVER.
   * First 6 s: tutorial capsule slides up from bottom with animated
     cartoon hand performing a left-to-right drag motion; first drag
     dismisses the capsule.
   * Pause button toggles to `▶` (red) and shows a centred `PAUSED`
     capsule overlay.
4. **Ticker safety:** verify no ticker assertion errors — moved to
   `TickerProviderStateMixin` since we add `_idleTicker` alongside
   `_ticker`.
5. **Layout robustness:** at narrow phone widths (320 dp), the HUD
   reflows (Pause + STAGE pill stack left, SCORE card centred,
   hearts pill right).

---

## Out of scope (explicitly)

- Wholesale replacement of the wave spawn logic or weapon engine
  (kept).
- A `GameScaffold` adoption — Space Blast is full-screen-canvas
  with its own per-frame painter.
- Boss enemies — single-stage formations only.
- Multi-touch (`onPanStart` + `onPanUpdate` only).
- New audio assets — host already pairs haptics with audio cues
  for free.
- New registry / dispatcher / route entries.
- Localised strings.
