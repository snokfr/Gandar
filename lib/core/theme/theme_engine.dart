import 'package:flutter/material.dart';

import 'theme_presets.dart';
import 'theme_tokens.dart';

/// Turns a [ThemeTokens] into a Flutter [ThemeData].
///
/// All app surfaces read from [ThemeData.colorScheme] / extensions rather than
/// hard-coded colors, so a single token change restyles the whole app.
class ThemeEngine {
  const ThemeEngine._();

  static ThemeData build(ThemeTokens tokens) {
    final scheme = ColorScheme(
      brightness: tokens.brightness,
      primary: tokens.accentColor,
      onPrimary: _readableOn(tokens.accentColor),
      secondary: tokens.accentAltColor,
      onSecondary: _readableOn(tokens.accentAltColor),
      error: const Color(0xFFE5484D),
      onError: Colors.white,
      surface: tokens.surfaceColor,
      onSurface: tokens.textPrimaryColor,
      surfaceContainerHighest: tokens.surfaceElevatedColor,
      onSurfaceVariant: tokens.textSecondaryColor,
      outline: tokens.borderColor,
      outlineVariant: tokens.borderColor,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: tokens.textPrimaryColor,
      onInverseSurface: tokens.surfaceColor,
      inversePrimary: tokens.accentAltColor,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: tokens.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.backgroundPrimaryColor,
      canvasColor: tokens.backgroundPrimaryColor,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    final textTheme = _textTheme(base.textTheme, tokens);

    return base.copyWith(
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[GandarTokens(tokens)],
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.backgroundPrimaryColor,
        foregroundColor: tokens.textPrimaryColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: tokens.surfaceColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          side: BorderSide(color: tokens.borderColor),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surfaceElevatedColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.surfaceElevatedColor,
        modalBackgroundColor: tokens.surfaceElevatedColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(tokens.radiusLg),
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: tokens.backgroundSecondaryColor,
        indicatorColor: tokens.accentColor.withValues(alpha: 0.18),
        selectedIconTheme: IconThemeData(color: tokens.accentColor),
        selectedLabelTextStyle: TextStyle(
          color: tokens.textPrimaryColor,
          fontWeight: FontWeight.w600,
        ),
        unselectedIconTheme: IconThemeData(color: tokens.textSecondaryColor),
        unselectedLabelTextStyle: TextStyle(color: tokens.textSecondaryColor),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.surfaceElevatedColor,
        indicatorColor: tokens.accentColor.withValues(alpha: 0.18),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? tokens.textPrimaryColor
                : tokens.textSecondaryColor,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? tokens.accentColor
                : tokens.textSecondaryColor,
          ),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: tokens.accentColor,
        thumbColor: tokens.textPrimaryColor,
        inactiveTrackColor: tokens.borderColor,
        overlayColor: tokens.accentColor.withValues(alpha: 0.15),
        trackHeight: 4,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.textPrimaryColor
              : tokens.textSecondaryColor,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.accentColor
              : tokens.borderColor,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceElevatedColor,
        hintStyle: TextStyle(color: tokens.textSecondaryColor),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          borderSide: BorderSide(color: tokens.accentColor, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.borderColor,
        thickness: 1,
        space: 1,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          tokens.textSecondaryColor.withValues(alpha: 0.4),
        ),
        radius: Radius.circular(tokens.radiusSm),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: tokens.textSecondaryColor,
        textColor: tokens.textPrimaryColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: tokens.surfaceElevatedColor,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.borderColor),
        ),
        textStyle: TextStyle(color: tokens.textPrimaryColor, fontSize: 12),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.accentColor,
        linearTrackColor: tokens.borderColor,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.surfaceElevatedColor,
        contentTextStyle: TextStyle(color: tokens.textPrimaryColor),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
      ),
    );
  }

  /// Body text keeps comfortable leading; headings tighten tracking as they
  /// grow (size-specific tracking, per platform typography practice).
  static TextTheme _textTheme(TextTheme base, ThemeTokens tokens) {
    TextStyle color(TextStyle? s) =>
        (s ?? const TextStyle()).copyWith(color: tokens.textPrimaryColor);

    return base.copyWith(
      displayLarge: color(base.displayLarge).copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -1.5,
        height: 1.05,
      ),
      displayMedium: color(base.displayMedium).copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
        height: 1.08,
      ),
      headlineMedium: color(base.headlineMedium).copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.15,
      ),
      titleLarge: color(base.titleLarge)
          .copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: color(base.titleMedium)
          .copyWith(fontWeight: FontWeight.w600),
      bodyLarge: color(base.bodyLarge).copyWith(height: 1.45),
      bodyMedium: color(base.bodyMedium)
          .copyWith(color: tokens.textSecondaryColor, height: 1.45),
      bodySmall: color(base.bodySmall)
          .copyWith(color: tokens.textSecondaryColor, height: 1.4),
      labelLarge: color(base.labelLarge)
          .copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
    );
  }

  static Color _readableOn(Color background) =>
      background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}

/// Exposes the raw tokens to widgets without re-deriving them from colors.
@immutable
class GandarTokens extends ThemeExtension<GandarTokens> {
  const GandarTokens(this.tokens);

  final ThemeTokens tokens;

  @override
  GandarTokens copyWith({ThemeTokens? tokens}) =>
      GandarTokens(tokens ?? this.tokens);

  @override
  GandarTokens lerp(ThemeExtension<GandarTokens>? other, double t) {
    if (other is! GandarTokens) return this;
    return t < 0.5 ? this : other;
  }
}

/// Convenience accessor: `context.gandarTokens`.
extension GandarThemeContext on BuildContext {
  ThemeTokens get gandarTokens =>
      Theme.of(this).extension<GandarTokens>()?.tokens ??
      ThemePresets.defaultTheme;
}
