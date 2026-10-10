import 'dart:math';

import '../../core/settings/playback_settings.dart';

/// Queue ordering strategies.
///
/// [ShuffleMode.standard] is a plain Fisher-Yates shuffle.
/// [ShuffleMode.smart] reorders to avoid placing recently played tracks at the
/// front of the queue, which is what makes "random" feel random in a large
/// library.
class ShuffleService {
  ShuffleService({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// How many leading positions smart shuffle tries to keep free of recent
  /// tracks.
  static const int recentGuardDepth = 5;

  /// Returns a new list in playback order.
  ///
  /// [recent] holds recently played *ids* (most recent first) and is only
  /// consulted for [ShuffleMode.smart]. [idOf] maps an item to the id used for
  /// that comparison; it defaults to the item itself.
  List<T> order<T>(
    List<T> items, {
    required ShuffleMode mode,
    List<Object?> recent = const [],
    Object? Function(T item)? idOf,
  }) {
    switch (mode) {
      case ShuffleMode.off:
        return List<T>.of(items);
      case ShuffleMode.standard:
        return _fisherYates(items);
      case ShuffleMode.smart:
        return _smartShuffle(items, recent, idOf ?? (T item) => item);
    }
  }

  /// Unbiased uniform permutation (inside-out Fisher-Yates).
  List<T> _fisherYates<T>(List<T> items) {
    final out = List<T>.of(items);
    for (var i = out.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final tmp = out[i];
      out[i] = out[j];
      out[j] = tmp;
    }
    return out;
  }

  List<T> _smartShuffle<T>(
    List<T> items,
    List<Object?> recent,
    Object? Function(T item) idOf,
  ) {
    final out = _fisherYates(items);
    if (out.length <= 1 || recent.isEmpty) return out;

    final recentSet = recent.toSet();
    final depth = min(recentGuardDepth, out.length);

    for (var i = 0; i < depth; i++) {
      if (!recentSet.contains(idOf(out[i]))) continue;
      // Find a later, non-recent candidate and swap it forward. Scanning
      // backwards prefers the most recently shuffled material.
      var swapped = false;
      for (var j = out.length - 1; j > i; j--) {
        if (!recentSet.contains(idOf(out[j]))) {
          final tmp = out[i];
          out[i] = out[j];
          out[j] = tmp;
          swapped = true;
          break;
        }
      }
      // If every remaining candidate is recent, leaving it is correct: we
      // cannot invent a non-recent track.
      if (!swapped) break;
    }
    return out;
  }
}

/// Tracks a small ring of recently played ids so [ShuffleService] can avoid
/// immediate repeats.
class RecentTracker<T> {
  RecentTracker({this.capacity = 20});

  final int capacity;
  final List<T> _items = <T>[];

  List<T> get items => List<T>.unmodifiable(_items);

  void record(T id) {
    _items.remove(id);
    _items.insert(0, id);
    if (_items.length > capacity) {
      _items.removeRange(capacity, _items.length);
    }
  }

  void clear() => _items.clear();
}
