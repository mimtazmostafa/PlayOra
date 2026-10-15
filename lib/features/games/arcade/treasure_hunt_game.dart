// Treasure Hunt — full multi-screen adventure.
//
// Matches the reference: an isometric tile map the explorer can
// swipe across, hidden treasure chests, a hint popup, a level
// selection with five themed worlds, a treasure collection ledger
// with six categories, and the standard start / win / trophy
// overlays shared with the rest of the family.
//
// Phases:
//   start → levelSelect → play → win → trophy
//   ↘ collection (always accessible from levelSelect)

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';
import '../widgets/game_flow_overlays.dart';

class TreasureHuntGame extends MiniGame {
  const TreasureHuntGame({
    super.key,
    required super.callbacks,
  });

  @override
  State<TreasureHuntGame> createState() => _TreasureHuntGameState();
}

enum _TreasurePhase {
  start,
  levelSelect,
  collection,
  play,
  hint,
  win,
  trophy,
}

// ── Level definitions ────────────────────────────────────────────────

enum _WorldTheme { island, desert, jungle, volcano, ruins }

class _World {
  const _World({
    required this.id,
    required this.name,
    required this.theme,
    required this.targetStars,
    required this.unlockStars,
    required this.subtitle,
  });

  final int id;
  final String name;
  final _WorldTheme theme;
  final int targetStars;
  final int unlockStars;
  final String subtitle;

  static const lostIsland = _World(
    id: 1,
    name: 'Lost Island',
    theme: _WorldTheme.island,
    targetStars: 60,
    unlockStars: 0,
    subtitle: 'Discover beaches & shipwrecks',
  );
  static const desertRuins = _World(
    id: 2,
    name: 'Desert Ruins',
    theme: _WorldTheme.desert,
    targetStars: 60,
    unlockStars: 1,
    subtitle: 'Dig through ancient sands',
  );
  static const jungleTemple = _World(
    id: 3,
    name: 'Jungle Temple',
    theme: _WorldTheme.jungle,
    targetStars: 60,
    unlockStars: 2,
    subtitle: 'Solve vine-covered riddles',
  );
  static const volcanicCave = _World(
    id: 4,
    name: 'Volcanic Cave',
    theme: _WorldTheme.volcano,
    targetStars: 60,
    unlockStars: 3,
    subtitle: 'Brave the lava rivers',
  );
  static const ancientCity = _World(
    id: 5,
    name: 'Ancient City',
    theme: _WorldTheme.ruins,
    targetStars: 60,
    unlockStars: 4,
    subtitle: 'Uncover the lost kingdom',
  );

  static const all = <_World>[
    lostIsland,
    desertRuins,
    jungleTemple,
    volcanicCave,
    ancientCity,
  ];
}

// ── In-level state ───────────────────────────────────────────────────

/// A hidden treasure on the map. The player has to swipe to within
/// `triggerRadius` of the tile centre to dig it up.
class _Treasure {
  _Treasure({
    required this.position,
    required this.kind,
    required this.points,
    required this.isMain,
  });

  final Offset position; // normalized 0..1 over the map rect
  final _TreasureKind kind;
  final int points;
  final bool isMain;
  bool found = false;
}

enum _TreasureKind { chest, gem, coin, key, crown, map }

// ── Treasure collection ledger (persistent across the run) ──────────

class _Collection {
  const _Collection({
    this.coins = 0,
    this.gems = 0,
    this.crowns = 0,
    this.maps = 0,
    this.keys = 0,
    this.chests = 0,
    this.currentKind = _TreasureKind.chest,
  });

  final int coins;
  final int gems;
  final int crowns;
  final int maps;
  final int keys;
  final int chests;
  final _TreasureKind currentKind;

  _Collection copyWith({
    int? coins,
    int? gems,
    int? crowns,
    int? maps,
    int? keys,
    int? chests,
    _TreasureKind? currentKind,
  }) {
    return _Collection(
      coins: coins ?? this.coins,
      gems: gems ?? this.gems,
      crowns: crowns ?? this.crowns,
      maps: maps ?? this.maps,
      keys: keys ?? this.keys,
      chests: chests ?? this.chests,
      currentKind: currentKind ?? this.currentKind,
    );
  }

  int countOf(_TreasureKind k) {
    switch (k) {
      case _TreasureKind.coin:
        return coins;
      case _TreasureKind.gem:
        return gems;
      case _TreasureKind.crown:
        return crowns;
      case _TreasureKind.map:
        return maps;
      case _TreasureKind.key:
        return keys;
      case _TreasureKind.chest:
        return chests;
    }
  }

  static const targets = <_TreasureKind, int>{
    _TreasureKind.coin: 50,
    _TreasureKind.gem: 20,
    _TreasureKind.crown: 10,
    _TreasureKind.map: 15,
    _TreasureKind.key: 8,
    _TreasureKind.chest: 50,
  };

