import 'package:flutter/material.dart';

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
  const AlbumArt({super.key, this.url, this.size = 56, this.radius});

  final String? url;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gandarTokens;
    final r = BorderRadius.circular(radius ?? tokens.radiusSm);
    return ClipRRect(
      borderRadius: r,
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: tokens.surfaceElevatedColor,
          child: url == null || url!.isEmpty
              ? Icon(
                  Icons.music_note,
                  size: size * 0.4,
                  color: tokens.textSecondaryColor,
                )
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.music_note,
                    size: size * 0.4,
                    color: tokens.textSecondaryColor,
                  ),
                ),
        ),
      ),
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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

/// The Gandar wordmark used in the sidebar and sign-in screen.
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
