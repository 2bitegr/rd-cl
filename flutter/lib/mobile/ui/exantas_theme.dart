import 'package:flutter/material.dart';

/// Design tokens for the mobile Exantas surfaces. Desktop keeps `MyTheme`.
@immutable
class ExantasTokens extends ThemeExtension<ExantasTokens> {
  const ExantasTokens({
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.inputBorder,
    required this.text,
    required this.textSecondary,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
  });

  final Color surface,
      surfaceAlt,
      border,
      inputBorder,
      text,
      textSecondary,
      accent,
      accentSoft,
      success,
      successSoft,
      warning,
      warningSoft,
      danger,
      dangerSoft;

  static const radiusSm = 8.0, radiusMd = 12.0, radiusLg = 16.0, radiusPill = 999.0;
  static const space1 = 4.0,
      space2 = 8.0,
      space3 = 12.0,
      space4 = 16.0,
      space6 = 24.0,
      space8 = 32.0;
  static const gutter = 16.0;
  static const minTouch = 48.0;

  static const light = ExantasTokens(
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF6F7F9),
    border: Color(0xFFE3E6EB),
    inputBorder: Color(0xFF8A94A3),
    text: Color(0xFF111827),
    textSecondary: Color(0xFF5B6472),
    accent: Color(0xFF0066E6),
    accentSoft: Color(0xFFEAF3FF),
    success: Color(0xFF067647),
    successSoft: Color(0xFFECFDF3),
    warning: Color(0xFFB54708),
    warningSoft: Color(0xFFFFF4E5),
    danger: Color(0xFFB42318),
    dangerSoft: Color(0xFFFEF3F2),
  );

  static const dark = ExantasTokens(
    surface: Color(0xFF14181F),
    surfaceAlt: Color(0xFF0C0F14),
    border: Color(0xFF2A303A),
    inputBorder: Color(0xFF7D8797),
    text: Color(0xFFF3F4F6),
    textSecondary: Color(0xFFA6AEBB),
    accent: Color(0xFF5CA3FF),
    accentSoft: Color(0xFF15263D),
    success: Color(0xFF47CD89),
    successSoft: Color(0xFF0E2A1D),
    warning: Color(0xFFFEB273),
    warningSoft: Color(0xFF33210F),
    danger: Color(0xFFF97066),
    dangerSoft: Color(0xFF331513),
  );

  @override
  ExantasTokens copyWith() => this;

  @override
  ExantasTokens lerp(ThemeExtension<ExantasTokens>? other, double t) =>
      other is! ExantasTokens ? this : (t < .5 ? this : other);
}

extension ExantasContext on BuildContext {
  ExantasTokens get ex =>
      Theme.of(this).extension<ExantasTokens>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? ExantasTokens.dark
          : ExantasTokens.light);
}

class ExantasTheme {
  static ThemeData light({List<ThemeExtension<ThemeExtension<dynamic>>> extra = const []}) =>
      _build(ExantasTokens.light, Brightness.light, extra);
  static ThemeData dark({List<ThemeExtension<ThemeExtension<dynamic>>> extra = const []}) =>
      _build(ExantasTokens.dark, Brightness.dark, extra);

