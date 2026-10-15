import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../local/hive_boxes.dart';
import '../../features/rewards/rewards_model.dart';

/// Storage contract for the rewards snapshot.
///
/// Two impls:
///   * [HiveRewardsRepository] — production, backed by a `Box`.
///   * [InMemoryRewardsRepository] — used by tests and as a fallback
///     if Hive is unavailable (e.g. running in a sandboxed test).
abstract class RewardsRepository {
  Future<RewardsSnapshot> read();
  Future<void> write(RewardsSnapshot snapshot);
}

class HiveRewardsRepository implements RewardsRepository {
  HiveRewardsRepository(this._box);

  final Box<dynamic> _box;

  /// Open the rewards box. Call once at startup (Hive must be init'd).
  static Future<HiveRewardsRepository> open() async {
    final box = await Hive.openBox<dynamic>(HiveBoxes.rewards);
    return HiveRewardsRepository(box);
  }

  /// Key used inside the Hive box. The whole snapshot is stored as a
  /// single record so we don't need adapters for the snapshot class.
  static const String _key = 'snapshot';

  @override
  Future<RewardsSnapshot> read() async {
    final raw = _box.get(_key);
    if (raw is Map) {
      return _decode(raw);
    }
    return RewardsSnapshot.empty;
  }

  @override
  Future<void> write(RewardsSnapshot snapshot) async {
    await _box.put(_key, {
      'coins': snapshot.coins,
      'xp': snapshot.xp,
    });
  }

  /// Defensive decode — handles the case where Hive stores ints as
  /// `int` or `num` depending on platform.
  static RewardsSnapshot _decode(Map<dynamic, dynamic> raw) {
    final coins = (raw['coins'] as num?)?.toInt() ?? 0;
    final xp = (raw['xp'] as num?)?.toInt() ?? 0;
    return RewardsSnapshot(coins: coins, xp: xp);
  }
}

class InMemoryRewardsRepository implements RewardsRepository {
  RewardsSnapshot _snapshot = RewardsSnapshot.empty;

  /// Test hook — seed an initial state.
  void seed(RewardsSnapshot snapshot) {
    _snapshot = snapshot;
  }

  @override
  Future<RewardsSnapshot> read() async => _snapshot;

  @override
  Future<void> write(RewardsSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}
