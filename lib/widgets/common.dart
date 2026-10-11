import 'package:flutter/material.dart';

import '../core/errors/failure_text.dart';
import '../core/theme/theme_engine.dart';
import '../domain/models/track.dart';

/// A section title with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleWidget = subtitle == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle!, style: theme.textTheme.bodySmall),
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              ?subtitleWidget,
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

/// Square album artwork with a graceful placeholder.
class AlbumArt extends StatelessWidget {
  const AlbumArt({
    super.key,
    this.url,
    this.size = 56,
    this.radius,
    this.isCurrent = false,
  });

  final String? url;
  final double size;
  final double? radius;

  /// Marks this as the track being played.
  ///
  /// A shelf of covers has no title to colour, so the badge is how the cover
  /// says "this one" — the same convention every music player uses.
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gandarTokens;
    final r = BorderRadius.circular(radius ?? tokens.radiusSm);
    final art = ClipRRect(
      borderRadius: r,
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: tokens.surfaceElevatedColor,
          child: url == null || url!.isEmpty
              ? Icon(
                  Icons.music_note,
                  size: size.isFinite ? size * 0.4 : 24,
                  color: tokens.textSecondaryColor,
                )
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.music_note,
                    size: size.isFinite ? size * 0.4 : 24,
                    color: tokens.textSecondaryColor,
                  ),
                ),
        ),
      ),
    );
    if (!isCurrent) return art;

    return Stack(
      children: [
        art,
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: r,
              border: Border.all(color: tokens.accentColor, width: 2),
            ),
          ),
        ),
        Positioned(
          right: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: Color(0xCC000000),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow, size: 14, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

/// One row in a track list.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    this.onTap,
    this.leading,
    this.trailing,
    this.isCurrent = false,
    this.subtitle,
    this.dense = false,
  });

  final Track track;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;
  final bool isCurrent;
  final String? subtitle;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gandarTokens;
    final theme = Theme.of(context);
    return ListTile(
      dense: dense,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading:
          leading ?? AlbumArt(url: track.artworkUrl, size: dense ? 40 : 48),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          color: isCurrent ? tokens.accentColor : tokens.textPrimaryColor,
        ),
      ),
      subtitle: Text(
        subtitle ?? track.artists.join(', '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: trailing,
    );
  }
}

/// A card-style container used for grouping settings.
class GandarCard extends StatelessWidget {
  const GandarCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gandarTokens;
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceColor,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.borderColor),
      ),
      child: child,
    );
  }
}

/// Switch row with a supporting description.
class SettingSwitchTile extends StatelessWidget {
  const SettingSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.description,
  });

  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: description == null
          ? null
          : Text(description!, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

/// Labelled slider row.
class SettingSliderTile extends StatelessWidget {
  const SettingSliderTile({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.description,
    this.divisions,
    this.valueLabel,
  });

  final String title;
  final String? description;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String Function(double)? valueLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            Text(
              valueLabel?.call(value) ?? value.toStringAsFixed(0),
              style: theme.textTheme.labelLarge,
            ),
          ],
        ),
        if (description != null)
          Text(description!, style: theme.textTheme.bodySmall),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Centered empty/error placeholder.
///
/// Scrolls rather than overflows when the copy is long or the window is small,
/// because the alternative is a yellow-and-black bar across the explanation the
/// user needs to read.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: tokens.textSecondaryColor),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// The action that belongs under a failure message.
///
/// **Retry** is offered only when repeating the work could change the answer.
/// A file that will never parse gets a route to the screen that explains what
/// to change instead, so the button never promises something the app cannot
/// deliver.
class FailureAction extends StatelessWidget {
  const FailureAction({
    super.key,
    required this.failure,
    required this.onRetry,
    this.onFix,
    this.fixLabel,
  });

  final FailureText failure;

  /// Re-runs the work behind the failed view.
  final VoidCallback onRetry;

  /// Where to send the user when the fix is outside this screen. Omitted on
  /// screens that can only ever retry.
  final VoidCallback? onFix;

  /// Label for [onFix]; defaults to wording that suits a dead end.
  final String? fixLabel;

  @override
  Widget build(BuildContext context) {
    if (failure.retryable) {
      return FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
      );
    }
    final fix = onFix;
    if (fix == null) {
      return OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Check again'),
      );
    }
    return OutlinedButton.icon(
      onPressed: fix,
      icon: const Icon(Icons.help_outline),
      label: Text(fixLabel ?? 'How to fix this'),
    );
  }
}

/// The Gandar wordmark used in the sidebar and on the empty states.
class GandarLogo extends StatelessWidget {
  const GandarLogo({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gandarTokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [tokens.accentColor, tokens.accentAltColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Icon(
            Icons.graphic_eq,
            size: size * 0.62,
            color: tokens.backgroundPrimaryColor,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Gandar',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontSize: size * 0.85, letterSpacing: -0.2),
        ),
      ],
    );
  }
}
