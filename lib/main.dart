import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app.dart';
import 'app/router.dart';
import 'core/settings/settings_repository.dart';
import 'data/storage/app_database.dart';
import 'playback/audio_engine/media_kit_audio_engine.dart';
import 'state/app_dependencies.dart';
import 'state/providers.dart';

/// Spotify application client id, supplied at build time:
/// `flutter run --dart-define=SPOTIFY_CLIENT_ID=...`
const String spotifyClientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // libmpv must be initialized before any Player is constructed.
  MediaKit.ensureInitialized();

  final database = AppDatabase();
  final settingsRepository = SettingsRepository(await SharedPrefsStore.open());
  final audioEngine = MediaKitAudioEngine();

  final dependencies = await AppDependencies.bootstrap(
    database: database,
    settingsRepository: settingsRepository,
    audioEngine: audioEngine,
    clientId: spotifyClientId,
  );

  runApp(
    ProviderScope(
      overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
      child: GandarApp(router: buildRouter()),
    ),
  );
}
