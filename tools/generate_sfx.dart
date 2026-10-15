// Generates 6 short PCM WAV files into ../assets/sfx/ for the AudioEngine.
//
// Usage:  dart run tools/generate_sfx.dart
//
// All sounds are mono, 22 050 Hz, 16-bit PCM. Total size < 100 KB so the
// binary stays slim. Each recipe is tuned by ear for a snappy, game-style
// feel — sine-based for taps/chimes, square wave for buzz, noise for pour.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const int _sampleRate = 22050;

void main() {
  final outDir = Directory('../assets/sfx');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  _writeWav(File('${outDir.path}/tap.wav'),       _tap(30));
  _writeWav(File('${outDir.path}/card_slide.wav'), _cardSlide(140));
  _writeWav(File('${outDir.path}/tile_drop.wav'),  _tileDrop(110));
  _writeWav(File('${outDir.path}/win_chime.wav'),  _winChime(620));
  _writeWav(File('${outDir.path}/error_buzz.wav'), _errorBuzz(170));
  _writeWav(File('${outDir.path}/pour.wav'),       _pour(280));

  stdout.writeln('Generated 6 WAV files into ${outDir.path}');
}

// ─── Synthesis primitives ─────────────────────────────────────────

/// Sample index → seconds.
double _t(int i) => i / _sampleRate;

/// Sine wave with amplitude 0..1.
double _sine(double freq, int i, {double phase = 0}) {
  return sin(2 * pi * freq * _t(i) + phase);
}

/// Square wave (-1..1) at the given fundamental frequency.
double _square(double freq, int i) {
  return sin(2 * pi * freq * _t(i)) >= 0 ? 1 : -1;
}

/// Simple linear attack/decay envelope (0 → 1 → 0 over length).
List<double> _envelope(int n, {double attack = 0.1, double release = 0.4}) {
  final at = (n * attack).clamp(1, n).toInt();
  final rt = (n * release).clamp(1, n).toInt();
  return List<double>.generate(n, (i) {
    if (i < at) return i / at;
    if (i > n - rt) return (n - i) / rt;
    return 1;
  }, growable: false);
}

/// Clip to int16 range.
int _clip(double v) => (v * 32767).round().clamp(-32768, 32767);

// ─── Sound recipes ────────────────────────────────────────────────

List<double> _tap(int ms) {
  // 30 ms 880 Hz sine, sharp envelope. Reads as a crisp "tick".
  final n = (_sampleRate * ms ~/ 1000);
  final env = _envelope(n, attack: 0.08, release: 0.6);
  return List<double>.generate(n, (i) {
    return 0.55 * env[i] * _sine(880, i);
  }, growable: false);
}

List<double> _cardSlide(int ms) {
  // 140 ms descending sweep 820 Hz → 380 Hz, soft envelope. Reads as
  // a paper-on-table whoosh.
  final n = (_sampleRate * ms ~/ 1000);
  final env = _envelope(n, attack: 0.18, release: 0.5);
  return List<double>.generate(n, (i) {
    final p = i / n;
    final freq = 820 - 440 * p;
    return 0.45 * env[i] * _sine(freq, i);
  }, growable: false);
}

List<double> _tileDrop(int ms) {
  // 110 ms 240 Hz → 90 Hz with quick decay. Reads as a wooden block hit.
  final n = (_sampleRate * ms ~/ 1000);
  final env = _envelope(n, attack: 0.04, release: 0.7);
  return List<double>.generate(n, (i) {
    final p = i / n;
    final freq = 240 - 150 * p;
    return 0.6 * env[i] * _sine(freq, i);
  }, growable: false);
}

List<double> _winChime(int ms) {
  // 620 ms C-E-G-C arpeggio (262, 330, 392, 523 Hz) with a sparkle tail.
  final n = (_sampleRate * ms ~/ 1000);
  final notes = [262.0, 330.0, 392.0, 523.0];
  final noteLen = n ~/ notes.length;
  return List<double>.generate(n, (i) {
    final idx = (i ~/ noteLen).clamp(0, notes.length - 1);
    final freq = notes[idx];
    final local = i - idx * noteLen;
    final atk = (noteLen * 0.15).clamp(1, noteLen).toInt();
    final env = local < atk ? local / atk : 1.0;
    // Slight detune overtone for sparkle.
    return 0.45 * env * (_sine(freq, i) + 0.25 * _sine(freq * 2, i));
  }, growable: false);
}

List<double> _errorBuzz(int ms) {
  // 170 ms square 110 Hz with detune, sharp envelope. Reads as "wrong".
  final n = (_sampleRate * ms ~/ 1000);
  final env = _envelope(n, attack: 0.05, release: 0.4);
  return List<double>.generate(n, (i) {
    return 0.5 * env[i] * (_square(110, i) + 0.3 * _square(108, i));
  }, growable: false);
}

List<double> _pour(int ms) {
  // 280 ms filtered noise burst with band-pass feel (frequency mix of
  // 1500 Hz sine + noise). Reads as a water pour.
  final n = (_sampleRate * ms ~/ 1000);
  final env = _envelope(n, attack: 0.18, release: 0.7);
  final rng = Random(42); // deterministic so files are stable across runs.
  return List<double>.generate(n, (i) {
    final noise = rng.nextDouble() * 2 - 1;
    final tone = _sine(1500, i, phase: pi / 3);
    return 0.45 * env[i] * (0.7 * noise + 0.3 * tone);
  }, growable: false);
}

// ─── WAV writer ───────────────────────────────────────────────────

/// Write a mono 16-bit PCM RIFF/WAVE file.
void _writeWav(File file, List<double> samples) {
  final pcm = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    pcm[i] = _clip(samples[i]);
  }
  final byteData = pcm.buffer.asUint8List();
  final dataLen = byteData.length;

  final builder = BytesBuilder(copy: false);
  // RIFF header.
  builder.add(_ascii('RIFF'));
  builder.add(_u32Le(36 + dataLen));
  builder.add(_ascii('WAVE'));
  // fmt chunk.
  builder.add(_ascii('fmt '));
  builder.add(_u32Le(16));               // chunk size
  builder.add(_u16Le(1));                // PCM format
  builder.add(_u16Le(1));                // mono
  builder.add(_u32Le(_sampleRate));      // sample rate
  builder.add(_u32Le(_sampleRate * 2));  // byte rate (mono * 16-bit)
  builder.add(_u16Le(2));                // block align
  builder.add(_u16Le(16));               // bits per sample
  // data chunk.
  builder.add(_ascii('data'));
  builder.add(_u32Le(dataLen));
  builder.add(byteData);

  file.writeAsBytesSync(builder.toBytes(), flush: true);
}

List<int> _ascii(String s) => s.codeUnits;
List<int> _u32Le(int v) => [
      v & 0xFF,
      (v >> 8) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 24) & 0xFF,
    ];
List<int> _u16Le(int v) => [v & 0xFF, (v >> 8) & 0xFF];
