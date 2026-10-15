import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// **Typing Race** — ported from
/// `downloaded_games/games/typing_race/game.py`.
///
/// 2P pass-and-play race to type a paragraph. Per-character input —
/// wrong chars don't advance and an error flash lights up; backspace
/// is ignored (matching the python source's strict typing model).
///
/// Modes:
///   * speed    → winner is whoever finishes faster
///   * accuracy → wrong char resets your progress; winner = faster
///                 completion
///   * both     → combined WPM + accuracy score
///
/// Difficulty scales with level: easy → medium → hard sentence pools.
///
/// Input is via the **system soft keyboard** (same one the user types
/// into WhatsApp / Messenger with). We mount a transparent focused
/// [TextField] when typing starts so the OS keyboard auto-appears; on
/// desktop / web the hardware keyboard flows through the same
/// controller.
class TypingRaceGame extends MiniGame {
  const TypingRaceGame({
    super.key,
    required super.callbacks,
    this.level = 1,
  });

  /// 1 = easy pool, 2 = medium pool, 3 = hard pool (else round-robin).
  final int level;

  @override
  State<TypingRaceGame> createState() => _TypingRaceGameState();
}

enum _TRMode { speed, accuracy, both }
enum _TRState { menu, ready, typing, resultP1, resultP2, finalResult }

class _TypingRaceGameState extends MiniGameState<TypingRaceGame> {
  _TRMode _mode = _TRMode.speed;
  _TRState _state = _TRState.menu;

  String _targetText = '';
  String _typedText = '';

  DateTime? _startTime;
  DateTime? _endTime;

  int _errorFlash = 0; // ticks remaining for the wrong-char flash
  int _countdown = 0;
  DateTime? _countdownStart;
  _TRState? _countdownNext;

  _Result? _p1;
  _Result? _p2;
  String _winnerLabel = '';
  Color _winnerColor = Colors.white;

  static const Color _bg = Color(0xFF0C0C16);
  static const Color _panel = Color(0xFF161628);
  static const Color _accent = Color(0xFF00E6FF);
  static const Color _green = Color(0xFF00E678);
  static const Color _red = Color(0xFFFF3C3C);
  static const Color _yellow = Color(0xFFFFD700);
  static const Color _white = Color(0xFFF0F0FF);
  static const Color _grey = Color(0xFF78788C);
  static const Color _p1Color = Color(0xFF00B4FF);
  static const Color _p2Color = Color(0xFFFF5078);

  Timer? _tickTimer;

  // ─── Focus nodes for the (invisible) TextField that drives the
  //     system keyboard. We rebind to a new node each typing round so
  //     the IME connection cleanly resets. ────────────────────────
  final TextEditingController _imeCtrl = TextEditingController();
  final FocusNode _imeFocus = FocusNode(debugLabel: 'typing-ime');

  // ─── English text pool (subset of python source). ─────────────────────
  static const List<String> _easyPool = <String>[
    "The sun rises in the east and sets in the west, painting the sky with beautiful shades of orange and pink every single day. Nature has its own way of showing us the beauty of life. Take a moment to appreciate the small things around you.",
    "Walking through the park on a sunny afternoon can be one of the most relaxing experiences. You can hear the birds singing, feel the gentle breeze on your face, and see children playing happily on the green grass. It is a perfect day.",
    "Reading books is a wonderful habit that opens up new worlds. Whether it is fiction, history, or science, every book holds a treasure of knowledge. Taking time to read every day improves your vocabulary and broadens your perspective.",
    "Learning a new skill can be challenging at first, but with practice, it becomes easier. Consistency is the key to success. Do not be afraid to make mistakes, because they are stepping stones to mastering whatever you are trying to learn.",
    "Cooking at home can be both fun and rewarding. You get to choose your own ingredients and experiment with different flavors. Plus, sharing a home-cooked meal with family and friends creates beautiful memories around the dinner table.",
  ];

