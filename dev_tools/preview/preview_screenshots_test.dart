// Visual identity preview — test-based screenshot generator.
//
// Run with:
//   flutter test dev_tools/preview/preview_screenshots_test.dart
//
// The test rasterizes each tile to a PNG via `RepaintBoundary.toImage`
// and writes them to `dev_tools/preview/out/*.png`. The user opens those
// PNGs to review the logo + sample icons before app-wide wiring.

import 'dart:io' show Directory, File;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnest/core/theme/app_colors.dart';
import 'package:playnest/core/visual_identity/game_icon_painter.dart';
import 'package:playnest/core/visual_identity/icon_recipe.dart';
import 'package:playnest/core/visual_identity/playnest_logo.dart';

void main() {
  testWidgets('rasterize visual identity preview tiles', (tester) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GlobalKey logo1024Key = GlobalKey();
    final GlobalKey logo256Key = GlobalKey();
    final GlobalKey splashKey = GlobalKey();
    final GlobalKey chessKey = GlobalKey();
    final GlobalKey blockKey = GlobalKey();
    final GlobalKey targetKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                RepaintBoundary(
                  key: logo1024Key,
                  child: const SizedBox(
                    width: 1024,
                    height: 1024,
                    child: PlayNestLogo(size: 1024),
                  ),
                ),
                RepaintBoundary(
                  key: logo256Key,
                  child: const SizedBox(
                    width: 256,
                    height: 256,
                    child: PlayNestLogo(size: 256),
                  ),
                ),
                RepaintBoundary(
                  key: splashKey,
                  child: SizedBox(
                    width: 360,
                    height: 640,
                    child: const _SplashMock(),
                  ),
                ),
                RepaintBoundary(
                  key: chessKey,
                  child: const SizedBox(
                    width: 256,
                    height: 256,
                    child: GameIconTile(
                      size: 256,
                      recipe: IconRecipe(
                        shape: IconRecipeShape.hexagon,
                        background: AppColors.primaryInk,
                        glyph: IconRecipeGlyph.crown,
                      ),
                    ),
                  ),
                ),
                RepaintBoundary(
                  key: blockKey,
                  child: const SizedBox(
                    width: 256,
                    height: 256,
                    child: GameIconTile(
                      size: 256,
                      recipe: IconRecipe(
                        shape: IconRecipeShape.roundedSquare,
                        background: AppColors.secondary,
                        glyph: IconRecipeGlyph.puzzle,
                      ),
                    ),
                  ),
                ),
                RepaintBoundary(
                  key: targetKey,
                  child: const SizedBox(
                    width: 256,
                    height: 256,
                    child: GameIconTile(
                      size: 256,
                      recipe: IconRecipe(
                        shape: IconRecipeShape.shield,
                        background: AppColors.primary,
                        glyph: IconRecipeGlyph.target,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Two pumps deliver the first frame + the post-frame layer flush that
    // RepaintBoundary.toImage needs. pumpAndSettle would hang because the
    // SingleChildScrollView keeps requesting layout for offscreen children.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final Directory outDir = Directory('dev_tools/preview/out');
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    await _write(tester, logo1024Key, outDir.path, 'playnest_logo_1024');
    await _write(tester, logo256Key, outDir.path, 'playnest_logo_256');
    await _write(tester, splashKey, outDir.path, 'splash_screen');
    await _write(tester, chessKey, outDir.path, 'icon_chess');
    await _write(tester, blockKey, outDir.path, 'icon_block_blast');
    await _write(tester, targetKey, outDir.path, 'icon_target');

    // Launcher icon set — Android mipmap densities + iOS universal icons.
    // Rasterized from a fresh 1024 px RepaintBoundary, downscaled per slot.
    final Directory launcherDir =
        Directory('${outDir.path}/launcher');
    if (!await launcherDir.exists()) {
      await launcherDir.create(recursive: true);
    }

    Future<void> launcherSized(String name, int px) async {
      final RenderObject? obj =
          logo1024Key.currentContext?.findRenderObject();
      if (obj is! RenderRepaintBoundary) return;
      final ui.Image image = await obj.toImage(pixelRatio: px / 1024);
      final ByteData? bytes =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      await File('${launcherDir.path}/$name.png')
          .writeAsBytes(bytes.buffer.asUint8List());
      // ignore: avoid_print
      print('  wrote ${launcherDir.path}\\$name.png');
    }

    await launcherSized('android/ic_launcher_mdpi', 48);
    await launcherSized('android/ic_launcher_hdpi', 72);
    await launcherSized('android/ic_launcher_xhdpi', 96);
    await launcherSized('android/ic_launcher_xxhdpi', 144);
    await launcherSized('android/ic_launcher_xxxhdpi', 192);
    await launcherSized('ios/Icon-App-20x20@1x', 20);
    await launcherSized('ios/Icon-App-20x20@2x', 40);
    await launcherSized('ios/Icon-App-20x20@3x', 60);
    await launcherSized('ios/Icon-App-29x29@1x', 29);
    await launcherSized('ios/Icon-App-29x29@2x', 58);
    await launcherSized('ios/Icon-App-29x29@3x', 87);
    await launcherSized('ios/Icon-App-40x40@1x', 40);
    await launcherSized('ios/Icon-App-40x40@2x', 80);
    await launcherSized('ios/Icon-App-40x40@3x', 120);
    await launcherSized('ios/Icon-App-60x60@2x', 120);
    await launcherSized('ios/Icon-App-60x60@3x', 180);
    await launcherSized('ios/Icon-App-76x76@1x', 76);
    await launcherSized('ios/Icon-App-76x76@2x', 152);
    await launcherSized('ios/Icon-App-83.5x83.5@2x', 167);
    await launcherSized('ios/Icon-App-1024x1024@1x', 1024);
  });
}

Future<void> _write(
  WidgetTester tester,
  GlobalKey key,
  String dir,
  String name,
) async {
  final RenderObject? obj = key.currentContext?.findRenderObject();
  expect(obj, isA<RenderRepaintBoundary>(),
      reason: 'Expected $name to be wrapped in RepaintBoundary.');
  final RenderRepaintBoundary boundary = obj! as RenderRepaintBoundary;
  final ui.Image image = await boundary.toImage(pixelRatio: 1);
  final ByteData? bytes =
      await image.toByteData(format: ui.ImageByteFormat.png);
  expect(bytes, isNotNull, reason: 'Failed to encode $name as PNG.');
  final File file = File('$dir/$name.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  // Surface the path so the user can find the PNG.
  // ignore: avoid_print
  print('  wrote ${file.path}');
}

/// Static splash mock — same layout as the live splash but without
/// the animation controllers (deterministic for screenshot tests).
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
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}