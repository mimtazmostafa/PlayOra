import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/game_category.dart';
import '../models/game_model.dart';

/// Catalog of games shown across the app.
///
/// Two implementations:
/// - [LocalJsonGameRepository] — backed by `assets/data/games_seed.json` (production).
/// - [InMemoryGameRepository] — seeded by hand for tests / previews.
///
/// All methods are async so the API swap-in later (replace `LocalJson…` with
/// `RemoteGameRepository`) requires no signature changes at call sites.
abstract class GameRepository {
  Future<List<Game>> getAllGames();
  Future<List<Game>> getByCategory(GameCategory category);
  Future<Game?> getById(String id);

  /// Curated hero games for the home banner. Order in the seed file is what
  /// the UI shows — implementations should return the first [limit] entries.
  Future<List<Game>> getFeatured({int limit = 3});

  /// Case-insensitive substring match across `title`, `titleBangla`, and
  /// `description`. Empty query returns the full catalog.
  Future<List<Game>> search(String query);
}

class LocalJsonGameRepository implements GameRepository {
  LocalJsonGameRepository._(this._games);

  /// Path to the bundled seed JSON. Declared in `pubspec.yaml`.
  static const String assetPath = 'assets/data/games_seed.json';

  final List<Game> _games;

  /// Load and parse the seed JSON. Call once at startup.
  static Future<LocalJsonGameRepository> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = json.decode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'games_seed.json: expected an object at the root.',
      );
    }
    final list = decoded['games'];
    if (list is! List) {
      throw const FormatException(
        'games_seed.json: missing or non-list "games" field.',
      );
    }
    final games = <Game>[];
    for (final entry in list) {
      if (entry is Map<String, dynamic>) {
        games.add(Game.fromJson(entry));
      }
    }
    return LocalJsonGameRepository._(games);
  }

  @override
  Future<List<Game>> getAllGames() async => List<Game>.unmodifiable(_games);

  @override
  Future<List<Game>> getByCategory(GameCategory category) async {
    return _games
        .where((g) => g.category == category)
        .toList(growable: false);
  }

  @override
  Future<Game?> getById(String id) async {
    for (final g in _games) {
      if (g.id == id) return g;
    }
    return null;
  }

  @override
  Future<List<Game>> getFeatured({int limit = 3}) async {
    if (_games.isEmpty) return const <Game>[];
    final end = limit.clamp(0, _games.length);
    return List<Game>.unmodifiable(_games.sublist(0, end));
  }

  @override
  Future<List<Game>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return getAllGames();
    return _games.where((g) {
      return g.title.toLowerCase().contains(q) ||
          g.titleBangla.toLowerCase().contains(q) ||
          g.description.toLowerCase().contains(q);
    }).toList(growable: false);
  }
}

class InMemoryGameRepository implements GameRepository {
  InMemoryGameRepository(List<Game> games) : _games = List<Game>.of(games);

  final List<Game> _games;

  @override
  Future<List<Game>> getAllGames() async => List<Game>.unmodifiable(_games);

  @override
  Future<List<Game>> getByCategory(GameCategory category) async {
    return _games
        .where((g) => g.category == category)
        .toList(growable: false);
  }

  @override
  Future<Game?> getById(String id) async {
    for (final g in _games) {
      if (g.id == id) return g;
    }
    return null;
  }

  @override
  Future<List<Game>> getFeatured({int limit = 3}) async {
    if (_games.isEmpty) return const <Game>[];
    final end = limit.clamp(0, _games.length);
    return List<Game>.unmodifiable(_games.sublist(0, end));
  }

  @override
  Future<List<Game>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return getAllGames();
    return _games.where((g) {
      return g.title.toLowerCase().contains(q) ||
          g.titleBangla.toLowerCase().contains(q) ||
          g.description.toLowerCase().contains(q);
    }).toList(growable: false);
  }
}