// Visual identity preview harness.
//
// Run with:
//   flutter run -t dev_tools/preview/visual_identity_preview.dart -d <device>
//
// The app launches, waits ~2s for the first frame, rasterizes each tile via
// RepaintBoundary.toImage, writes the PNGs to
// dev_tools/preview/out/*.png, then exits cleanly.
//
// Output files:
//   playnest_logo_1024.png   — launcher icon, 1024×1024
//   playnest_logo_256.png    — splash tile, 256×256
//   splash_screen.png       — full splash screen mock at 360×640
//   icon_chess.png          — sample recipe: hexagon + chess-knight glyph
//   icon_block_blast.png    — sample recipe: roundedSquare + puzzle glyph
//   icon_wordle.png         — sample recipe: roundedSquare + "W" letterform glyph
//
// This is the user-gate deliverable. No app-wide wiring happens until the
// user has reviewed the PNGs.

import 'dart:io' show Directory, File;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:playnest/core/theme/app_colors.dart';
import 'package:playnest/core/visual_identity/game_icon_painter.dart';
import 'package:playnest/core/visual_identity/icon_recipe.dart';
import 'package:playnest/core/visual_identity/playnest_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait so the splash mockup has predictable dimensions.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  // Wire up a render boundary around each tile.
  final GlobalKey logoKey1024 = GlobalKey();
  final GlobalKey logoKey256 = GlobalKey();
  final GlobalKey splashKey = GlobalKey();
  final GlobalKey iconChessKey = GlobalKey();
  final GlobalKey iconBlockKey = GlobalKey();
  final GlobalKey iconWordleKey = GlobalKey();

  runApp(
    MaterialApp(
      title: 'PlayNest Visual Identity Preview',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: AppColors.primary,
        scaffoldBackgroundColor: Colors.white,
        textTheme: const TextTheme(),
      ),
      home: PreviewHarness(
        keys: <GlobalKey>[
          logoKey1024,
          logoKey256,
          splashKey,
          iconChessKey,
          iconBlockKey,
          iconWordleKey,
        ],
      ),
    ),
  );

  // Give the first frame a moment to lay out, then rasterize + write PNGs.
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  await _writePng(logoKey1024, 1024, 1024, 'playnest_logo_1024');
  await _writePng(logoKey256, 256, 256, 'playnest_logo_256');
  await _writePng(splashKey, 360, 640, 'splash_screen');
  await _writePng(iconChessKey, 256, 256, 'icon_chess');
  await _writePng(iconBlockKey, 256, 256, 'icon_block_blast');
  await _writePng(iconWordleKey, 256, 256, 'icon_wordle');

  // Rasterize the full launcher-icon set in one pass. Each density slot
  // shares a RepaintBoundary so the larger PNG is just an upscale of the
  // smaller one — cheap, deterministic.
  await _writeLauncherSet(logoKey1024);

  // Exit cleanly so the preview command terminates.
  await Future<void>.delayed(const Duration(milliseconds: 200));
  // ignore: avoid_print
  print('\nPreview PNGs written to dev_tools/preview/out/\n');
  // ignore: avoid_print
  print('Open them to review before app-wide wiring.\n');
}

class PreviewHarness extends StatelessWidget {
  const PreviewHarness({super.key, required this.keys});

  final List<GlobalKey> keys;

  static const String _placeholder =
      'PlayNest · Visual Identity Preview';

  @override
  Widget build(BuildContext context) {
    final GlobalKey k0 = keys[0];
    final GlobalKey k1 = keys[1];
    final GlobalKey k2 = keys[2];
    final GlobalKey k3 = keys[3];
    final GlobalKey k4 = keys[4];
    final GlobalKey k5 = keys[5];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      appBar: AppBar(
        title: const Text(_placeholder),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionTitle('App logo — launcher scale (1024 px)'),
            Center(
              child: RepaintBoundary(
                key: k0,
                child: _TileFrame(
                  size: const Size(1024, 1024),
                  child: const PlayNestLogo(size: 1024),
                ),
              ),
            ),
            const SizedBox(height: 32),
            _SectionTitle('App logo — splash tile scale (256 px)'),
            Center(
              child: RepaintBoundary(
                key: k1,
                child: _TileFrame(
                  size: const Size(256, 256),
                  child: const PlayNestLogo(size: 256),
                ),
              ),
            ),
            const SizedBox(height: 32),
            _SectionTitle('Full splash mock (360 × 640)'),
            Center(
              child: RepaintBoundary(
                key: k2,
                child: SizedBox(
                  width: 360,
                  height: 640,
                  child: const _SplashMock(),
                ),
              ),
            ),
            const SizedBox(height: 32),
            _SectionTitle('Sample recipe icons'),
            const Text(
              'Three example IconRecipe combinations chosen to span the '
              'shape + glyph vocabulary. These are the icons the user needs '
              'to approve before app-wide wiring.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 24,
              children: <Widget>[
                _IconTile(
                  key: k3,
                  label: 'Hexagon + chess-knight glyph',
                  caption: 'Hex · #4A1B9A · crown glyph',
                  recipe: const IconRecipe(
                    shape: IconRecipeShape.hexagon,
                    background: AppColors.primaryInk,
                    glyph: IconRecipeGlyph.crown,
                  ),
                ),
                _IconTile(
                  key: k4,
                  label: 'Rounded square + puzzle glyph',
                  caption: 'Square · #22C55E · puzzle',
                  recipe: const IconRecipe(
                    shape: IconRecipeShape.roundedSquare,
                    background: AppColors.secondary,
                    glyph: IconRecipeGlyph.puzzle,
                  ),
                ),
                _IconTile(
                  key: k5,
                  label: 'Shield + target glyph',
                  caption: 'Shield · #6C2BD9 · target',
                  recipe: const IconRecipe(
                    shape: IconRecipeShape.shield,
                    background: AppColors.primary,
                    glyph: IconRecipeGlyph.target,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1625),
        ),
      ),
    );
  }
}

class _TileFrame extends StatelessWidget {
  const _TileFrame({required this.size, required this.child});

  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: ColoredBox(color: Colors.white, child: child),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({
    super.key,
    required this.label,
    required this.caption,
    required this.recipe,
  });

