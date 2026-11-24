import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color canvas;
  final Color surface;
  final Color surfaceAlt;
  final Color inkPrimary;
  final Color inkMuted;
  final Color border;
  final Color accent;
  final Color accentTint;
  final Color success;
  final Color destructive;
  final Color warning;

  const AppColors({
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.inkPrimary,
    required this.inkMuted,
    required this.border,
    required this.accent,
    required this.accentTint,
    required this.success,
    required this.destructive,
    required this.warning,
  });

  static const AppColors light = AppColors(
    canvas: Color(0xFFF7F6F2),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEFECE5),
    inkPrimary: Color(0xFF1A1D21),
    inkMuted: Color(0xFF555D6B),
    border: Color(0xFFE2DFD7),
    accent: Color(0xFF1E5AA8),
    accentTint: Color(0xFFE8F0FA),
    success: Color(0xFF1F7A4C),
    destructive: Color(0xFFB83232),
    warning: Color(0xFF9A5B13),
  );

  static const AppColors dark = AppColors(
    canvas: Color(0xFF121417),
    surface: Color(0xFF1B1F24),
    surfaceAlt: Color(0xFF232830),
    inkPrimary: Color(0xFFF1F3F5),
    inkMuted: Color(0xFF9BA4B0),
    border: Color(0xFF2C323B),
    accent: Color(0xFF60A5FA),
    accentTint: Color(0xFF1E2E44),
    success: Color(0xFF4ADE80),
    destructive: Color(0xFFF87171),
    warning: Color(0xFFFBBF24),
  );

  static AppColors of(BuildContext context) {
    final ext = Theme.of(context).extension<AppColors>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  @override
  AppColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceAlt,
    Color? inkPrimary,
    Color? inkMuted,
    Color? border,
    Color? accent,
    Color? accentTint,
    Color? success,
    Color? destructive,
    Color? warning,
  }) {
    return AppColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      inkPrimary: inkPrimary ?? this.inkPrimary,
      inkMuted: inkMuted ?? this.inkMuted,
      border: border ?? this.border,
      accent: accent ?? this.accent,
      accentTint: accentTint ?? this.accentTint,
      success: success ?? this.success,
      destructive: destructive ?? this.destructive,
      warning: warning ?? this.warning,
    );
  }

  @override
  AppColors lerp(covariant ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      inkPrimary: Color.lerp(inkPrimary, other.inkPrimary, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentTint: Color.lerp(accentTint, other.accentTint, t)!,
      success: Color.lerp(success, other.success, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

class AppTheme {
  static const double cardRadius = 12.0;
  static const double controlRadius = 10.0;
  static const double chipRadius = 8.0;
  static const double minTapTarget = 48.0;
  static const Color darkOnAccent = Color(0xFF0E1A2B);

  static TextStyle tabularStyle(TextStyle style) {
    final existing = style.fontFeatures ?? const <FontFeature>[];
    if (existing.any((f) => f.feature == 'tnum' && f.value == 1)) {
      return style;
    }
    return style.copyWith(
      fontFeatures: [...existing, const FontFeature.tabularFigures()],
    );
  }

  static ThemeData light() => _buildTheme(
        brightness: Brightness.light,
        colors: AppColors.light,
        onAccent: Colors.white,
      );

  static ThemeData dark() => _buildTheme(
        brightness: Brightness.dark,
        colors: AppColors.dark,
        onAccent: darkOnAccent,
      );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required AppColors colors,
    required Color onAccent,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: onAccent,
      primaryContainer: colors.accentTint,
      onPrimaryContainer: colors.accent,
      secondary: colors.accent,
      onSecondary: onAccent,
      secondaryContainer: colors.surfaceAlt,
      onSecondaryContainer: colors.inkPrimary,
      error: colors.destructive,
      onError: brightness == Brightness.dark ? darkOnAccent : Colors.white,
      surface: colors.surface,
      onSurface: colors.inkPrimary,
      surfaceContainerHighest: colors.surfaceAlt,
      onSurfaceVariant: colors.inkMuted,
      outline: colors.border,
      outlineVariant: colors.border,
    );

    final textTheme = TextTheme(
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: colors.inkPrimary,
        height: 1.2,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: colors.inkPrimary,
        height: 1.25,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: colors.inkPrimary,
        height: 1.3,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: colors.inkPrimary,
        height: 1.45,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: colors.inkMuted,
        height: 1.35,
      ),
      labelLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: colors.inkPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: colors.inkMuted,
      ),
    );

    OutlineInputBorder inputBorder(Color borderColor, {double width = 1.0}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: BorderSide(color: borderColor, width: width),
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.canvas,
      canvasColor: colors.canvas,
      dividerColor: colors.border,
      textTheme: textTheme,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.canvas,
        foregroundColor: colors.inkPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: colors.inkPrimary,
        ),
        shape: Border(
          bottom: BorderSide(color: colors.border, width: 1),
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: colors.border, width: 1),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(cardRadius),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: colors.border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceAlt,
        hintStyle: TextStyle(fontSize: 14, color: colors.inkMuted),
        labelStyle: TextStyle(fontSize: 14, color: colors.inkMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: inputBorder(colors.border),
        enabledBorder: inputBorder(colors.border),
        focusedBorder: inputBorder(colors.accent, width: 2.0),
        errorBorder: inputBorder(colors.destructive),
        focusedErrorBorder: inputBorder(colors.destructive, width: 2.0),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: onAccent,
          elevation: 0,
          minimumSize: const Size(minTapTarget, minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: onAccent,
          elevation: 0,
          minimumSize: const Size(minTapTarget, minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.inkPrimary,
          minimumSize: const Size(minTapTarget, minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          side: BorderSide(color: colors.border, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          minimumSize: const Size(minTapTarget, minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(minTapTarget, minTapTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minTileHeight: minTapTarget,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(
            const Size(minTapTarget, minTapTarget),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colors.accentTint;
            }
            return colors.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colors.accent;
            }
            return colors.inkPrimary;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: colors.accent, width: 2);
            }
            return BorderSide(color: colors.border, width: 1);
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(controlRadius),
            ),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceAlt,
        selectedColor: colors.accentTint,
        side: BorderSide(color: colors.border, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chipRadius),
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: colors.inkPrimary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.accent,
        foregroundColor: onAccent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.accentTint,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected ? colors.accent : colors.inkMuted,
            size: 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? colors.accent : colors.inkMuted,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.inkPrimary,
        contentTextStyle: TextStyle(
          fontSize: 14,
          color: colors.surface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}

class JournalCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;

  const JournalCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final borderRadius = BorderRadius.circular(AppTheme.cardRadius);
    return Material(
      color: backgroundColor ?? colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: borderColor ?? colors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              child: Padding(padding: padding, child: child),
            )
          : Padding(padding: padding, child: child),
    );
  }
}

class JournalSkeletonList extends StatelessWidget {
  final int cardCount;

  const JournalSkeletonList({super.key, this.cardCount = 3});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: cardCount,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return JournalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SkeletonBar(width: 150, height: 16, color: colors.surfaceAlt),
                  _SkeletonBar(width: 64, height: 22, color: colors.surfaceAlt),
                ],
              ),
              const SizedBox(height: 12),
              _SkeletonBar(
                width: double.infinity,
                height: 12,
                color: colors.surfaceAlt,
              ),
              const SizedBox(height: 8),
              _SkeletonBar(width: 210, height: 12, color: colors.surfaceAlt),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _SkeletonBar({
    required this.width,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      ),
    );
  }
}

class JournalErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const JournalErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return JournalCard(
      backgroundColor: colors.destructive.withValues(alpha: 0.08),
      borderColor: colors.destructive,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.error_outline,
              color: colors.destructive,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Terjadi kesalahan',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.destructive,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(fontSize: 13, color: colors.inkPrimary),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Coba Lagi'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.destructive,
                    side: BorderSide(color: colors.destructive),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class JournalEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const JournalEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return JournalCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.accentTint,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            ),
            child: Icon(icon, color: colors.accent, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: colors.inkMuted),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
                if (secondaryLabel != null && onSecondary != null)
                  OutlinedButton(
                    onPressed: onSecondary,
                    child: Text(secondaryLabel!),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class JournalUncategorizedPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const JournalUncategorizedPill({
    super.key,
    this.label = 'Perlu tag modul/project',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final badge = Container(
      constraints: onTap != null
          ? const BoxConstraints(minHeight: AppTheme.minTapTarget)
          : null,
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: onTap != null ? 10 : 4,
      ),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
        border: Border.all(color: colors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.label_important_outline, size: 15, color: colors.warning),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.warning,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: colors.warning),
          ],
        ],
      ),
    );

    if (onTap == null) return badge;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      child: badge,
    );
  }
}

class JournalHoursBadge extends StatelessWidget {
  final double hours;

  const JournalHoursBadge({super.key, required this.hours});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.accentTint,
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      ),
      child: Text(
        '${hours.toStringAsFixed(1)} jam',
        style: AppTheme.tabularStyle(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.accent,
          ),
        ),
      ),
    );
  }
}
