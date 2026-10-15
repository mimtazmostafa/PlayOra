import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/settings_controller.dart';

/// Global sound-effect dispatcher.
///
/// Owns a single [AudioPlayer] in low-latency mode and exposes
/// semantic helpers (`playTap`, `playCardSlide`, ...) so callers don't
/// have to know asset paths. Every helper early-returns when the user
/// has toggled sound off in settings — toggling is hot-reactive
/// because the engine reads [soundOnProvider] inside every call.
///
/// Generated WAVs live in `assets/sfx/` (built by
/// `tools/generate_sfx.dart`).
class AudioEngine {
  AudioEngine();

  final AudioPlayer _player = AudioPlayer();

  /// Lazily-initialised on first use; per-call read so the toggle
  /// flips take effect instantly without rebuilding the engine.
  bool _ready = false;

  /// Per-sfx last-played timestamps. Used to throttle rapid-fire
  /// triggers (e.g. a balloon that escapes every frame would queue
  /// hundreds of buzzes and sound continuous). Each entry is the
  /// [DateTime] of the most recent play call for that sound; requests
  /// within [_minReplayGap] of the last one are dropped.
  final Map<_Sfx, DateTime> _lastPlayed = {};
  /// Cooldown between identical SFX plays. 120 ms covers two frames at
  /// 60 fps so a runaway loop cannot stack triggers into an effectively
  /// continuous buzz while still allowing intentional rapid-fire
  /// (e.g. multi-pop combos) to register.
  static const Duration _minReplayGap = Duration(milliseconds: 120);

  /// Serial queue of pending stop+play operations. Without this,
  /// concurrent calls interleave on the shared [AudioPlayer] and one
  /// call's `stop()` can cancel another's `play()` mid-load.
  Future<void> _playQueue = Future.value();

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setPlayerMode(PlayerMode.lowLatency);
    _ready = true;
  }

  Future<void> _play(bool enabled, _Sfx sfx) async {
    if (!enabled) return;
    final now = DateTime.now();
    final last = _lastPlayed[sfx];
    if (last != null && now.difference(last) < _minReplayGap) return;

    // Chain onto the previous play so concurrent callers don't race on
    // the shared player. The throttled timestamp is recorded up-front
    // so retry-storms don't bypass the gap; the chain awaits the
    // previous play to completion before starting the next.
    final completer = Completer<void>();
    _playQueue = _playQueue.then((_) async {
      try {
        await _ensureReady();
        await _player.stop();
        await _player.play(AssetSource(sfx.asset));
      } on Object {
        // Swallow playback errors silently — the game shouldn't crash
        // because of a missing codec on a specific device.
      } finally {
        completer.complete();
      }
    });
    _lastPlayed[sfx] = now;
    await completer.future;
  }

  Future<void> playTap(bool enabled) => _play(enabled, _Sfx.tap);
  Future<void> playCardSlide(bool enabled) => _play(enabled, _Sfx.cardSlide);
  Future<void> playTileDrop(bool enabled) => _play(enabled, _Sfx.tileDrop);
  Future<void> playWin(bool enabled) => _play(enabled, _Sfx.winChime);
  Future<void> playError(bool enabled) => _play(enabled, _Sfx.errorBuzz);
  Future<void> playPour(bool enabled) => _play(enabled, _Sfx.pour);

  Future<void> dispose() => _player.dispose();
}

/// Sound-effect manifest. `asset` is the path under `assets/` (no
/// leading slash, no `assets/` prefix).
enum _Sfx {
  tap('sfx/tap.wav'),
  cardSlide('sfx/card_slide.wav'),
  tileDrop('sfx/tile_drop.wav'),
  winChime('sfx/win_chime.wav'),
  errorBuzz('sfx/error_buzz.wav'),
  pour('sfx/pour.wav');

  const _Sfx(this.asset);
  final String asset;
}

/// Global engine instance — single shared player per app session.
final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = AudioEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Convenience: true when in-game audio is enabled.
///
/// Wraps [settingsControllerProvider] so call sites can read it
/// without needing to listen to the whole state object.
final soundOnProvider = Provider<bool>((ref) {
  return ref.watch(settingsControllerProvider.select((s) => s.soundOn));
});