  static const List<String> _mediumPool = <String>[
    "The industrial revolution marked a major turning point in history. Almost every aspect of daily life was influenced in some way. Average income and population began to exhibit unprecedented sustained growth. Factories replaced hand tools, and steam engines transformed transportation.",
    "Space exploration has always fascinated humanity. From the first moon landing to the deployment of rovers on Mars, our understanding of the universe continues to expand. Telescopes capture breathtaking images of distant galaxies, proving just how small our world really is.",
    "Artificial intelligence is rapidly changing the landscape of technology and business. Machine learning algorithms can analyze vast amounts of data to predict trends, automate repetitive tasks, and even generate creative content. However, this progress also brings up important ethical discussions.",
    "Climate change is a pressing global issue that requires immediate action. The increasing levels of greenhouse gases are causing temperatures to rise, melting ice caps, and leading to extreme weather patterns. Transitioning to renewable energy sources is crucial.",
    "Effective communication is the cornerstone of any successful organization. Whether it is written emails, formal presentations, or casual team meetings, conveying your ideas clearly prevents misunderstandings. Active listening is equally important.",
  ];

  static const List<String> _hardPool = <String>[
    "Photosynthesis is the fundamental biological process by which green plants, algae, and certain bacteria transform light energy into chemical energy. During this process, carbon dioxide and water are converted into glucose and oxygen, utilizing sunlight absorbed by chlorophyll.",
    "The theory of general relativity, published by Albert Einstein in 1915, revolutionized our understanding of gravity. Unlike classical mechanics, relativity describes it as the curvature of spacetime caused by the presence of mass and energy, successfully predicting phenomena such as the bending of light by massive objects.",
    "Navigating the complexities of international trade law requires a deep understanding of bilateral agreements, tariffs, and customs regulations. Corporations expanding globally must ensure compliance with the World Trade Organization standards while adapting to local legal frameworks.",
    "Quantum computing represents a monumental leap forward in computational capabilities. By leveraging the principles of quantum mechanics, such as superposition and entanglement, quantum computers can process complex algorithms exponentially faster than classical supercomputers.",
    "Epidemiological modeling plays a critical role in public health management during infectious disease outbreaks. By utilizing complex mathematical frameworks, such as the Susceptible-Infectious-Recovered model, researchers can simulate the potential spread of pathogens.",
  ];

  String _pickText() {
    final pool = widget.level >= 3
        ? _hardPool
        : (widget.level == 2 ? _mediumPool : _easyPool);
    return pool[Random().nextInt(pool.length)];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(0);
      _updateStats();
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _imeCtrl.dispose();
    _imeFocus.dispose();
    super.dispose();
  }

  void _updateStats() {
    String label;
    switch (_state) {
      case _TRState.menu:
        label = 'Mode: ${_modeLabel(_mode)} · Pick a mode and start';
        break;
      case _TRState.ready:
        label = 'Get ready! $_countdown';
        break;
      case _TRState.typing:
        final elapsed = _startTime == null
            ? 0
            : DateTime.now().difference(_startTime!).inSeconds;
        label =
            'P${_p1 == null ? "1" : "2"} typing · ${_modeLabel(_mode)} · ${elapsed}s';
        break;
      case _TRState.resultP1:
        label =
            'P1 done — ${_p1?.wpm.toStringAsFixed(1) ?? "?"} WPM · ${_p1?.accuracy.toStringAsFixed(0) ?? "?"}%';
        break;
      case _TRState.resultP2:
        label = 'P2 typing…';
        break;
      case _TRState.finalResult:
        label =
            '$_winnerLabel · ${_p1?.wpm.toStringAsFixed(1)} vs ${_p2?.wpm.toStringAsFixed(1)} WPM';
        break;
    }
    reportStats(label);
  }

  String _modeLabel(_TRMode m) => m == _TRMode.speed
      ? 'Speed'
      : (m == _TRMode.accuracy ? 'Accuracy' : 'Speed+Acc');

