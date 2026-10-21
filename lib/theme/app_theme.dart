import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFFFBF7F5);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF4EDEA);
  static const onSurface = Color(0xFF1E1A1B);
  static const onSurfaceVariant = Color(0xFF5A5155);
  static const primary = Color(0xFFA8174A);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFFFD9E3);
  static const onPrimaryContainer = Color(0xFF3F0020);
  static const travel = Color(0xFF00626A);
  static const travelContainer = Color(0xFFCDEDF0);
  static const onTravelContainer = Color(0xFF00363A);
  static const stay = Color(0xFF7A5200);
  static const stayContainer = Color(0xFFFFE7B8);
  static const onStayContainer = Color(0xFF3E2A00);
  static const outline = Color(0xFF857A7F);
  static const divider = Color(0xFFE0D6D2);
  static const success = Color(0xFF1E6B3A);
  static const successContainer = Color(0xFFD7F0DD);
  static const warning = Color(0xFF7A4B00);
  static const warningContainer = Color(0xFFFFEBC2);
  static const error = Color(0xFFB3261E);
  static const errorContainer = Color(0xFFFCDAD6);
  static const info = Color(0xFF1D58A6);
  static const infoContainer = Color(0xFFD8E6FA);
}

abstract final class AppDarkColors {
  static const background = Color(0xFF161213);
  static const surface = Color(0xFF201B1C);
  static const surfaceAlt = Color(0xFF2B2425);
  static const onSurface = Color(0xFFEDE0E2);
  static const onSurfaceVariant = Color(0xFFC9BCBF);
  static const primary = Color(0xFFFFB1C8);
  static const onPrimary = Color(0xFF5E0A2E);
  static const primaryContainer = Color(0xFF7D1E44);
  static const onPrimaryContainer = Color(0xFFFFD9E3);
  static const travel = Color(0xFF7FD3DB);
  static const travelContainer = Color(0xFF00363A);
  static const onTravelContainer = Color(0xFFCDEDF0);
  static const stay = Color(0xFFF2BE62);
  static const stayContainer = Color(0xFF3E2A00);
  static const onStayContainer = Color(0xFFFFE7B8);
  static const outline = Color(0xFF988C90);
  static const divider = Color(0xFF3A3234);
  static const success = Color(0xFF8FD7A3);
  static const successContainer = Color(0xFF12351F);
  static const onSuccessContainer = Color(0xFFD7F0DD);
  static const warning = Color(0xFFF2BE62);
  static const warningContainer = Color(0xFF493000);
  static const onWarningContainer = Color(0xFFFFEBC2);
  static const error = Color(0xFFFFB4AB);
  static const onError = Color(0xFF5F1411);
  static const errorContainer = Color(0xFF7F1D1D);
  static const onErrorContainer = Color(0xFFFCDAD6);
  static const info = Color(0xFFA9C8F5);
  static const infoContainer = Color(0xFF17345D);
  static const onInfoContainer = Color(0xFFD8E6FA);
}

abstract final class AppSpacing {
  static const xHalf = 2.0;
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x12 = 48.0;
  static const compactScreen = x4;
  static const mediumScreen = x6;
  static const expandedScreen = x8;
  static const cardPadding = x4;
  static const feedGap = x3;
}

abstract final class AppRadius {
  static const small = 8.0;
  static const card = 12.0;
  static const pill = 999.0;
}

abstract final class AppTypeScale {
  static const displaySize = 28.0;
  static const titleLargeSize = 22.0;
  static const titleMediumSize = 18.0;
  static const bodyLargeSize = 16.0;
  static const bodyMediumSize = 14.0;
  static const labelSize = 12.0;
}

abstract final class AppLayout {
  static const compactBreakpoint = 600.0;
  static const expandedBreakpoint = 1024.0;
  static const readingColumn = 720.0;
  static const formColumn = 480.0;
  static const signInColumn = 440.0;
  static const welcomeColumn = 520.0;
  static const sidebarWidth = 228.0;
}

abstract final class AppTouchTarget {
  static const minimum = 48.0;
}

abstract final class AppIconSize {
  static const small = 18.0;
  static const medium = 28.0;
  static const large = 36.0;
  static const hero = 40.0;
}

abstract final class AppNavigationMetrics {
  static const bottomBarHeight = 80.0;
}

