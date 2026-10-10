import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Explains the Spotify connection and starts the PKCE sign-in.
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final deps = ref.watch(appDependenciesProvider);
    final configured = deps.clientId.isNotEmpty;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const GandarLogo(size: 36),
                const SizedBox(height: 20),
                Text(
                  'Connect your Spotify account',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Gandar reads your liked songs and playlists from Spotify, '
                  'then streams the audio from open sources — no ads.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                if (!configured)
                  const _ClientIdNotice()
                else
                  FilledButton.icon(
                    onPressed: _busy ? null : _signIn,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(
                      _busy ? 'Waiting for browser…' : 'Sign in with Spotify',
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'You can keep using Gandar without signing in: themes, '
                  'playback settings and the cache all work locally.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(appDependenciesProvider).spotifyApi.signIn();
      ref.invalidate(isSignedInProvider);
      ref.invalidate(likedTracksProvider);
      ref.invalidate(playlistsProvider);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Shown when no Spotify client id has been configured.
class _ClientIdNotice extends StatelessWidget {
  const _ClientIdNotice();

  @override
  Widget build(BuildContext context) {
    return GandarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline),
              const SizedBox(width: 8),
              Text(
                'Spotify client id required',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Create an app in the Spotify developer dashboard, add the '
            'redirect URI http://127.0.0.1:8888/callback, and add your account '
            'under User Management. Then run Gandar with:\n\n'
            'flutter run --dart-define=SPOTIFY_CLIENT_ID=your_client_id',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
