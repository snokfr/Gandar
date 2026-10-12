import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/discord/discord_ipc.dart';

/// The words a person reads when Discord's pipe refuses Gandar.
///
/// The fact that matters is *which* program is elevated: the fix is to start
/// the other one the same way, and advice that names the wrong side sends
/// someone to change a program that was never the problem. Only Windows can
/// answer it, so all three cases have to say something true.
void main() {
  const pipe = r'\\.\pipe\discord-ipc-0';

  group('when Discord refuses the pipe', () {
    test('an elevated Gandar is named as the elevated side', () {
      final advice = discordPipeRefusedAdvice(path: pipe, elevated: true);

      expect(advice, contains(pipe));
      expect(advice, contains('Gandar is running as administrator'));
      expect(
        advice,
        contains('Discord\u2019s own level cannot be read from here'),
        reason: 'only Gandar\u2019s level was measured, so only that may be '
            'stated as fact',
      );
      expect(
        advice,
        isNot(contains('Discord is most likely')),
        reason: 'the elevated program is known, so nothing needs guessing',
      );
      expect(
        advice,
        isNot(contains('Discord is not')),
        reason: 'Discord\u2019s side of the mismatch was never measured',
      );
      // The way out of this one is to stop elevating Gandar: that is the
      // program the reader controls, and the one they just started wrong.
      expect(advice, contains('open it normally'));
      expect(advice, contains('not as administrator'));
    });

    test('a normal Gandar points at Discord instead', () {
      final advice = discordPipeRefusedAdvice(path: pipe, elevated: false);

      expect(
        advice,
        contains('Discord is most likely running as administrator'),
      );
      expect(advice, contains('Gandar is not'));
      expect(
        advice,
        isNot(contains('Gandar is running as administrator')),
        reason: 'this Gandar is not elevated, and saying so would be wrong',
      );
      expect(advice, contains('Start Discord normally'));
    });

    test('an unknown answer admits it rather than picking a side', () {
      final advice = discordPipeRefusedAdvice(path: pipe, elevated: null);

      expect(advice, contains('One of the two is running as administrator'));
      expect(advice, isNot(contains('most likely')));
      expect(
        advice,
        isNot(contains('Gandar is running as administrator')),
        reason: 'nothing was measured, so nothing may be asserted',
      );
      expect(advice, contains('Start both the same way'));
      expect(
        advice,
        isNot(contains('open it normally')),
        reason: 'the wrong side must not be named when neither was measured',
      );
    });

    test('every answer says the problem is not Gandar\'s to fix', () {
      for (final elevated in <bool?>[true, false, null]) {
        final advice = discordPipeRefusedAdvice(path: pipe, elevated: elevated);
        expect(advice, contains('nothing to fix in Gandar'));
      }
    });
  });
}