abstract final class AppOpacity {
  static const bannerTint = 0.12;
}

abstract final class AppTheme {
  static ThemeData get light => _build(dark: false);
  static ThemeData get dark => _build(dark: true);

  static ThemeData _build({required bool dark}) {
    final colorScheme = ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: dark ? AppDarkColors.primary : AppColors.primary,
      onPrimary: dark ? AppDarkColors.onPrimary : AppColors.onPrimary,
      primaryContainer: dark
          ? AppDarkColors.primaryContainer
          : AppColors.primaryContainer,
      onPrimaryContainer: dark
          ? AppDarkColors.onPrimaryContainer
          : AppColors.onPrimaryContainer,
      secondary: dark ? AppDarkColors.travel : AppColors.travel,
      onSecondary: dark
          ? AppDarkColors.onTravelContainer
          : AppColors.onTravelContainer,
      secondaryContainer: dark
          ? AppDarkColors.travelContainer
          : AppColors.travelContainer,
      onSecondaryContainer: dark
          ? AppDarkColors.onTravelContainer
          : AppColors.onTravelContainer,
      tertiary: dark ? AppDarkColors.stay : AppColors.stay,
      onTertiary: dark
          ? AppDarkColors.onStayContainer
          : AppColors.onStayContainer,
      tertiaryContainer: dark
          ? AppDarkColors.stayContainer
          : AppColors.stayContainer,
      onTertiaryContainer: dark
          ? AppDarkColors.onStayContainer
          : AppColors.onStayContainer,
      error: dark ? AppDarkColors.error : AppColors.error,
      onError: dark ? AppDarkColors.onError : AppColors.surface,
      errorContainer: dark
          ? AppDarkColors.errorContainer
          : AppColors.errorContainer,
      onErrorContainer: dark
          ? AppDarkColors.onErrorContainer
          : AppColors.onSurface,
      surface: dark ? AppDarkColors.surface : AppColors.surface,
      onSurface: dark ? AppDarkColors.onSurface : AppColors.onSurface,
      onSurfaceVariant: dark
          ? AppDarkColors.onSurfaceVariant
          : AppColors.onSurfaceVariant,
      outline: dark ? AppDarkColors.outline : AppColors.outline,
      outlineVariant: dark ? AppDarkColors.divider : AppColors.divider,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: dark ? AppColors.surface : AppDarkColors.surface,
      onInverseSurface: dark ? AppColors.onSurface : AppDarkColors.onSurface,
      inversePrimary: dark ? AppColors.primary : AppDarkColors.primary,
      surfaceTint: dark ? AppDarkColors.primary : AppColors.primary,
    );
    final text = dark ? AppDarkColors.onSurface : AppColors.onSurface;
    final secondaryText = dark
        ? AppDarkColors.onSurfaceVariant
        : AppColors.onSurfaceVariant;
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: dark
          ? AppDarkColors.background
          : AppColors.background,
      dividerColor: dark ? AppDarkColors.divider : AppColors.divider,
      textTheme: TextTheme(
        displaySmall: TextStyle(
          fontSize: AppTypeScale.displaySize,
          height: 36 / 28,
          fontWeight: FontWeight.w700,
          color: text,
        ),
        titleLarge: TextStyle(
          fontSize: AppTypeScale.titleLargeSize,
          height: 28 / 22,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        titleMedium: TextStyle(
          fontSize: AppTypeScale.titleMediumSize,
          height: 24 / 18,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        bodyLarge: TextStyle(
          fontSize: AppTypeScale.bodyLargeSize,
          height: 24 / 16,
          color: text,
        ),
        bodyMedium: TextStyle(
          fontSize: AppTypeScale.bodyMediumSize,
          height: 20 / 14,
          color: secondaryText,
        ),
        labelLarge: TextStyle(
          fontSize: AppTypeScale.labelSize,
          height: 16 / 12,
          fontWeight: FontWeight.w600,
          color: secondaryText,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? AppDarkColors.surface : AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x4,
          vertical: AppSpacing.x4,
        ),
      ),
      cardTheme: CardThemeData(
        color: dark ? AppDarkColors.surface : AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: AppNavigationMetrics.bottomBarHeight,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: AppTypeScale.labelSize, color: secondaryText),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: colorScheme.onPrimaryContainer),
      ),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}