  final String label;
  final String caption;
  final IconRecipe recipe;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 256,
          height: 256,
          child: GameIconTile(recipe: recipe, size: 256),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1625),
          ),
        ),
        Text(
          caption,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF4B4458),
          ),
        ),
      ],
    );
  }
}

/// Static (non-animated) splash mock — rasterizes deterministically.
class _SplashMock extends StatelessWidget {
  const _SplashMock();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppColors.primary,
            Color(0xFF4A1FA8),
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const PlayNestLogo(size: 120),
              const SizedBox(height: 20),
              const Text(
                'PlayNest',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'One Hub. Endless Play.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.82),
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 180,
                height: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: ColoredBox(color: Colors.white.withValues(alpha: 0.4)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _writePng(GlobalKey key, int w, int h, String name) async {
  try {
    final RenderObject? obj = key.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) return;
    final ui.Image image = await obj.toImage(pixelRatio: 1);
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final Directory outDir =
        Directory('dev_tools/preview/out');
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    final File file = File('${outDir.path}/$name.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    // ignore: avoid_print
    print('  ✓ wrote ${file.path}');
  } catch (e) {
    // ignore: avoid_print
    print('  ✗ failed to write $name.png: $e');
  }
}

/// Rasterize the launcher icon at every (px + density) the platform
/// expects: Android `mipmap-*` + iOS universal `AppIcon` set.
Future<void> _writeLauncherSet(GlobalKey logoKey) async {
  final Directory launcherDir =
      Directory('dev_tools/preview/out/launcher');
  if (!await launcherDir.exists()) {
    await launcherDir.create(recursive: true);
  }

  Future<void> writeSized(String name, int px) async {
    final RenderObject? obj = logoKey.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) return;
    final ui.Image image = await obj.toImage(pixelRatio: px / 1024);
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final File file = File('${launcherDir.path}/$name.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    // ignore: avoid_print
    print('  ✓ wrote ${file.path}');
  }

  // Android mipmap densities (square launcher).
  await writeSized('android/ic_launcher_mdpi', 48);
  await writeSized('android/ic_launcher_hdpi', 72);
  await writeSized('android/ic_launcher_xhdpi', 96);
  await writeSized('android/ic_launcher_xxhdpi', 144);
  await writeSized('android/ic_launcher_xxxhdpi', 192);

  // iOS universal AppIcon set.
  await writeSized('ios/Icon-App-20x20@1x', 20);
  await writeSized('ios/Icon-App-20x20@2x', 40);
  await writeSized('ios/Icon-App-20x20@3x', 60);
  await writeSized('ios/Icon-App-29x29@1x', 29);
  await writeSized('ios/Icon-App-29x29@2x', 58);
  await writeSized('ios/Icon-App-29x29@3x', 87);
  await writeSized('ios/Icon-App-40x40@1x', 40);
  await writeSized('ios/Icon-App-40x40@2x', 80);
  await writeSized('ios/Icon-App-40x40@3x', 120);
  await writeSized('ios/Icon-App-60x60@2x', 120);
  await writeSized('ios/Icon-App-60x60@3x', 180);
  await writeSized('ios/Icon-App-76x76@1x', 76);
  await writeSized('ios/Icon-App-76x76@2x', 152);
  await writeSized('ios/Icon-App-83.5x83.5@2x', 167);
  await writeSized('ios/Icon-App-1024x1024@1x', 1024);
}