  void _startCountdown(_TRState next) {
    setState(() {
      _countdown = 3;
      _countdownStart = DateTime.now();
      _countdownNext = next;
      _state = _TRState.ready;
    });
    _updateStats();
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (!mounted) return;
      if (_countdownStart == null || _countdownNext == null) return;
      final elapsed =
          DateTime.now().difference(_countdownStart!).inMilliseconds;
      final newCount = 3 - (elapsed ~/ 1000);
      if (newCount != _countdown) {
        setState(() => _countdown = newCount.clamp(0, 3));
        if (_countdown <= 0) {
          t.cancel();
          _beginTyping(_countdownNext!);
        }
      }
    });
  }

  void _beginTyping(_TRState typingState) {
    setState(() {
      _typedText = '';
      _startTime = DateTime.now();
      _endTime = null;
      _errorFlash = 0;
      if (typingState == _TRState.typing) {
        // P1 typing
        _targetText = _pickText();
        _p1 = null;
        _state = _TRState.typing;
      } else {
        // P2 typing
        _targetText = _pickText();
        _p2 = null;
        _state = _TRState.typing;
      }
    });
    // Reset the IME buffer and request focus so the system soft
    // keyboard appears immediately.
    _imeCtrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _imeFocus.requestFocus();
    });
    _updateStats();
  }

  _Result _computeResult() {
    final elapsed = _endTime!.difference(_startTime!);
    final typed = _typedText;
    final target = _targetText;
    final words =
        typed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final mins = max(elapsed.inMilliseconds / 60000, 0.001);
    final wpm = words / mins;
    final correct =
        typed.characters.where((c) => true).toList().asMap().entries.where((e) {
      final i = e.key;
      return i < target.length && target[i] == e.value;
    }).length;
    final acc = target.isEmpty
        ? 100.0
        : (correct / target.length * 100).clamp(0, 100).toDouble();
    return _Result(wpm: wpm, accuracy: acc, elapsedMs: elapsed.inMilliseconds);
  }

  void _finishTyping() {
    _endTime = DateTime.now();
    final result = _computeResult();
    setState(() {
      if (_p1 == null) {
        _p1 = result;
        _state = _TRState.resultP1;
      } else {
        _p2 = result;
        _state = _TRState.finalResult;
        _determineWinner();
      }
    });
    // Release IME focus so the soft keyboard hides for the result
    // screens.
    _imeFocus.unfocus();
    haptic(HapticFeedbackType.medium);
    reportScore(result.wpm.round() * 10);
    _updateStats();
    if (_state == _TRState.finalResult) {
      reportGameOver();
    }
  }

  void _determineWinner() {
    if (_p1 == null || _p2 == null) return;
    final r1 = _p1!;
    final r2 = _p2!;
    int winner; // 1 or 2
    switch (_mode) {
      case _TRMode.accuracy:
        winner = r1.elapsedMs <= r2.elapsedMs ? 1 : 2;
        break;
      case _TRMode.speed:
        winner = r1.wpm >= r2.wpm ? 1 : 2;
        break;
      case _TRMode.both:
        final maxWpm = max(r1.wpm, r2.wpm);
        final s1 = 0.5 * (r1.wpm / (maxWpm == 0 ? 1 : maxWpm)) +
            0.5 * (r1.accuracy / 100);
        final s2 = 0.5 * (r2.wpm / (maxWpm == 0 ? 1 : maxWpm)) +
            0.5 * (r2.accuracy / 100);
        winner = s1 >= s2 ? 1 : 2;
        break;
    }
    if (winner == 1) {
      _winnerLabel = 'Player 1 Wins!';
      _winnerColor = _p1Color;
    } else {
      _winnerLabel = 'Player 2 Wins!';
      _winnerColor = _p2Color;
    }
  }

  /// Forward a character (or string) into the typing pipeline. The
  /// character came from either the IME text-field changes (mobile
  /// soft-keyboard) or a hardware key event (desktop / web).
  void _handleChar(String ch) {
    if (_state != _TRState.typing) return;
    if (ch.isEmpty) return;
    final pos = _typedText.length;
    if (pos >= _targetText.length) return;

    if (ch == _targetText[pos]) {
      setState(() {
        _typedText += ch;
      });
      if (_typedText.length >= _targetText.length) {
        _finishTyping();
      }
    } else {
      setState(() {
        _errorFlash = 12;
        if (_mode == _TRMode.accuracy) {
          _typedText = '';
        }
      });
      haptic(HapticFeedbackType.heavy);
    }
  }

  /// Hardware / IME backspace is ignored in classic typing-race
  /// (matches the original python source); surface a small flash so
  /// the user knows the press registered.
  void _handleBackspace() {
    if (_state != _TRState.typing) return;
    setState(() => _errorFlash = 6);
    haptic(HapticFeedbackType.selection);
  }

  /// Hardware keyboard path for desktop / web. Soft-keyboard goes
  /// through [onImeChanged] below.
  void _onHardwareKey(KeyDownEvent event) {
    if (_state != _TRState.typing) return;
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _handleBackspace();
      return;
    }
    final ch = event.character;
    if (ch == null || ch.isEmpty) return;
    _handleChar(ch);
  }

  /// Soft-keyboard callback. The text-field reports the entire buffer
  /// after each change; we diff to the previous buffer and forward
  /// only the appended characters.
  void _onImeChanged(String value) {
    if (_state != _TRState.typing) return;
    if (value == _typedText) return;
    if (value.length > _typedText.length) {
      // Forward every newly-typed character.
      for (var i = _typedText.length; i < value.length; i++) {
        _handleChar(value[i]);
      }
    } else if (value.length < _typedText.length) {
      // Soft keyboard may have emitted a backspace event. Keep our
      // model authoritative — reset the IME buffer back to ours.
      _imeCtrl.value = TextEditingValue(
        text: _typedText,
        selection: TextSelection.collapsed(offset: _typedText.length),
      );
      _handleBackspace();
    }
  }

  void _startMatch() {
    setState(() {
      _p1 = null;
      _p2 = null;
      _winnerLabel = '';
    });
    _startCountdown(_TRState.typing);
  }

  void _nextPlayer() {
    _startCountdown(_TRState.resultP2); // dummy — will route to typing
    setState(() {
      _state = _TRState.ready;
    });
  }

  void _goMenu() {
    _imeFocus.unfocus();
    setState(() {
      _state = _TRState.menu;
      _typedText = '';
      _targetText = '';
    });
    _updateStats();
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: SafeArea(
        bottom: false,
        child: switch (_state) {
          _TRState.menu => _buildMenu(),
          _TRState.ready => _buildCountdown(),
          _TRState.typing => _buildTyping(),
          _TRState.resultP1 => _buildResultP1(),
          _TRState.resultP2 => _buildTyping(),
          _TRState.finalResult => _buildFinal(),
        },
      ),
    );
  }

  Widget _buildMenu() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Big visual removed — host HUD already shows the title.
          const Spacer(),
          const Text(
            'Pick a mode, then race to type the paragraph.\nWrong characters reset your streak (in Accuracy mode) or just flash red.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _white, fontSize: 13),
          ),
          const SizedBox(height: 24),
          const Text(
            'MODE',
            style: TextStyle(
              color: _grey,
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final m in _TRMode.values) ...[
                Expanded(
                  child: _modeChip(m),
                ),
                if (m != _TRMode.values.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _startMatch,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('START RACE'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: const Color(0xFF002030),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _modeChip(_TRMode m) {
    final selected = _mode == m;
    return GestureDetector(
      onTap: () => setState(() => _mode = m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.18) : _panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _accent : Colors.white12,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            _modeLabel(m),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? _accent : _white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCountdown() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _countdown > 0 ? '$_countdown' : 'GO!',
            style: TextStyle(
              color: _countdown > 0 ? _accent : _green,
              fontSize: 96,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _p1 == null ? 'Player 1 — get ready' : 'Player 2 — get ready',
            style: const TextStyle(color: _white, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildTyping() {
    // KeyboardListener for hardware keyboards (desktop / web).
    // TextField below drives the system soft keyboard on mobile.
    return KeyboardListener(
      focusNode: FocusNode(skipTraversal: true),
      onKeyEvent: (e) => e is KeyDownEvent ? _onHardwareKey(e) : null,
      child: GestureDetector(
        // Tap anywhere in the typing area to re-show the soft keyboard
        // if the user dismissed it.
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_state == _TRState.typing) _imeFocus.requestFocus();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Player turn badge.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: (_p1 == null ? _p1Color : _p2Color)
                          .withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _p1 == null ? _p1Color : _p2Color,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      _p1 == null ? 'Player 1 typing' : 'Player 2 typing',
                      style: TextStyle(
                        color: _p1 == null ? _p1Color : _p2Color,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Paragraph display.
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _errorFlash > 0
                        ? _red.withValues(alpha: 0.18)
                        : _panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _errorFlash > 0 ? _red : Colors.white12,
                      width: _errorFlash > 0 ? 2 : 1,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: _buildHighlightedText(),
                  ),
                ),
              ),
              if (_errorFlash > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    '⚠ Wrong character!',
                    style: const TextStyle(
                      color: _red,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 10),
              // Tap-to-type hint + invisible IME-driving TextField.
              Center(
                child: Text(
                  'Tap here and type with your keyboard',
                  style: TextStyle(
                    color: _grey.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              // Hidden but focused TextField — the system soft keyboard
              // appears while this has focus. We set the controller's
              // text to mirror our model after each handle.
              Opacity(
                opacity: 0.0,
                child: TextField(
                  controller: _imeCtrl,
                  focusNode: _imeFocus,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  // Permit long passages; the soft-keyboard user is
                  // constrained by the screen anyway.
                  maxLines: 1,
                  onChanged: _onImeChanged,
                  style: const TextStyle(color: Colors.transparent),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedText() {
    final span = TextSpan(
      children: [
        for (var i = 0; i < _targetText.length; i++)
          TextSpan(
            text: _targetText[i],
            style: TextStyle(
              color: i < _typedText.length
                  ? _green
                  : (i == _typedText.length ? _yellow : _grey),
              fontSize: 22,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              height: 1.4,
            ),
          ),
      ],
    );
    return RichText(text: span);
  }

  Widget _buildResultP1() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'PLAYER 1 — DONE',
            style: TextStyle(
              color: _p1Color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _resultCard('Player 1', _p1!, _p1Color),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _nextPlayer,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('PLAYER 2 — START'),
              style: FilledButton.styleFrom(
                backgroundColor: _p2Color,
                foregroundColor: const Color(0xFF20000A),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinal() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _winnerLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _winnerColor,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _resultCard('Player 1', _p1!, _p1Color)),
              const SizedBox(width: 12),
              Expanded(child: _resultCard('Player 2', _p2!, _p2Color)),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _goMenu,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('PLAY AGAIN'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: const Color(0xFF002030),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(String name, _Result r, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          _statRow('WPM', r.wpm.toStringAsFixed(1)),
          _statRow('Accuracy', '${r.accuracy.toStringAsFixed(0)}%'),
          _statRow('Time', '${(r.elapsedMs / 1000).toStringAsFixed(1)}s'),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _grey, fontSize: 12)),
          Text(
            value,
            style: const TextStyle(
              color: _white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Result {
  const _Result({
    required this.wpm,
    required this.accuracy,
    required this.elapsedMs,
  });
  final double wpm;
  final double accuracy;
  final int elapsedMs;
}
