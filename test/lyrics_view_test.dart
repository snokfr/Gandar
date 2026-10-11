import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/theme/theme_engine.dart';
import 'package:gandar/core/theme/theme_presets.dart';
import 'package:gandar/data/lyrics/lyrics_source.dart';
import 'package:gandar/features/player/lyrics_view.dart';

const String _lrc = '''
[00:10.00] first line
[00:14.00] second line
[00:18.00] third line
''';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeEngine.build(ThemePresets.spotifyClassic),
  home: Scaffold(body: SizedBox(height: 400, child: child)),
);

/// The style the line is being rendered with.
///
/// Read off `AnimatedDefaultTextStyle` rather than the `Text` it wraps: the
/// target style is the widget's own field, so this stays true while the
/// cross-fade between two lines is still running.
///
/// Walked up by hand, nearest first, rather than with `find.ancestor`: Material
/// puts an `AnimatedDefaultTextStyle` of its own above this whole tree, so the
/// finder matches two widgets and cannot say which is the line's.
TextStyle _styleOf(WidgetTester tester, String line) {
  AnimatedDefaultTextStyle? found;
  tester.element(find.text(line)).visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is AnimatedDefaultTextStyle) {
      found = widget;
      return false;
    }
    return true;
  });
  return found!.style;
}

void main() {
  final accent = ThemePresets.spotifyClassic.accentColor;

  testWidgets('every line is rendered', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    addTearDown(position.dispose);

    await tester.pumpWidget(
      _wrap(
        SyncedLyricsView(
          lyrics: const Lyrics(plain: 'first\nsecond\nthird', synced: _lrc),
          position: position,
        ),
      ),
    );

    expect(find.text('first line'), findsOneWidget);
    expect(find.text('second line'), findsOneWidget);
    expect(find.text('third line'), findsOneWidget);
  });

  testWidgets('the line being sung is the highlighted one', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    addTearDown(position.dispose);

    await tester.pumpWidget(
      _wrap(
        SyncedLyricsView(
          lyrics: const Lyrics(plain: 'first\nsecond\nthird', synced: _lrc),
          position: position,
        ),
      ),
    );

    // Before the first line, nothing is lit up — a track with a long intro
    // should not show its opening line as though it were already singing it.
    expect(_styleOf(tester, 'first line').fontWeight, isNot(FontWeight.w700));

    position.value = const Duration(seconds: 12);
    await tester.pump();
    expect(_styleOf(tester, 'first line').fontWeight, FontWeight.w700);
    expect(_styleOf(tester, 'first line').color, accent);
    expect(_styleOf(tester, 'third line').fontWeight, isNot(FontWeight.w700));

    // Crossing into the next line moves the highlight, which is the whole
    // point of the feature.
    position.value = const Duration(seconds: 14);
    await tester.pump();
    expect(_styleOf(tester, 'first line').fontWeight, isNot(FontWeight.w700));
    expect(_styleOf(tester, 'second line').fontWeight, FontWeight.w700);
    expect(_styleOf(tester, 'second line').color, accent);

    position.value = const Duration(seconds: 19);
    await tester.pump();
    expect(_styleOf(tester, 'third line').fontWeight, FontWeight.w700);
  });

  testWidgets('seeking backwards moves the highlight back', (tester) async {
    final position = ValueNotifier<Duration>(const Duration(seconds: 19));
    addTearDown(position.dispose);

    await tester.pumpWidget(
      _wrap(
        SyncedLyricsView(
          lyrics: const Lyrics(plain: 'first\nsecond\nthird', synced: _lrc),
          position: position,
        ),
      ),
    );
    await tester.pump();
    expect(_styleOf(tester, 'third line').fontWeight, FontWeight.w700);

    position.value = const Duration(seconds: 11);
    await tester.pump();
    expect(_styleOf(tester, 'first line').fontWeight, FontWeight.w700);
    expect(_styleOf(tester, 'third line').fontWeight, isNot(FontWeight.w700));
  });

  testWidgets('lyrics with no timestamps are shown plainly, unhighlighted', (
    tester,
  ) async {
    final position = ValueNotifier<Duration>(const Duration(seconds: 30));
    addTearDown(position.dispose);

    await tester.pumpWidget(
      _wrap(
        SyncedLyricsView(
          lyrics: const Lyrics(plain: 'just words\nand more words'),
          position: position,
        ),
      ),
    );

    // Plain words are shown as selectable text rather than as a list of styled
    // lines: there is nothing to sync to, so nothing pretends to be current.
    expect(find.textContaining('just words'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('scrollable false renders the lines without a scroll view', (
    tester,
  ) async {
    // The now-playing sheet is already a scrollable; a second one inside it
    // would fight the outer one for the drag.
    final position = ValueNotifier<Duration>(Duration.zero);
    addTearDown(position.dispose);

    await tester.pumpWidget(
      _wrap(
        SyncedLyricsView(
          lyrics: const Lyrics(plain: 'first\nsecond\nthird', synced: _lrc),
          position: position,
          scrollable: false,
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('third line'), findsOneWidget);
  });

  testWidgets('an empty lyric is not a crash', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    addTearDown(position.dispose);

    await tester.pumpWidget(
      _wrap(SyncedLyricsView(lyrics: Lyrics.none, position: position)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
