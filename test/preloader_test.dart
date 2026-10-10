import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/domain/models/resolved_stream.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/domain/repositories/repositories.dart';
import 'package:gandar/playback/preloader.dart';

Track t(String id) => Track(id: id, title: id, artists: const ['A']);

/// Resolver that counts calls and can be made to fail.
class CountingResolver implements AudioResolver {
  CountingResolver({this.failFor = const {}});

  final Set<String> failFor;
  final Map<String, int> calls = {};
  final List<String> order = [];
  Completer<void>? gate;

  @override
  Future<ResolvedStream> resolve(Track track) async {
    calls[track.id] = (calls[track.id] ?? 0) + 1;
    order.add(track.id);
    if (gate != null) await gate!.future;
    if (failFor.contains(track.id)) {
      throw StateError('resolution failed for ${track.id}');
    }
    return ResolvedStream(
      url: 'https://example.test/${track.id}.m4a',
      videoId: 'v-${track.id}',
      container: 'm4a',
    );
  }
}

void main() {
  test('resolves a track once and serves later requests from cache', () async {
    final resolver = CountingResolver();
    final preloader = StreamPreloader(resolver: resolver);

    final first = await preloader.resolve(t('a'));
    final second = await preloader.resolve(t('a'));

    expect(first.url, second.url);
    expect(resolver.calls['a'], 1);
    expect(preloader.peek('a'), isNotNull);
  });

  test('concurrent requests for the same track share one resolution', () async {
    final resolver = CountingResolver()..gate = Completer<void>();
    final preloader = StreamPreloader(resolver: resolver);

    final futures = [
      preloader.resolve(t('a')),
      preloader.resolve(t('a')),
      preloader.resolve(t('a')),
    ];
    resolver.gate!.complete();
    await Future.wait(futures);

    expect(resolver.calls['a'], 1);
  });

  test('prefetch is fire-and-forget and warms the cache', () async {
    final resolver = CountingResolver();
    final preloader = StreamPreloader(resolver: resolver);

    preloader.prefetch(t('b'));
    // Give the microtask queue a turn.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(preloader.peek('b'), isNotNull);
    expect(resolver.calls['b'], 1);
  });

  test('prefetch is a no-op for null and for already-cached tracks', () async {
    final resolver = CountingResolver();
    final preloader = StreamPreloader(resolver: resolver);

    preloader.prefetch(null);
    await preloader.resolve(t('c'));
    preloader.prefetch(t('c'));
    await Future<void>.delayed(Duration.zero);

    expect(resolver.calls['c'], 1);
  });

  test('a failed resolution is not cached and can be retried', () async {
    final resolver = CountingResolver(failFor: {'d'});
    final preloader = StreamPreloader(resolver: resolver);

    await expectLater(preloader.resolve(t('d')), throwsStateError);
    expect(preloader.peek('d'), isNull);

    await expectLater(preloader.resolve(t('d')), throwsStateError);
    expect(resolver.calls['d'], 2);
  });

  test('capacity bounds how many streams are kept warm', () async {
    final resolver = CountingResolver();
    final preloader = StreamPreloader(resolver: resolver, capacity: 2);

    await preloader.resolve(t('1'));
    await preloader.resolve(t('2'));
    await preloader.resolve(t('3'));

    expect(preloader.cachedCount, 2);
    expect(preloader.peek('1'), isNull, reason: 'oldest should be evicted');
    expect(preloader.peek('2'), isNotNull);
    expect(preloader.peek('3'), isNotNull);
  });

  test('clear drops everything', () async {
    final preloader = StreamPreloader(resolver: CountingResolver());
    await preloader.resolve(t('x'));
    preloader.clear();
    expect(preloader.cachedCount, 0);
  });
}