  static const labels = <_TreasureKind, String>{
    _TreasureKind.coin: 'Coins',
    _TreasureKind.gem: 'Gems',
    _TreasureKind.crown: 'Crowns',
    _TreasureKind.map: 'Maps',
    _TreasureKind.key: 'Keys',
    _TreasureKind.chest: 'Golden Chest',
  };
}

// ────────────────────────────────────────────────────────────────────
// State
// ────────────────────────────────────────────────────────────────────

class _TreasureHuntGameState extends MiniGameState<TreasureHuntGame>
    with SingleTickerProviderStateMixin {
  static const int _treasuresPerLevel = 3;
  static const Duration _timeBudget = Duration(seconds: 45);

  late final Ticker _ticker;
  late final Random _rng;

  _TreasurePhase _phase = _TreasurePhase.start;
  _World _currentWorld = _World.lostIsland;

  // World-level state.
  List<_Treasure> _treasures = [];
  Offset _player = const Offset(0.5, 0.85);
  Duration _timeLeft = _timeBudget;
  Duration _last = Duration.zero;
  int _score = 0;

  // Per-world best stars — Lost Island starts complete so the player
  // unlocks the next world without grinding through the tutorial.
  final Map<int, int> _bestStars = {
    1: 60,
    2: 0,
    3: 0,
    4: 0,
    5: 0,
  };

  // Persistent collection ledger.
  _Collection _collection = const _Collection();

  // Player swipe-move state.
  Offset _dragStart = Offset.zero;

  // HUD dedupe — avoid hammering the host with identical stats.
  String _lastStats = '';
  int _lastReportedScore = -1;

  // ── Lifecycle ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _rng = Random();
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats(
        'Coins ${_collection.coins}/${_Collection.targets[_TreasureKind.coin]}'
        '  •  Gems ${_collection.gems}/${_Collection.targets[_TreasureKind.gem]}',
      );
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // ── Map generation ─────────────────────────────────────────────────

  void _setupLevel(_World world) {
    _currentWorld = world;
    final positions = <Offset>[];
    var attempts = 0;
    while (positions.length < _treasuresPerLevel && attempts < 400) {
      attempts++;
      final p = Offset(
        0.12 + _rng.nextDouble() * 0.76,
        0.16 + _rng.nextDouble() * 0.68,
      );
      final ok = positions.every((q) => (p - q).distance > 0.28);
      if (ok) positions.add(p);
    }
    final kinds = _TreasureKind.values.toList()..shuffle(_rng);
    // The first treasure is always the main "chest" — the others are
    // bonus pickups that boost the level score.
    _treasures = [
      for (var i = 0; i < positions.length; i++)
        _Treasure(
          position: positions[i],
          kind: i == 0 ? _TreasureKind.chest : kinds[i % kinds.length],
          points: i == 0 ? 60 : 20,
          isMain: i == 0,
        ),
    ];
    _player = const Offset(0.5, 0.88);
    _timeLeft = _timeBudget;
    _last = Duration.zero;
    _score = 0;
  }

  // ── Timer ──────────────────────────────────────────────────────────

  void _tick(Duration elapsed) {
    if (_phase != _TreasurePhase.play && _phase != _TreasurePhase.hint) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    if (_phase != _TreasurePhase.play) return;
    final dt = _last == Duration.zero
        ? Duration.zero
        : elapsed - _last;
    _last = elapsed;
    if (dt == Duration.zero) return;
    // Only rebuild the widget tree when an integer second has
    // elapsed — the HUD shows whole seconds, so sub-second frames
    // would otherwise produce no-op rebuilds.
    final newSeconds = (_timeLeft - dt).inSeconds;
    final secondsChanged = newSeconds != _timeLeft.inSeconds;
    _timeLeft = _timeLeft - dt;
    if (_timeLeft <= Duration.zero) {
      _timeLeft = Duration.zero;
      _endRound(won: false);
      return;
    }
    if (secondsChanged) setState(() {});
    _refreshHud();
  }

  void _refreshHud() {
    if (_score != _lastReportedScore) {
      _lastReportedScore = _score;
      reportScore(_score);
    }
    final stats =
        'Coins ${_collection.coins}/${_Collection.targets[_TreasureKind.coin]}'
        '  •  Time ${_timeLeft.inSeconds}s';
    if (stats != _lastStats) {
      _lastStats = stats;
      reportStats(stats);
    }
  }

  // ── Gameplay handlers ──────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    if (_phase != _TreasurePhase.play) return;
    _dragStart = d.localPosition;
  }

  void _onPanUpdate(DragUpdateDetails d, Size mapSize) {
    if (_phase != _TreasurePhase.play) return;
    final delta = d.localPosition - _dragStart;
    final ndx = delta.dx / mapSize.width;
    final ndy = delta.dy / mapSize.height;
    setState(() {
      _player = Offset(
        (_player.dx + ndx).clamp(0.06, 0.94),
        (_player.dy + ndy).clamp(0.06, 0.94),
      );
    });
    _dragStart = d.localPosition;
    _checkPickup();
  }

  void _checkPickup() {
    for (final t in _treasures) {
      if (t.found) continue;
      final d = (_player - t.position).distance;
      if (d < 0.09) {
        t.found = true;
        _score += t.points;
        _collection = _collectionFromPickup(t.kind, _collection);
        if (t.isMain) _collection = _collection.copyWith(currentKind: t.kind);
        haptic(HapticFeedbackType.medium);
        if (_treasures.every((x) => x.found)) {
          _endRound(won: true);
        }
      }
    }
    _refreshHud();
  }

  _Collection _collectionFromPickup(_TreasureKind k, _Collection c) {
    switch (k) {
      case _TreasureKind.coin:
        return c.copyWith(coins: c.coins + 1);
      case _TreasureKind.gem:
        return c.copyWith(gems: c.gems + 1);
      case _TreasureKind.crown:
        return c.copyWith(crowns: c.crowns + 1);
      case _TreasureKind.map:
        return c.copyWith(maps: c.maps + 1);
      case _TreasureKind.key:
        return c.copyWith(keys: c.keys + 1);
      case _TreasureKind.chest:
        return c.copyWith(chests: c.chests + 1);
    }
  }

  // ── Round end / phase transitions ─────────────────────────────────

  void _endRound({required bool won}) {
    if (won) {
      final previous = _bestStars[_currentWorld.id] ?? 0;
      if (_score > previous) _bestStars[_currentWorld.id] = _score;
    }
    haptic(won ? HapticFeedbackType.heavy : HapticFeedbackType.selection);
    reportGameOver();
    setState(() {
      _phase = won ? _TreasurePhase.win : _TreasurePhase.trophy;
    });
  }

  void _onPlay() {
    setState(() {
      _phase = _TreasurePhase.levelSelect;
    });
  }

  void _selectLevel(_World w) {
    if ((_bestStars[w.id] ?? 0) < w.unlockStars) return;
    setState(() {
      _currentWorld = w;
      _setupLevel(w);
      _phase = _TreasurePhase.play;
    });
    _refreshHud();
  }

  void _backToLevels() {
    setState(() {
      _phase = _TreasurePhase.levelSelect;
    });
  }

  void _openCollection() {
    setState(() {
      _phase = _TreasurePhase.collection;
    });
  }

  void _onContinueAfterWin() {
    setState(() {
      _phase = _TreasurePhase.trophy;
    });
  }

  void _onPlayAgain() {
    setState(() {
      _setupLevel(_currentWorld);
      _phase = _TreasurePhase.play;
    });
    _refreshHud();
  }

  void _toggleHint() {
    setState(() {
      _phase = _phase == _TreasurePhase.hint
          ? _TreasurePhase.play
          : _TreasurePhase.hint;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The gameplay surface is painted behind every non-start
        // screen so transitions don't show a flash of black.
        if (_phase != _TreasurePhase.start)
          Positioned.fill(
            child: RepaintBoundary(
              child: LayoutBuilder(builder: (ctx, c) {
                final size = Size(c.maxWidth, c.maxHeight);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _onPanStart,
                  onPanUpdate: (d) => _onPanUpdate(d, size),
                  child: CustomPaint(
                    painter: _MapPainter(
                      world: _currentWorld,
                      player: _player,
                      treasures: _treasures,
                      phase: _phase,
                    ),
                    size: size,
                  ),
                );
              }),
            ),
          ),
        if (_phase == _TreasurePhase.start)
          GameStartOverlay(
            title: 'TREASURE HUNT',
            subtitle: 'Hunt hidden chests\nacross 5 worlds!',
            youScore: _collection.countOf(_TreasureKind.chest),
            targetScore: _Collection.targets[_TreasureKind.chest]!,
            instruction:
                'Swipe across the map to walk. Get close to a chest to dig. Find every chest before the timer runs out.',
            illustration: const BoyCharacter(pose: BoyPose.walking),
            onPlay: _onPlay,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phase == _TreasurePhase.levelSelect)
          Positioned.fill(child: _LevelSelectView(
            bestStars: _bestStars,
            onSelect: _selectLevel,
            onCollection: _openCollection,
            onBack: () => Navigator.of(context).maybePop(),
          )),
        if (_phase == _TreasurePhase.collection)
          Positioned.fill(child: _CollectionView(
            collection: _collection,
            onBack: _backToLevels,
          )),
        if (_phase == _TreasurePhase.hint)
          Positioned.fill(child: _HintPopup(
            world: _currentWorld,
            onClose: _toggleHint,
            onBackToLevels: _backToLevels,
          )),
        if (_phase == _TreasurePhase.play)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GamePlayHud(
              youText: 'Found ${_treasures.where((t) => t.found).length}/$_treasuresPerLevel',
              counterText: 'Time ${_timeLeft.inSeconds}s',
              onPause: _toggleHint,
            ),
          ),
        if (_phase == _TreasurePhase.win)
          GameWinOverlay(
            title: 'YOU WIN!',
            subtitle: 'TREASURE FOUND!',
            scoreValue: _score,
            scoreLabel: 'Stars',
            statRows: [
              ('Coins', '${_collection.coins}'),
              ('Gems', '${_collection.gems}'),
            ],
            onContinue: _onContinueAfterWin,
          ),
        if (_phase == _TreasurePhase.trophy)
          GameTrophyOverlay(
            iconData: Icons.diamond_rounded,
            iconGradient: const [Color(0xFFFCD34D), Color(0xFFF59E0B)],
            title: _treasures.every((t) => t.found)
                ? 'Great Job!'
                : 'Time\'s up!',
            subtitle: _treasures.every((t) => t.found)
                ? 'You found every treasure in ${_currentWorld.name}.'
                : 'Try again — beat the clock in ${_currentWorld.name}.',
            score: _score,
            statRows: [
              ('Stars', '$_score'),
              ('Best', '${_bestStars[_currentWorld.id]}'),
              ('Target', '${_currentWorld.targetStars}'),
            ],
            onPlayAgain: _onPlayAgain,
            onBack: _backToLevels,
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Level selection screen
// ────────────────────────────────────────────────────────────────────

class _LevelSelectView extends StatelessWidget {
  const _LevelSelectView({
    required this.bestStars,
    required this.onSelect,
    required this.onCollection,
    required this.onBack,
  });

  final Map<int, int> bestStars;
  final ValueChanged<_World> onSelect;
  final VoidCallback onCollection;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1226), Color(0xFF1F2A4A)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _Header(
              title: 'SELECT LEVEL',
              onBack: onBack,
              trailing: _PillButton(
                icon: Icons.diamond_rounded,
                label: 'Collection',
                onTap: onCollection,
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                itemCount: _World.all.length,
                itemBuilder: (ctx, i) {
                  final w = _World.all[i];
                  final best = bestStars[w.id] ?? 0;
                  final unlocked = best >= w.unlockStars;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _LevelCard(
                      world: w,
                      best: best,
                      unlocked: unlocked,
                      isCurrent: false,
                      onTap: () => onSelect(w),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: _FeaturesPanel(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.world,
    required this.best,
    required this.unlocked,
    required this.isCurrent,
    required this.onTap,
  });

  final _World world;
  final int best;
  final bool unlocked;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(world.theme);
    return Opacity(
      opacity: unlocked ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: unlocked ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  palette.cardLight,
                  palette.cardDark,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.accent,
                    boxShadow: [
                      BoxShadow(
                        color: palette.accent.withValues(alpha: 0.55),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    unlocked ? _iconFor(world.theme) : Icons.lock_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              world.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (best >= world.targetStars)
                            const Icon(
                              Icons.verified_rounded,
                              color: Color(0xFFFCD34D),
                              size: 22,
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        world.subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (var i = 0; i < 3; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 3),
                              child: Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: unlocked && i < (best ~/ 20)
                                    ? const Color(0xFFFCD34D)
                                    : Colors.white.withValues(alpha: 0.25),
                              ),
                            ),
                          const Spacer(),
                          Text(
                            '$best/${world.targetStars}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturesPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rows = const [
      ('Explore', 'Beautiful maps'),
      ('Use hints', 'Find treasure faster'),
      ('Collect', 'Special items & rewards'),
      ('Beat', 'The clock for stars'),
      ('More', 'Treasures to discover'),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.auto_awesome_rounded,
                  color: Color(0xFFFCD34D), size: 18),
              SizedBox(width: 8),
              Text(
                'GAME FEATURES',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFFCD34D),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${r.$1} ${r.$2}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Collection screen
// ────────────────────────────────────────────────────────────────────

class _CollectionView extends StatelessWidget {
  const _CollectionView({required this.collection, required this.onBack});

  final _Collection collection;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1226), Color(0xFF1F2A4A)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _Header(title: 'TREASURE COLLECTION', onBack: onBack),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  _CurrentTreasureShowcase(
                    currentKind: collection.currentKind,
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2.1,
                    children: [
                      for (final k in _TreasureKind.values
                          .where((k) => k != _TreasureKind.chest))
                        _CollectionTile(
                          kind: k,
                          have: collection.countOf(k),
                          target: _Collection.targets[k]!,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentTreasureShowcase extends StatelessWidget {
  const _CurrentTreasureShowcase({required this.currentKind});

  final _TreasureKind currentKind;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFCD34D), Color(0xFFF59E0B)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: CustomPaint(
              painter: _TreasureIconPainter(kind: currentKind),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CURRENT TREASURE',
                  style: TextStyle(
                    color: Color(0xFF7C2D12),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _Collection.labels[currentKind]!,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Legendary tier • Found in your last hunt',
                  style: TextStyle(
                    color: Color(0xFF7C2D12),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({
    required this.kind,
    required this.have,
    required this.target,
  });

  final _TreasureKind kind;
  final int have;
  final int target;

  @override
  Widget build(BuildContext context) {
    final progress = (have / target).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CustomPaint(
              painter: _TreasureIconPainter(kind: kind),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _Collection.labels[kind]!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '$have/$target',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
                    valueColor: const AlwaysStoppedAnimation(
                      Color(0xFFFCD34D),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Hint popup
// ────────────────────────────────────────────────────────────────────

class _HintPopup extends StatelessWidget {
  const _HintPopup({
    required this.world,
    required this.onClose,
    required this.onBackToLevels,
  });

  final _World world;
  final VoidCallback onClose;
  final VoidCallback onBackToLevels;

  String get _hint => _hintsFor(world);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFCD34D), Color(0xFFF59E0B)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.55),
                      blurRadius: 20,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lightbulb_rounded,
                            color: Color(0xFF111827), size: 26),
                        const SizedBox(width: 8),
                        Text(
                          'HINT — ${world.name}',
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _hint,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: Color(0xFF111827),
                                width: 2,
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: onBackToLevels,
                            icon: const Icon(Icons.arrow_back_rounded,
                                color: Color(0xFF111827)),
                            label: const Text(
                              'Levels',
                              style: TextStyle(
                                color: Color(0xFF111827),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF111827),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: onClose,
                            icon: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white),
                            label: const Text(
                              'Resume',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _hintsFor(_World w) {
    switch (w.theme) {
      case _WorldTheme.island:
        return 'Look for the cracked stone near the waterfall. '
            'The treasure might be behind it!';
      case _WorldTheme.desert:
        return 'Dig where the camel skeleton lies — the chest is '
            'buried under the dune to the south.';
      case _WorldTheme.jungle:
        return 'The vine-covered boulder hides the key. Push past '
            'the totem poles and check the third clearing.';
      case _WorldTheme.volcano:
        return 'Watch the lava flow — when it cools, step on the '
            'obsidian tile. The crown is just north of it.';
      case _WorldTheme.ruins:
        return 'Count the broken columns. The fifth pillar has a '
            'loose top — tap it to reveal the map.';
    }
  }
}

// ────────────────────────────────────────────────────────────────────
// Shared header / pill button
// ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.title, this.onBack, this.trailing});
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFCD34D),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF111827), size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// World palette / icon helpers
// ────────────────────────────────────────────────────────────────────

class _WorldPalette {
  const _WorldPalette({
    required this.sky,
    required this.ground,
    required this.groundShadow,
    required this.accent,
    required this.cardLight,
    required this.cardDark,
  });

  final Color sky;
  final Color ground;
  final Color groundShadow;
  final Color accent;
  final Color cardLight;
  final Color cardDark;
}

_WorldPalette _paletteFor(_WorldTheme t) {
  switch (t) {
    case _WorldTheme.island:
      return const _WorldPalette(
        sky: Color(0xFFBFE6FF),
        ground: Color(0xFFFCD34D),
        groundShadow: Color(0xFFF59E0B),
        accent: Color(0xFF0EA5E9),
        cardLight: Color(0xFF0C4A6E),
        cardDark: Color(0xFF082F49),
      );
    case _WorldTheme.desert:
      return const _WorldPalette(
        sky: Color(0xFFFFE8B0),
        ground: Color(0xFFF6E6C5),
        groundShadow: Color(0xFFD9A968),
        accent: Color(0xFFD97706),
        cardLight: Color(0xFF7C2D12),
        cardDark: Color(0xFF451A03),
      );
    case _WorldTheme.jungle:
      return const _WorldPalette(
        sky: Color(0xFFD7F5D7),
        ground: Color(0xFF65A30D),
        groundShadow: Color(0xFF3F6212),
        accent: Color(0xFF16A34A),
        cardLight: Color(0xFF14532D),
        cardDark: Color(0xFF052E16),
      );
    case _WorldTheme.volcano:
      return const _WorldPalette(
        sky: Color(0xFFFFD7CC),
        ground: Color(0xFF1F2937),
        groundShadow: Color(0xFF111827),
        accent: Color(0xFFEF4444),
        cardLight: Color(0xFF7F1D1D),
        cardDark: Color(0xFF450A0A),
      );
    case _WorldTheme.ruins:
      return const _WorldPalette(
        sky: Color(0xFFE5E7EB),
        ground: Color(0xFF9CA3AF),
        groundShadow: Color(0xFF6B7280),
        accent: Color(0xFF6B4226),
        cardLight: Color(0xFF1F2937),
        cardDark: Color(0xFF111827),
      );
  }
}

IconData _iconFor(_WorldTheme t) {
  switch (t) {
    case _WorldTheme.island:
      return Icons.beach_access_rounded;
    case _WorldTheme.desert:
      return Icons.wb_sunny_rounded;
    case _WorldTheme.jungle:
      return Icons.park_rounded;
    case _WorldTheme.volcano:
      return Icons.local_fire_department_rounded;
    case _WorldTheme.ruins:
      return Icons.account_balance_rounded;
  }
}

// ────────────────────────────────────────────────────────────────────
// Map painter (isometric tile map)
// ────────────────────────────────────────────────────────────────────

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.world,
    required this.player,
    required this.treasures,
    required this.phase,
  });

  final _World world;
  final Offset player;
  final List<_Treasure> treasures;
  final _TreasurePhase phase;

  // Cached paints/path reused every frame instead of reallocating.
  static final Paint _skyPaint = Paint();
  static final Paint _tileFill = Paint();
  static final Paint _tileStroke = Paint()
    ..color = const Color(0x55111127)
    ..strokeWidth = 0.8
    ..style = PaintingStyle.stroke;
  static final Paint _trunkPaint = Paint()
    ..color = const Color(0xFF92400E)
    ..strokeWidth = 6
    ..strokeCap = StrokeCap.round;
  static final Paint _leafPaint = Paint()
    ..color = const Color(0xFF15803D)
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round;
  static final Paint _waterPaint = Paint()..color = const Color(0xFF1D4ED8);
  static final Paint _lavaPaint = Paint()..color = const Color(0xFFFB923C);
  static final Paint _goldRingPaint = Paint()
    ..color = const Color(0xFFFCD34D)
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;
  static final Paint _blackStroke = Paint()
    ..color = const Color(0xFF111827)
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;
  static final Paint _playerBody = Paint()
    ..color = const Color(0xFFFCD34D);
  static final Paint _playerDot = Paint()
    ..color = const Color(0xFF111827);
  static final Paint _pyramidFill = Paint()..color = const Color(0xFFCA8A04);
  static final Paint _pyramidStroke = Paint()
    ..color = const Color(0xFF92400E)
    ..strokeWidth = 1.4
    ..style = PaintingStyle.stroke;
  static final Paint _tree1 = Paint()..color = const Color(0xFF166534);
  static final Paint _tree2 = Paint()..color = const Color(0xFF15803D);
  static final Paint _tree3 = Paint()..color = const Color(0xFF22C55E);
  static final Paint _treeTrunk = Paint()..color = const Color(0xFF92400E);
  static final Paint _volcanoCone = Paint()..color = const Color(0xFF374151);
  static final Paint _volcanoCaldera = Paint()..color = const Color(0xFFEF4444);
  static final Paint _volcanoFlame = Paint()..color = const Color(0xFFF59E0B);
  static final Paint _colShaft = Paint()..color = const Color(0xFFD9D9D9);
  static final Paint _colCap = Paint()..color = const Color(0xFF9CA3AF);
  static final Paint _colBase = Paint()..color = const Color(0xFF6B7280);
  static final Paint _goldBand = Paint()..color = const Color(0xFFFCD34D);
  static final Paint _dugPit = Paint()..color = const Color(0xFF111827);
  static final Paint _chestShadow = Paint()
    ..color = Color(0x66000000);
  static final Paint _chestFill = Paint();
  static final Paint _haloActive = Paint()
    ..color = const Color(0x33FCD34D);
  static final Paint _playerShadow = Paint()
    ..color = Color(0x66000000);
  static final Path _tilePath = Path();

  // Sky-gradient shader is keyed by (size, palette) so the same frame
  // re-renders don't reallocate it. Holds the most recent shader.
  Size? _skySize;
  int? _skyKey;
  Shader? _skyShader;

  @override
  void paint(Canvas canvas, Size size) {
    final palette = _paletteFor(world.theme);
    final skyMid = Color.lerp(palette.sky, palette.ground, 0.45)!;
    final skyKey = identityHashCode(palette) ^ identityHashCode(skyMid);
    if (_skyShader == null || _skySize != size || _skyKey != skyKey) {
      _skyShader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [palette.sky, skyMid],
      ).createShader(Offset.zero & size);
      _skySize = size;
      _skyKey = skyKey;
    }
    _skyPaint.shader = _skyShader;
    canvas.drawRect(Offset.zero & size, _skyPaint);

    // Iso grid (8 cols × 12 rows) — diamonds for each tile.
    const cols = 8;
    const rows = 12;
    final tileW = size.width / (cols + 2);
    final tileH = tileW * 0.55;
    final ox = size.width / 2;
    final oy = size.height * 0.16;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final dx = (c - cols / 2 + 0.5) * tileW;
        final dy = (r - rows / 2 + 0.5) * tileH;
        final cx = ox + dx;
        final cy = oy + dy + r * tileH * 0.5;
        _tilePath
          ..reset()
          ..moveTo(cx, cy - tileH / 2)
          ..lineTo(cx + tileW / 2, cy)
          ..lineTo(cx, cy + tileH / 2)
          ..lineTo(cx - tileW / 2, cy)
          ..close();
        _tileFill.color = Color.lerp(
          palette.ground,
          palette.groundShadow,
          ((c + r) % 2 == 0) ? 0.0 : 0.15,
        )!;
        canvas.drawPath(_tilePath, _tileFill);
        _tileStroke.color = palette.groundShadow.withValues(alpha: 0.30);
        canvas.drawPath(_tilePath, _tileStroke);
      }
    }

    _drawScenery(canvas, size, palette);

    for (final t in treasures) {
      _drawTreasure(
        canvas,
        Offset(t.position.dx * size.width, t.position.dy * size.height),
        t,
        palette,
      );
    }

    _drawPlayer(
      canvas,
      Offset(player.dx * size.width, player.dy * size.height),
      palette,
    );
  }

  void _drawScenery(Canvas canvas, Size size, _WorldPalette p) {
    switch (world.theme) {
      case _WorldTheme.island:
        for (var i = 0; i < 4; i++) {
          final x = size.width * (0.10 + i * 0.26);
          _drawPalm(canvas, Offset(x, size.height * 0.30));
        }
        canvas.drawRect(
          Rect.fromLTWH(0, size.height * 0.86, size.width, size.height * 0.14),
          _waterPaint,
        );
        break;
      case _WorldTheme.desert:
        for (var i = 0; i < 3; i++) {
          final x = size.width * (0.18 + i * 0.30);
          _drawPyramid(canvas, Offset(x, size.height * 0.34));
        }
        break;
      case _WorldTheme.jungle:
        for (var i = 0; i < 4; i++) {
          final x = size.width * (0.10 + i * 0.27);
          _drawTree(canvas, Offset(x, size.height * 0.28));
        }
        break;
      case _WorldTheme.volcano:
        _drawVolcano(canvas, Offset(size.width / 2, size.height * 0.36));
        canvas.drawCircle(
          Offset(size.width * 0.20, size.height * 0.70),
          size.width * 0.18,
          _lavaPaint,
        );
        canvas.drawCircle(
          Offset(size.width * 0.78, size.height * 0.78),
          size.width * 0.22,
          _lavaPaint,
        );
        break;
      case _WorldTheme.ruins:
        for (var i = 0; i < 3; i++) {
          final x = size.width * (0.15 + i * 0.32);
          _drawColumn(canvas, Offset(x, size.height * 0.34));
        }
        break;
    }
  }

  void _drawPalm(Canvas canvas, Offset c) {
    canvas.drawLine(c, c + const Offset(0, 28), _trunkPaint);
    for (var i = 0; i < 5; i++) {
      final a = -1.5 + i * 0.6;
      final tip = c + Offset(20 * cos(a), 6 * sin(a));
      canvas.drawLine(c, tip, _leafPaint);
    }
  }

  void _drawPyramid(Canvas canvas, Offset c) {
    final path = _tilePath
      ..reset()
      ..moveTo(c.dx, c.dy)
      ..lineTo(c.dx - 22, c.dy + 32)
      ..lineTo(c.dx + 22, c.dy + 32)
      ..close();
    canvas.drawPath(path, _pyramidFill);
    canvas.drawPath(path, _pyramidStroke);
  }

  void _drawTree(Canvas canvas, Offset c) {
    canvas.drawCircle(c, 14, _tree1);
    canvas.drawCircle(c + const Offset(8, -4), 12, _tree2);
    canvas.drawCircle(c + const Offset(-6, 6), 10, _tree3);
    canvas.drawRect(
      Rect.fromCenter(center: c + const Offset(0, 22), width: 6, height: 18),
      _treeTrunk,
    );
  }

  void _drawVolcano(Canvas canvas, Offset c) {
    final cone = _tilePath
      ..reset()
      ..moveTo(c.dx - 60, c.dy + 40)
      ..lineTo(c.dx - 16, c.dy - 10)
      ..lineTo(c.dx + 60, c.dy + 40)
      ..close();
    canvas.drawPath(cone, _volcanoCone);
    canvas.drawOval(
      Rect.fromCenter(center: c + const Offset(0, -8), width: 28, height: 8),
      _volcanoCaldera,
    );
    canvas.drawPath(
      _tilePath
        ..reset()
        ..moveTo(c.dx - 4, c.dy - 16)
        ..lineTo(c.dx, c.dy - 28)
        ..lineTo(c.dx + 4, c.dy - 16)
        ..close(),
      _volcanoFlame,
    );
  }

  void _drawColumn(Canvas canvas, Offset c) {
    canvas.drawRect(
      Rect.fromCenter(center: c, width: 12, height: 36),
      _colShaft,
    );
    canvas.drawRect(
      Rect.fromCenter(center: c + const Offset(0, -22), width: 18, height: 8),
      _colCap,
    );
    canvas.drawRect(
      Rect.fromCenter(center: c + const Offset(0, 22), width: 18, height: 8),
      _colBase,
    );
  }

  void _drawTreasure(
      Canvas canvas, Offset c, _Treasure t, _WorldPalette p) {
    if (t.found) {
      canvas.drawCircle(c, 16, _dugPit);
      canvas.drawCircle(c, 16, _goldRingPaint);
      return;
    }
    if (phase == _TreasurePhase.play || phase == _TreasurePhase.hint) {
      canvas.drawCircle(c, 26, _haloActive);
    }
    canvas.drawRect(
      Rect.fromCenter(center: c + const Offset(0, 1), width: 22, height: 18),
      _chestShadow,
    );
    _chestFill.color = _chestColor(t.kind);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: 22, height: 18),
        const Radius.circular(4),
      ),
      _chestFill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(c.dx - 11, c.dy - 4, 22, 6),
        const Radius.circular(3),
      ),
      _goldBand,
    );
    canvas.drawCircle(c, 2.5, _playerDot);
  }

  Color _chestColor(_TreasureKind k) {
    switch (k) {
      case _TreasureKind.chest:
        return const Color(0xFF92400E);
      case _TreasureKind.coin:
        return const Color(0xFFF59E0B);
      case _TreasureKind.gem:
        return const Color(0xFF0EA5E9);
      case _TreasureKind.crown:
        return const Color(0xFFFCD34D);
      case _TreasureKind.map:
        return const Color(0xFF65A30D);
      case _TreasureKind.key:
        return const Color(0xFF6B7280);
    }
  }

  void _drawPlayer(Canvas canvas, Offset c, _WorldPalette p) {
    canvas.drawCircle(c + const Offset(0, 2), 14, _playerShadow);
    canvas.drawCircle(c, 14, _playerBody);
    canvas.drawCircle(c, 14, _blackStroke);
    canvas.drawCircle(c, 4, _playerDot);
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.player != player ||
      old.phase != phase ||
      old.world != world ||
      old.treasures.length != treasures.length ||
      !_treasuresEqual(old.treasures, treasures);

  static bool _treasuresEqual(List<_Treasure> a, List<_Treasure> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].found != b[i].found || a[i].position != b[i].position) {
        return false;
      }
    }
    return true;
  }
}

// ────────────────────────────────────────────────────────────────────
// Treasure icon painter (used in collection screen)
// ────────────────────────────────────────────────────────────────────

class _TreasureIconPainter extends CustomPainter {
  _TreasureIconPainter({required this.kind});

  final _TreasureKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.4;
    final bg = Paint()..color = const Color(0xFF1F2937);
    canvas.drawCircle(c, r * 1.05, bg);
    switch (kind) {
      case _TreasureKind.coin:
        canvas.drawCircle(c, r * 0.7, Paint()..color = const Color(0xFFFCD34D));
        canvas.drawCircle(
            c, r * 0.7, Paint()..color = const Color(0xFF92400E)..style = PaintingStyle.stroke..strokeWidth = 2);
        break;
      case _TreasureKind.gem:
        final gem = Path()
          ..moveTo(c.dx, c.dy - r * 0.7)
          ..lineTo(c.dx + r * 0.6, c.dy)
          ..lineTo(c.dx, c.dy + r * 0.7)
          ..lineTo(c.dx - r * 0.6, c.dy)
          ..close();
        canvas.drawPath(gem, Paint()..color = const Color(0xFF0EA5E9));
        canvas.drawPath(
          gem,
          Paint()
            ..color = const Color(0xFF1E40AF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        break;
      case _TreasureKind.crown:
        final crown = Path()
          ..moveTo(c.dx - r * 0.7, c.dy + r * 0.2)
          ..lineTo(c.dx - r * 0.7, c.dy - r * 0.4)
          ..lineTo(c.dx - r * 0.35, c.dy)
          ..lineTo(c.dx, c.dy - r * 0.55)
          ..lineTo(c.dx + r * 0.35, c.dy)
          ..lineTo(c.dx + r * 0.7, c.dy - r * 0.4)
          ..lineTo(c.dx + r * 0.7, c.dy + r * 0.2)
          ..close();
        canvas.drawPath(crown, Paint()..color = const Color(0xFFFCD34D));
        canvas.drawPath(
          crown,
          Paint()
            ..color = const Color(0xFF7C2D12)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        break;
      case _TreasureKind.map:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: r * 1.2, height: r * 0.95),
            const Radius.circular(4),
          ),
          Paint()..color = const Color(0xFFFCD34D),
        );
        canvas.drawLine(
          c + Offset(-r * 0.5, 0),
          c + Offset(r * 0.5, 0),
          Paint()
            ..color = const Color(0xFF7C2D12)
            ..strokeWidth = 1.5,
        );
        break;
      case _TreasureKind.key:
        canvas.drawCircle(
          c + Offset(-r * 0.3, 0),
          r * 0.25,
          Paint()..color = const Color(0xFFFCD34D),
        );
        canvas.drawRect(
          Rect.fromLTWH(c.dx - r * 0.1, c.dy - 2, r * 0.8, 4),
          Paint()..color = const Color(0xFFFCD34D),
        );
        break;
      case _TreasureKind.chest:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: r * 1.4, height: r * 1.0),
            const Radius.circular(4),
          ),
          Paint()..color = const Color(0xFF92400E),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(c.dx - r * 0.7, c.dy - r * 0.45, r * 1.4, r * 0.35),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xFFFCD34D),
        );
        break;
    }
  }

  @override
  bool shouldRepaint(_TreasureIconPainter old) => old.kind != kind;
}