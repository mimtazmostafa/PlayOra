import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/skeleton_loader.dart';

/// Full-screen skeleton used while the home catalog is "loading".
///
/// Mirrors the real layout so the transition feels stable.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SkeletonBox(height: 180, borderRadius: 20),
            ),
            const SizedBox(height: AppSpacing.xl),
            // Daily challenge.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SkeletonBox(height: 88, borderRadius: 20),
            ),
            const SizedBox(height: AppSpacing.xl),
            // Row 1.
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SkeletonBox(width: 120, height: 18),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: 5,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
                itemBuilder: (_, _) => const SizedBox(
                  width: 140,
                  child: SkeletonBox(borderRadius: 16),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            // Row 2.
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SkeletonBox(width: 140, height: 18),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: 5,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
                itemBuilder: (_, _) => const SizedBox(
                  width: 140,
                  child: SkeletonBox(borderRadius: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}