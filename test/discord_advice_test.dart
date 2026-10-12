import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/discord/discord_ipc.dart';
import 'package:gandar/data/discord/windows_session.dart';

/// The words a person reads when Discord's pipe refuses Gandar.
///
/// These used to be three cases of one guess: which of the two programs was
/// elevated. That guess is wrong in the direction it was most confident about —
/// an elevated program *can* write to an ordinary one's pipe, which was measured
/// on a real machine (an elevated process opened Discord's `discord-ipc-0` and
/// completed a handshake and a `SET_ACTIVITY`) — and it named the wrong cause
/// for the most common one of all, a pipe belonging to a different Windows
/// account.
///
/// So the advice now takes the facts and is tested on them: who owns the pipe,
/// what Discord is running as, and whether this process is elevated.
void main() {
  const pipe = r'\\.\pipe\discord-ipc-0';
  const us = 'S-1-5-21-450133605-757460015-1053418532-1001';
  const them = 'S-1-5-21-450133605-757460015-1053418532-1002';

  DiscordProcessInfo discord({bool? elevated}) => DiscordProcessInfo(
    pid: 4242,
    executable: 'Discord.exe',
    userSid: us,
    elevated: elevated,
    integrity: elevated == true ? 'high' : 'medium',
  );

  String advice({
    bool? elevated,
    String? pipeOwner,
    List<DiscordProcessInfo>? discordProcesses,
    String? ourSid = us,
  }) => discordPipeRefusedAdvice(
    path: pipe,
    elevated: elevated,
    pipeOwner: pipeOwner,
    ourSid: ourSid,
    discord: discordProcesses,
  );

  group('when the pipe belongs to another account', () {
    test('it says so, and says elevation is not the answer', () {
      final text = advice(
        elevated: true,
        pipeOwner: them,
        discordProcesses: <DiscordProcessInfo>[discord(elevated: true)],
      );

      expect(text, contains(pipe));
      expect(text, contains('different Windows account'));
      expect(text, contains('…-1002'), reason: 'the account that owns it');
      expect(text, contains('…-1001'), reason: 'the account Gandar is running as');
      expect(text, contains('Being an administrator does not help here'));
      expect(
        text,
        isNot(contains('start both the same way')),
        reason: 'two accounts cannot be matched by starting things differently',
      );
    });
  });

  group('when no Discord is running', () {
    test('a leftover pipe name is named as such', () {
      final text = advice(
        elevated: false,
        pipeOwner: us,
        discordProcesses: const <DiscordProcessInfo>[],
      );

      expect(text, contains('no Discord process is running'));
      expect(text, contains('left over'));
    });
  });

  group('when Discord is the elevated one', () {
    test('the fix points at Discord, not at Gandar', () {
      final text = advice(
        elevated: false,
        pipeOwner: us,
        discordProcesses: <DiscordProcessInfo>[discord(elevated: true)],
      );

      expect(text, contains('Discord is running as administrator'));
      expect(text, contains('Gandar is not'));
      expect(text, contains('Start Discord normally'));
      expect(
        text,
        isNot(contains('Gandar is running as administrator')),
        reason: 'this Gandar is not elevated, and saying so would be wrong',
      );
    });
  });

  group('when Gandar is the elevated one', () {
    test('it does not blame elevation, because that is not the cause', () {
      final text = advice(
        elevated: true,
        pipeOwner: us,
        discordProcesses: <DiscordProcessInfo>[discord(elevated: false)],
      );

      expect(text, contains('Gandar is running as administrator'));
      expect(text, contains('Discord is not elevated'));
      expect(
        text,
        contains('that is not the usual reason'),
        reason: 'an elevated program can write to an ordinary one’s pipe',
      );
      expect(
        text,
        isNot(contains('Close Gandar and open it normally')),
        reason: 'that advice was measured to be based on a false premise',
      );
      expect(
        text,
        contains('restarting Discord'),
        reason: 'restarting the client is what actually helps',
      );
    });
  });

  group('when neither is elevated', () {
    test('it says plainly that this is not an administrator problem', () {
      final text = advice(
        elevated: false,
        pipeOwner: us,
        discordProcesses: <DiscordProcessInfo>[discord(elevated: false)],
      );

      expect(text, contains('not an administrator problem at all'));
      expect(text, contains('Quit Discord completely'));
      expect(text, contains('endpoint-security'));
      expect(text, isNot(contains('most likely')));
    });
  });

  group('when nothing could be measured', () {
    test('it admits it rather than picking a side', () {
      final text = advice(elevated: null, discordProcesses: null);

      expect(text, contains('would not say which program is the problem'));
      expect(
        text,
        isNot(contains('Gandar is running as administrator')),
        reason: 'nothing was measured, so nothing may be asserted',
      );
      expect(text, isNot(contains('Discord is running as administrator')));
    });

    test('a pipe it could not read the owner of is not called another account',
        () {
      final text = advice(
        elevated: false,
        pipeOwner: null,
        discordProcesses: <DiscordProcessInfo>[discord(elevated: false)],
      );
      expect(text, isNot(contains('different Windows account')));
    });
  });

  test('every answer says Discord is optional', () {
    for (final text in <String>[
      advice(elevated: true, pipeOwner: them, ourSid: us),
      advice(elevated: false, discordProcesses: const <DiscordProcessInfo>[]),
      advice(elevated: false, discordProcesses: <DiscordProcessInfo>[discord(elevated: true)]),
      advice(elevated: true, discordProcesses: <DiscordProcessInfo>[discord(elevated: false)]),
      advice(elevated: false, discordProcesses: <DiscordProcessInfo>[discord(elevated: false)]),
      advice(elevated: null, discordProcesses: null),
    ]) {
      expect(text, contains('optional extra'));
      expect(text, contains(pipe));
    }
  });
}
