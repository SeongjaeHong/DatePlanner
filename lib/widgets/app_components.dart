import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.trailing, super.key});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.x3),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.message,
    this.action,
    this.dense = false,
    super.key,
  });
  final String title;
  final String message;
  final Widget? action;
  final bool dense;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.formColumn),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(dense ? AppSpacing.x2 : AppSpacing.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: AppIconSize.medium,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                SizedBox(height: dense ? AppSpacing.x2 : AppSpacing.x3),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: dense ? AppSpacing.x1 : AppSpacing.x2),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                if (action != null) ...[
                  SizedBox(height: dense ? AppSpacing.x2 : AppSpacing.x4),
                  action!,
                ],
              ],
            ),
          ),
        ),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
    super.key,
  });
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                size: AppIconSize.medium,
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.x3),
              OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ),
        ),
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
    super.key,
  });
  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(icon, size: AppIconSize.small, color: foreground),
        label: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: foreground),
        ),
        backgroundColor: background,
        side: BorderSide.none,
      );
}

class PlanCard extends StatelessWidget {
  const PlanCard({
    required this.title,
    required this.dateRange,
    required this.statusLabel,
    required this.statusIcon,
    required this.statusColor,
    required this.selected,
    required this.removed,
    required this.onTap,
    super.key,
  });

  final String title;
  final String dateRange;
  final String statusLabel;
  final IconData statusIcon;
  final Color statusColor;
  final bool selected;
  final bool removed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          selected: selected,
          leading: Icon(removed ? Icons.restore : Icons.favorite_outline),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dateRange),
              StatusChip(
                icon: statusIcon,
                label: statusLabel,
                foreground: statusColor,
                background:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}

class ActivityFeedCard extends StatelessWidget {
  const ActivityFeedCard({
    required this.title,
    required this.body,
    required this.dragHandle,
    required this.actions,
    required this.removed,
    required this.onTap,
    this.place,
    this.extra,
    super.key,
  });

  final String title;
  final String body;
  final Widget dragHandle;
  final Widget actions;
  final bool removed;
  final VoidCallback onTap;
  final Widget? place;
  final Widget? extra;

  @override
  Widget build(BuildContext context) => Card(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            leading: dragHandle,
            title: Text(title),
            subtitle: Text(body, maxLines: 3, overflow: TextOverflow.ellipsis),
            trailing: actions,
            onTap: onTap,
            enabled: !removed,
          ),
          if (place != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x4, 0, AppSpacing.x4, AppSpacing.x4),
              child: place,
            ),
          if (extra != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x4, 0, AppSpacing.x4, AppSpacing.x4),
              child: extra,
            ),
        ]),
      );
}

class AppBanner extends StatelessWidget {
  const AppBanner({
    required this.message,
    required this.icon,
    required this.color,
    super.key,
  });
  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.x3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: AppOpacity.bannerTint),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child:
                  Text(message, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      );
}

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({this.lines = 3, super.key});
  final int lines;

  @override
  Widget build(BuildContext context) => Column(
        children: List.generate(
          lines,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.x3),
            child: Container(
              height: AppTouchTarget.minimum,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
            ),
          ),
        ),
      );
}

class IconButton48 extends StatelessWidget {
  const IconButton48({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints(
          minWidth: AppTouchTarget.minimum,
          minHeight: AppTouchTarget.minimum,
        ),
      );
}

class UnfinishedDestination extends StatelessWidget {
  const UnfinishedDestination({
    required this.title,
    required this.message,
    super.key,
  });
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => EmptyState(
        title: title,
        message: message,
        action: StatusChip(
          icon: Icons.hourglass_empty,
          label: AppLocalizations.of(context).notAvailableYet,
          foreground: Theme.of(context).colorScheme.onSurfaceVariant,
          background: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      );
}
