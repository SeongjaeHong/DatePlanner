import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_date_planner/theme/app_theme.dart';

void main() {
  test('documented light and derived dark text pairs meet 4.5:1 contrast', () {
    const pairs = <(Color, Color)>[
      (AppColors.onSurface, AppColors.background),
      (AppColors.onSurfaceVariant, AppColors.background),
      (AppColors.primary, AppColors.background),
      (AppColors.onPrimary, AppColors.primary),
      (AppColors.onPrimaryContainer, AppColors.primaryContainer),
      (AppColors.travel, AppColors.background),
      (AppColors.onTravelContainer, AppColors.travelContainer),
      (AppColors.stay, AppColors.background),
      (AppColors.onStayContainer, AppColors.stayContainer),
      (AppColors.success, AppColors.surface),
      (AppColors.warning, AppColors.background),
      (AppColors.error, AppColors.background),
      (AppColors.info, AppColors.background),
      (AppDarkColors.onSurface, AppDarkColors.background),
      (AppDarkColors.onSurfaceVariant, AppDarkColors.surface),
      (AppDarkColors.primary, AppDarkColors.background),
      (AppDarkColors.onPrimary, AppDarkColors.primary),
      (AppDarkColors.onPrimaryContainer, AppDarkColors.primaryContainer),
      (AppDarkColors.travel, AppDarkColors.background),
      (AppDarkColors.onTravelContainer, AppDarkColors.travelContainer),
      (AppDarkColors.stay, AppDarkColors.background),
      (AppDarkColors.onStayContainer, AppDarkColors.stayContainer),
      (AppDarkColors.success, AppDarkColors.surface),
      (AppDarkColors.warning, AppDarkColors.background),
      (AppDarkColors.error, AppDarkColors.background),
      (AppDarkColors.info, AppDarkColors.background),
      (AppDarkColors.onSuccessContainer, AppDarkColors.successContainer),
      (AppDarkColors.onWarningContainer, AppDarkColors.warningContainer),
      (AppDarkColors.onErrorContainer, AppDarkColors.errorContainer),
      (AppDarkColors.onInfoContainer, AppDarkColors.infoContainer),
    ];
    for (final (foreground, background) in pairs) {
      expect(
        _contrast(foreground, background),
        greaterThanOrEqualTo(4.5),
        reason: '$foreground on $background',
      );
    }
    expect(
      _contrast(AppColors.outline, AppColors.surface),
      greaterThanOrEqualTo(3),
    );
  });
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}