  static ThemeData _build(ExantasTokens t, Brightness b,
      List<ThemeExtension<ThemeExtension<dynamic>>> extra) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme(
      brightness: b,
      primary: t.accent,
      onPrimary: dark ? const Color(0xFF00172E) : Colors.white,
      primaryContainer: t.accentSoft,
      onPrimaryContainer: t.accent,
      secondary: t.accent,
      onSecondary: dark ? const Color(0xFF00172E) : Colors.white,
      secondaryContainer: t.accentSoft,
      onSecondaryContainer: t.accent,
      error: t.danger,
      onError: dark ? const Color(0xFF2A0A07) : Colors.white,
      errorContainer: t.dangerSoft,
      onErrorContainer: t.danger,
      surface: t.surface,
      onSurface: t.text,
      onSurfaceVariant: t.textSecondary,
      outline: t.inputBorder,
      outlineVariant: t.border,
      surfaceContainerLowest: t.surface,
      surfaceContainerLow: t.surfaceAlt,
      surfaceContainer: t.surfaceAlt,
      surfaceContainerHigh: t.surfaceAlt,
      surfaceContainerHighest: t.border,
      shadow: Colors.black,
      scrim: Colors.black,
    );
    TextStyle s(double size, FontWeight w, [Color? c, double h = 1.3]) =>
        TextStyle(fontSize: size, fontWeight: w, color: c ?? t.text, height: h);
    OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(ExantasTokens.radiusMd),
        borderSide: BorderSide(color: c, width: w));
    final shape12 = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ExantasTokens.radiusMd));
    const minSize = Size(ExantasTokens.minTouch, ExantasTokens.minTouch);
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.surfaceAlt,
      canvasColor: t.surface,
      dividerColor: t.border,
      dialogBackgroundColor: t.surface,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: TextTheme(
        titleLarge: s(20, FontWeight.w600),
        titleMedium: s(16, FontWeight.w600),
        titleSmall: s(14, FontWeight.w600),
        bodyLarge: s(16, FontWeight.w400, null, 1.4),
        bodyMedium: s(14, FontWeight.w400, null, 1.4),
        bodySmall: s(13, FontWeight.w400, t.textSecondary, 1.35),
        labelLarge: s(14, FontWeight.w500),
        labelMedium: s(12, FontWeight.w500, t.textSecondary),
        labelSmall: s(12, FontWeight.w500, t.textSecondary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: t.surface,
        foregroundColor: t.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: s(20, FontWeight.w600),
        shape: Border(bottom: BorderSide(color: t.border)),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ExantasTokens.radiusLg),
            side: BorderSide(color: t.border)),
      ),
      dividerTheme: DividerThemeData(color: t.border, space: 1, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: field(t.inputBorder),
        enabledBorder: field(t.inputBorder),
        disabledBorder: field(t.border),
        focusedBorder: field(t.accent, 2),
        errorBorder: field(t.danger),
        focusedErrorBorder: field(t.danger, 2),
        hintStyle: s(14, FontWeight.w400, t.textSecondary),
        labelStyle: s(14, FontWeight.w400, t.textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size(ExantasTokens.minTouch, 52),
              shape: shape12,
              textStyle: s(16, FontWeight.w600))),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
              minimumSize: minSize, shape: shape12, elevation: 0)),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              minimumSize: minSize,
              shape: shape12,
              side: BorderSide(color: t.inputBorder),
              textStyle: s(14, FontWeight.w500))),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              minimumSize: minSize,
              shape: shape12,
              textStyle: s(14, FontWeight.w500))),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(minimumSize: minSize)),
      listTileTheme: ListTileThemeData(
          minVerticalPadding: 8,
          iconColor: t.textSecondary,
          titleTextStyle: s(14, FontWeight.w500),
          subtitleTextStyle: s(13, FontWeight.w400, t.textSecondary)),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: t.accentSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((st) => s(12,
            FontWeight.w500,
            st.contains(WidgetState.selected) ? t.accent : t.textSecondary)),
        iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(
            size: 24,
            color:
                st.contains(WidgetState.selected) ? t.accent : t.textSecondary)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: t.surface,
        indicatorColor: t.accentSoft,
        selectedIconTheme: IconThemeData(color: t.accent),
        unselectedIconTheme: IconThemeData(color: t.textSecondary),
        selectedLabelTextStyle: s(12, FontWeight.w500, t.accent),
        unselectedLabelTextStyle: s(12, FontWeight.w500, t.textSecondary),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(
                  Size(ExantasTokens.minTouch, ExantasTokens.minTouch)),
              side: WidgetStatePropertyAll(BorderSide(color: t.inputBorder)),
              backgroundColor: WidgetStateProperty.resolveWith((st) =>
                  st.contains(WidgetState.selected) ? t.accentSoft : t.surface),
              foregroundColor: WidgetStateProperty.resolveWith((st) =>
                  st.contains(WidgetState.selected) ? t.accent : t.text))),
      dialogTheme: DialogTheme(
          backgroundColor: t.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
              horizontal: ExantasTokens.gutter, vertical: 24),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ExantasTokens.radiusLg),
              side: BorderSide(color: t.border)),
          titleTextStyle: s(20, FontWeight.w600),
          contentTextStyle: s(14, FontWeight.w400, null, 1.4)),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: t.surface,
          surfaceTintColor: Colors.transparent,
          showDragHandle: false,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(ExantasTokens.radiusLg)))),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: dark ? t.border : t.text,
          contentTextStyle: s(14, FontWeight.w400, dark ? t.text : t.surface),
          shape: shape12),
      extensions: <ThemeExtension<ThemeExtension<dynamic>>>[t, ...extra],
    );
  }
}
