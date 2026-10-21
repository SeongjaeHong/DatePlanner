import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/date_plan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/attachments.dart';
import '../widgets/place_block.dart';
import 'travel_stay.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({required this.spaceId, this.repository, super.key});
  final String spaceId;
  final PlanRepository? repository;

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  late final PlanRepository _service = widget.repository ?? DatePlanService();
  late Future<List<DatePlan>> _plans = _load();
  DatePlan? _selected;
  bool _includeDeleted = false;

  Future<List<DatePlan>> _load() =>
      _service.listPlans(widget.spaceId, includeDeleted: _includeDeleted);

  void _reload() => setState(() {
        _plans = _load();
      });

  Future<void> _newPlan() async {
    final result = await showDialog<_PlanValues>(
      context: context,
      builder: (_) => const _PlanFormDialog(),
    );
    if (result == null) return;
    try {
      final id = await _service.createPlan(
        spaceId: widget.spaceId,
        title: result.title,
        start: result.start,
        end: result.end,
        notes: result.notes,
      );
      _reload();
      if (!mounted) return;
      final plan = await _service.getPlan(id);
      if (!mounted) return;
      setState(() => _selected = plan);
    } on PostgrestException catch (error) {
      if (kDebugMode) {
        debugPrint('Date plan save failed (${error.code}): ${error.message}');
      }
      if (mounted) _showError(_messageForError(error.message));
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
            'Date plan save failed unexpectedly (${error.runtimeType}).');
      }
      if (mounted) _showError(AppLocalizations.of(context).planSaveError);
    }
  }

  String _messageForError(String raw) {
    final strings = AppLocalizations.of(context);
    if (raw.contains('INVALID_DATE_RANGE')) return strings.planDateRangeError;
    return strings.planSaveError;
  }

  void _showError(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _openPlan(DatePlan plan) async {
    if (plan.deletedAt != null) {
      final strings = AppLocalizations.of(context);
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(strings.restorePlanTitle),
          content: Text(strings.restorePlanBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(strings.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(strings.restore)),
          ],
        ),
      );
      if (yes == true) {
        try {
          await _service.setPlanDeleted(plan, false);
          _reload();
        } catch (_) {
          _showError(strings.planSaveError);
        }
      }
      return;
    }
    setState(() => _selected = plan);
  }

  Widget _planList(AppLocalizations strings, {bool inPane = false}) =>
      FutureBuilder<List<DatePlan>>(
        future: _plans,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
                padding: EdgeInsets.all(AppSpacing.x4),
                child: LoadingSkeleton(lines: 3));
          }
          if (snapshot.hasError) {
            return ErrorState(
                message: strings.plansLoadError,
                retryLabel: strings.retry,
                onRetry: _reload);
          }
          final plans = List<DatePlan>.of(snapshot.data ?? const <DatePlan>[]);
          final today = CalendarDate.fromPicker(DateTime.now());
          plans.sort((a, b) {
            final aRank = _statusRank(a, today);
            final bRank = _statusRank(b, today);
            if (aRank != bRank) return aRank.compareTo(bRank);
            return aRank == 2
                ? b.endDate.compareTo(a.endDate)
                : a.startDate.compareTo(b.startDate);
          });
          return Column(
            children: [
              SectionHeader(
                title: strings.plans,
                trailing: FilledButton.icon(
                  onPressed: _newPlan,
                  icon: const Icon(Icons.add),
                  label: Text(strings.newPlan),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _includeDeleted = !_includeDeleted;
                      _plans = _load();
                    });
                  },
                  icon: Icon(_includeDeleted
                      ? Icons.visibility_off_outlined
                      : Icons.delete_outline),
                  label: Text(_includeDeleted
                      ? strings.hideRemoved
                      : strings.showRemoved),
                ),
              ),
              if (plans.isEmpty)
                Expanded(
                    child: EmptyState(
                  title: _includeDeleted
                      ? strings.noRemovedPlans
                      : strings.noPlans,
                  message: _includeDeleted
                      ? strings.noRemovedPlansBody
                      : strings.noPlansBody,
                  action: _includeDeleted
                      ? null
                      : FilledButton.icon(
                          onPressed: _newPlan,
                          icon: const Icon(Icons.add),
                          label: Text(strings.newPlan)),
                ))
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: plans.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.x3),
                    itemBuilder: (context, index) {
                      final plan = plans[index];
                      final status = _statusFor(plan, today, strings);
                      return PlanCard(
                        selected: inPane && _selected?.id == plan.id,
                        removed: plan.deletedAt != null,
                        title: plan.title,
                        dateRange: _dateRange(plan, strings),
                        statusLabel: status.$1,
                        statusIcon: status.$2,
                        statusColor: status.$3,
                        onTap: () => _openPlan(plan),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      );

  String _dateRange(DatePlan plan, AppLocalizations strings) =>
      '${MaterialLocalizations.of(context).formatMediumDate(plan.startDate.displayDate)} – ${MaterialLocalizations.of(context).formatMediumDate(plan.endDate.displayDate)}';

  int _statusRank(DatePlan plan, CalendarDate today) {
    if (plan.deletedAt != null) return 3;
    if (plan.endDate.compareTo(today) < 0) return 2;
    if (plan.startDate.compareTo(today) > 0) return 1;
    return 0;
  }

  (String, IconData, Color) _statusFor(
      DatePlan plan, CalendarDate today, AppLocalizations strings) {
    final scheme = Theme.of(context).colorScheme;
    if (plan.deletedAt != null) {
      return (strings.planRemoved, Icons.delete_outline, scheme.error);
    }
    if (_statusRank(plan, today) == 2) {
      return (
        strings.planPast,
        Icons.check_circle_outline,
        scheme.onSurfaceVariant
      );
    }
    if (_statusRank(plan, today) == 1) {
      return (strings.planUpcoming, Icons.schedule, scheme.tertiary);
    }
    return (strings.planInProgress, Icons.play_circle_outline, scheme.primary);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < AppLayout.compactBreakpoint
        ? AppSpacing.compactScreen
        : width < AppLayout.expandedBreakpoint
            ? AppSpacing.mediumScreen
            : AppSpacing.expandedScreen;
    if (width < 1200 && _selected != null) {
      return Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _selected = null),
                icon: const Icon(Icons.arrow_back),
                label: Text(strings.backToPlans),
              ),
            ),
            Expanded(
              child: PlanDetailScreen(
                key: ValueKey(_selected!.id),
                plan: _selected!,
                service: _service,
                attachmentsEnabled: widget.repository == null,
                onChanged: _reload,
                onBack: () => setState(() => _selected = null),
              ),
            ),
          ],
        ),
      );
    }
    if (width >= 1200) {
      return Padding(
        padding: EdgeInsets.all(padding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 360, child: _planList(strings, inPane: true)),
            const VerticalDivider(width: AppSpacing.x6),
            Expanded(
              child: _selected == null
                  ? EmptyState(
                      title: strings.selectPlanTitle,
                      message: strings.selectPlanBody)
                  : PlanDetailScreen(
                      key: ValueKey(_selected!.id),
                      plan: _selected!,
                      service: _service,
                      attachmentsEnabled: widget.repository == null,
                      onChanged: _reload,
                      onBack: () => setState(() => _selected = null)),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding:
          EdgeInsets.fromLTRB(padding, AppSpacing.x6, padding, AppSpacing.x4),
      child: _planList(strings),
    );
  }
}

class PlanDetailScreen extends StatefulWidget {
  const PlanDetailScreen(
      {required this.plan,
      required this.service,
      required this.onChanged,
      this.attachmentsEnabled = true,
      this.initialTravel = false,
      this.onBack,
      super.key});
  final DatePlan plan;
  final PlanRepository service;
  final bool attachmentsEnabled;
  final bool initialTravel;
  final VoidCallback onChanged;
  final VoidCallback? onBack;

  @override
  State<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends State<PlanDetailScreen> {
  late bool _showTravel = widget.initialTravel;
  late DatePlan _plan = widget.plan;
  late Future<List<PlanDay>> _days = widget.service.listDays(_plan.id);
  PlanDay? _selectedDay;
  int _refresh = 0;

  void _reload() {
    setState(() {
      _days = widget.service.listDays(_plan.id);
      _refresh++;
    });
    widget.onChanged();
  }

  Future<void> _editPlan() async {
    final values = await showDialog<_PlanValues>(
        context: context, builder: (_) => _PlanFormDialog(plan: _plan));
    if (values == null) return;
    try {
      _plan = await widget.service.updatePlan(_plan,
          title: values.title,
          start: values.start,
          end: values.end,
          notes: values.notes);
      _reload();
    } on PlanningRuleException catch (error) {
      if (mounted) {
        _showError(error.code == 'DAYS_CONTAIN_CARDS'
            ? AppLocalizations.of(context).shortenBlockedError
            : AppLocalizations.of(context).planSaveError);
      }
    } on PlanningConflict catch (_) {
      if (mounted) _showError(AppLocalizations.of(context).planConflictError);
    } catch (_) {
      if (mounted) _showError(AppLocalizations.of(context).planSaveError);
    }
  }

  Future<void> _removePlan() async {
    final strings = AppLocalizations.of(context);
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(strings.removePlanTitle),
              content: Text(strings.removePlanBody),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(strings.cancel)),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(strings.remove)),
              ],
            ));
    if (accepted != true) return;
    try {
      await widget.service.setPlanDeleted(_plan, true);
      widget.onChanged();
      if (mounted && widget.onBack != null) {
        widget.onBack!();
      } else if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) _showError(strings.planSaveError);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
            title: _plan.title,
            trailing: PopupMenuButton<String>(
              tooltip: strings.planActions,
              onSelected: (value) =>
                  value == 'edit' ? _editPlan() : _removePlan(),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(strings.editPlan)),
                PopupMenuItem(value: 'remove', child: Text(strings.removePlan)),
              ],
            )),
        Text(
            '${MaterialLocalizations.of(context).formatMediumDate(_plan.startDate.displayDate)} – ${MaterialLocalizations.of(context).formatMediumDate(_plan.endDate.displayDate)}',
            style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: AppSpacing.x4),
        Wrap(spacing: AppSpacing.x2, runSpacing: AppSpacing.x2, children: [
          ChoiceChip(
              label: Text(strings.itinerary),
              selected: !_showTravel,
              onSelected: (_) => setState(() => _showTravel = false)),
          ChoiceChip(
              label: Text(strings.travelAndStay),
              selected: _showTravel,
              onSelected: (_) => setState(() => _showTravel = true)),
        ]),
        const SizedBox(height: AppSpacing.x4),
        if (_showTravel)
          Expanded(
              child: TravelStayScreen(
                  plan: _plan, attachmentsEnabled: widget.attachmentsEnabled))
        else
          Expanded(
            child: FutureBuilder<List<PlanDay>>(
              future: _days,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LoadingSkeleton(lines: 3);
                }
                if (snapshot.hasError) {
                  return ErrorState(
                      message: strings.planLoadError,
                      retryLabel: strings.retry,
                      onRetry: () => setState(
                          () => _days = widget.service.listDays(_plan.id)));
                }
                final days = snapshot.data ?? const <PlanDay>[];
                if (days.isEmpty) {
                  return EmptyState(
                      title: strings.emptyDaysTitle,
                      message: strings.emptyDaysBody);
                }
                _selectedDay ??= days.first;
                final selected = days.firstWhere(
                    (day) => day.id == _selectedDay!.id,
                    orElse: () => days.first);
                final daySelectorScrollBehavior =
                    ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    ...ScrollConfiguration.of(context).dragDevices,
                    PointerDeviceKind.mouse,
                  },
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (days.length > 1) ...[
                      SizedBox(
                        height: AppTouchTarget.minimum + AppSpacing.x2,
                        child: ScrollConfiguration(
                          behavior: daySelectorScrollBehavior,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: days.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: AppSpacing.x2),
                            itemBuilder: (context, index) {
                              final day = days[index];
                              return ChoiceChip(
                                label: Text(strings.dayLabel(
                                    index + 1,
                                    MaterialLocalizations.of(context)
                                        .formatMediumDate(
                                            day.date.displayDate))),
                                selected: selected.id == day.id,
                                onSelected: (_) => setState(() {
                                  _selectedDay = day;
                                  _refresh++;
                                }),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x3),
                    ],
                    Expanded(
                        child: _DayCards(
                            key: ValueKey('${selected.id}-$_refresh'),
                            day: selected,
                            planId: _plan.id,
                            attachmentsEnabled: widget.attachmentsEnabled,
                            days: days,
                            service: widget.service,
                            onChanged: _reload)),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

class _DayCards extends StatefulWidget {
  const _DayCards(
      {required this.day,
      required this.planId,
      required this.attachmentsEnabled,
      required this.days,
      required this.service,
      required this.onChanged,
      super.key});
  final PlanDay day;
  final String planId;
  final bool attachmentsEnabled;
  final List<PlanDay> days;
  final PlanRepository service;
  final VoidCallback onChanged;

  @override
  State<_DayCards> createState() => _DayCardsState();
}

class _DayCardsState extends State<_DayCards> {
  late Future<List<ActivityCardData>> _cards =
      widget.service.listCards(widget.day.id, includeDeleted: true);
  bool _showRemoved = false;

  void _reload() => setState(() {
        _cards = widget.service.listCards(widget.day.id, includeDeleted: true);
      });

  Future<void> _addCard() async {
    final values = await showDialog<_CardValues>(
        context: context, builder: (_) => const _CardFormDialog());
    if (values == null) return;
    try {
      await widget.service.createCard(
          widget.day.id, values.kind, values.title, values.body,
          placeName: values.placeName,
          placeAddress: values.placeAddress,
          placeLatitude: values.placeLatitude,
          placeLongitude: values.placeLongitude);
      _reload();
    } catch (_) {
      if (mounted) _showError(AppLocalizations.of(context).cardSaveError);
    }
  }

  Future<void> _editCard(ActivityCardData card) async {
    var values = await showDialog<_CardValues>(
        context: context, builder: (_) => _CardFormDialog(card: card));
    if (values == null) return;
    try {
      await widget.service.updateCard(card,
          kind: values.kind,
          title: values.title,
          body: values.body,
          placeName: values.placeName,
          placeAddress: values.placeAddress,
          placeLatitude: values.placeLatitude,
          placeLongitude: values.placeLongitude);
      _reload();
    } on PlanningConflict catch (conflict) {
      if (!mounted) return;
      final strings = AppLocalizations.of(context);
      final keepMine = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(strings.cardConflictTitle),
                content: Text(strings.cardConflictBody),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(strings.useTheirs)),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(strings.keepMine)),
                ],
              ));
      if (keepMine == true) {
        try {
          final latest = ActivityCardData.fromJson(conflict.latest);
          await widget.service.updateCard(latest,
              kind: values.kind,
              title: values.title,
              body: values.body,
              placeName: values.placeName,
              placeAddress: values.placeAddress,
              placeLatitude: values.placeLatitude,
              placeLongitude: values.placeLongitude,
              expectedVersion: latest.version);
          _reload();
        } catch (_) {
          if (mounted) _showError(strings.cardSaveError);
        }
      } else {
        _reload();
      }
    } catch (_) {
      if (mounted) _showError(AppLocalizations.of(context).cardSaveError);
    }
  }

  Future<void> _deleteCard(ActivityCardData card) async {
    final strings = AppLocalizations.of(context);
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(strings.removeCardTitle),
              content: Text(strings.removeCardBody),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(strings.cancel)),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(strings.remove)),
              ],
            ));
    if (accepted != true) return;
    try {
      await widget.service.setCardDeleted(card, true);
      _reload();
    } catch (_) {
      if (mounted) _showError(strings.cardSaveError);
    }
  }

  Future<void> _restoreCard(ActivityCardData card) async {
    try {
      await widget.service.setCardDeleted(card, false);
      _reload();
    } catch (_) {
      if (mounted) _showError(AppLocalizations.of(context).cardSaveError);
    }
  }

  Future<void> _move(ActivityCardData card, int index, String dayId) async {
    try {
      await widget.service.moveCard(card, dayId, index);
      _reload();
      widget.onChanged();
    } catch (_) {
      if (mounted) _showError(AppLocalizations.of(context).cardMoveError);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return FutureBuilder<List<ActivityCardData>>(
      future: _cards,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingSkeleton(lines: 3);
        }
        if (snapshot.hasError) {
          return ErrorState(
              message: strings.cardsLoadError,
              retryLabel: strings.retry,
              onRetry: _reload);
        }
        final all = snapshot.data ?? const <ActivityCardData>[];
        final cards = all
            .where((card) => _showRemoved || card.deletedAt == null)
            .toList();
        if (all.isEmpty || cards.isEmpty) {
          return EmptyState(
            dense: true,
            title:
                all.isNotEmpty ? strings.noActiveCards : strings.emptyDayTitle,
            message: all.isNotEmpty
                ? strings.noActiveCardsBody
                : strings.emptyDayBody,
            action: Column(mainAxisSize: MainAxisSize.min, children: [
              FilledButton.icon(
                  onPressed: _addCard,
                  icon: const Icon(Icons.add),
                  label: Text(strings.addCard)),
              if (all.isNotEmpty)
                TextButton(
                    onPressed: () => setState(() => _showRemoved = true),
                    child: Text(strings.showRemoved)),
            ]),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
                title: strings.dayFeed,
                trailing: Wrap(children: [
                  if (all.any((card) => card.deletedAt != null))
                    TextButton(
                        onPressed: () =>
                            setState(() => _showRemoved = !_showRemoved),
                        child: Text(_showRemoved
                            ? strings.hideRemoved
                            : strings.showRemoved)),
                  FilledButton.icon(
                      onPressed: _addCard,
                      icon: const Icon(Icons.add),
                      label: Text(strings.addCard)),
                ])),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: AppSpacing.x8),
                itemCount: cards.length,
                onReorderItem: (oldIndex, newIndex) {
                  final card = cards[oldIndex];
                  _move(card, newIndex, widget.day.id);
                },
                itemBuilder: (context, index) {
                  final card = cards[index];
                  final removed = card.deletedAt != null;
                  return ActivityFeedCard(
                    key: ValueKey(card.id),
                    removed: removed,
                    title: card.title.isEmpty
                        ? _kindLabel(strings, card.kind)
                        : card.title,
                    body: card.body.isEmpty
                        ? _kindLabel(strings, card.kind)
                        : card.body,
                    place: card.placeName == null && card.placeAddress == null
                        ? null
                        : PlaceBlock(
                            name: card.placeName,
                            address: card.placeAddress,
                            latitude: card.placeLatitude,
                            longitude: card.placeLongitude,
                          ),
                    extra: removed || !widget.attachmentsEnabled
                        ? null
                        : CardPhotos(planId: widget.planId, cardId: card.id),
                    dragHandle: ReorderableDragStartListener(
                        index: index,
                        child: const SizedBox(
                            width: AppTouchTarget.minimum,
                            height: AppTouchTarget.minimum,
                            child: Icon(Icons.drag_handle))),
                    actions: PopupMenuButton<String>(
                      tooltip: strings.cardActions,
                      onSelected: (action) {
                        switch (action) {
                          case 'edit':
                            _editCard(card);
                          case 'up':
                            if (index > 0) {
                              _move(card, index - 1, widget.day.id);
                            }
                          case 'down':
                            if (index + 1 < cards.length) {
                              _move(card, index + 1, widget.day.id);
                            }
                          case 'day':
                            _selectMoveDay(card);
                          case 'restore':
                            _restoreCard(card);
                          case 'remove':
                            _deleteCard(card);
                        }
                      },
                      itemBuilder: (_) => removed
                          ? [
                              PopupMenuItem(
                                  value: 'restore',
                                  child: Text(strings.restore))
                            ]
                          : [
                              PopupMenuItem(
                                  value: 'edit', child: Text(strings.editCard)),
                              if (index > 0)
                                PopupMenuItem(
                                    value: 'up', child: Text(strings.moveUp)),
                              if (index + 1 < cards.length)
                                PopupMenuItem(
                                    value: 'down',
                                    child: Text(strings.moveDown)),
                              if (widget.days.length > 1)
                                PopupMenuItem(
                                    value: 'day',
                                    child: Text(strings.moveToDay)),
                              PopupMenuItem(
                                  value: 'remove',
                                  child: Text(strings.removeCard)),
                            ],
                    ),
                    onTap: removed
                        ? () => _restoreCard(card)
                        : () => _editCard(card),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectMoveDay(ActivityCardData card) async {
    final strings = AppLocalizations.of(context);
    final day = await showDialog<PlanDay>(
        context: context,
        builder: (context) => SimpleDialog(
              title: Text(strings.moveToDay),
              children: [
                for (var i = 0; i < widget.days.length; i++)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, widget.days[i]),
                    child: Text(strings.dayLabel(
                        i + 1,
                        MaterialLocalizations.of(context).formatMediumDate(
                            widget.days[i].date.displayDate))),
                  )
              ],
            ));
    if (day != null) {
      final cards = await widget.service.listCards(day.id);
      await _move(card, cards.length, day.id);
    }
  }
}

class _PlanValues {
  const _PlanValues(this.title, this.start, this.end, this.notes);
  final String title;
  final CalendarDate start;
  final CalendarDate end;
  final String notes;
}

class _PlanFormDialog extends StatefulWidget {
  const _PlanFormDialog({this.plan});
  final DatePlan? plan;
  @override
  State<_PlanFormDialog> createState() => _PlanFormDialogState();
}

class _PlanFormDialogState extends State<_PlanFormDialog> {
  late final _title = TextEditingController(text: widget.plan?.title ?? '');
  late final _notes = TextEditingController(text: widget.plan?.notes ?? '');
  late CalendarDate _start =
      widget.plan?.startDate ?? CalendarDate.fromPicker(DateTime.now());
  late CalendarDate _end =
      widget.plan?.endDate ?? CalendarDate.fromPicker(DateTime.now());

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final current = start ? _start : _end;
    final selected = await showDatePicker(
      context: context,
      initialDate: current.displayDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (selected == null) return;
    setState(() {
      if (start) {
        _start = CalendarDate.fromPicker(selected);
      } else {
        _end = CalendarDate.fromPicker(selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.plan == null ? strings.newPlan : strings.editPlan),
      content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: _title,
            maxLength: 120,
            decoration: InputDecoration(labelText: strings.planTitleLabel)),
        const SizedBox(height: AppSpacing.x3),
        Wrap(spacing: AppSpacing.x2, children: [
          OutlinedButton.icon(
              onPressed: () => _pick(true),
              icon: const Icon(Icons.calendar_today),
              label: Text(
                  '${strings.startDateLabel}: ${MaterialLocalizations.of(context).formatMediumDate(_start.displayDate)}')),
          OutlinedButton.icon(
              onPressed: () => _pick(false),
              icon: const Icon(Icons.event),
              label: Text(
                  '${strings.endDateLabel}: ${MaterialLocalizations.of(context).formatMediumDate(_end.displayDate)}')),
        ]),
        const SizedBox(height: AppSpacing.x3),
        TextField(
            controller: _notes,
            maxLines: 3,
            maxLength: 4000,
            decoration: InputDecoration(labelText: strings.planNotesLabel)),
      ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.cancel)),
        FilledButton(
            onPressed: () {
              if (_title.text.trim().isEmpty || _end.compareTo(_start) < 0) {
                return;
              }
              Navigator.pop(
                  context, _PlanValues(_title.text, _start, _end, _notes.text));
            },
            child: Text(strings.save)),
      ],
    );
  }
}

class _CardValues {
  const _CardValues(this.kind, this.title, this.body, this.placeName,
      this.placeAddress, this.placeLatitude, this.placeLongitude);
  final String kind;
  final String title;
  final String body;
  final String? placeName;
  final String? placeAddress;
  final double? placeLatitude;
  final double? placeLongitude;
}

class _CardFormDialog extends StatefulWidget {
  const _CardFormDialog({this.card});
  final ActivityCardData? card;
  @override
  State<_CardFormDialog> createState() => _CardFormDialogState();
}

class _CardFormDialogState extends State<_CardFormDialog> {
  late String _kind = widget.card?.kind ?? 'activity';
  late final _title = TextEditingController(text: widget.card?.title ?? '');
  late final _body = TextEditingController(text: widget.card?.body ?? '');
  late final _placeName =
      TextEditingController(text: widget.card?.placeName ?? '');
  late final _placeAddress =
      TextEditingController(text: widget.card?.placeAddress ?? '');
  late final _latitude =
      TextEditingController(text: widget.card?.placeLatitude?.toString() ?? '');
  late final _longitude = TextEditingController(
      text: widget.card?.placeLongitude?.toString() ?? '');
  bool _showPlace = false;

  @override
  void initState() {
    super.initState();
    _showPlace =
        widget.card?.placeName != null || widget.card?.placeAddress != null;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _placeName.dispose();
    _placeAddress.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.card == null ? strings.addCard : strings.editCard),
      content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(
          initialValue: _kind,
          decoration: InputDecoration(
              labelText: strings.cardKindLabel(_kindLabel(strings, _kind))),
          items: [
            for (final value in ['note', 'activity', 'travel'])
              DropdownMenuItem(
                  value: value, child: Text(_kindLabel(strings, value)))
          ],
          onChanged: (value) => setState(() => _kind = value ?? _kind),
        ),
        const SizedBox(height: AppSpacing.x3),
        TextField(
            controller: _title,
            maxLength: 120,
            decoration: InputDecoration(labelText: strings.cardTitleLabel)),
        const SizedBox(height: AppSpacing.x3),
        TextField(
            controller: _body,
            minLines: 2,
            maxLines: 6,
            maxLength: 4000,
            decoration: InputDecoration(labelText: strings.cardTextLabel)),
        const SizedBox(height: AppSpacing.x3),
        if (!_showPlace)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _showPlace = true),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: Text(strings.addPlace),
            ),
          )
        else ...[
          TextField(
              controller: _placeName,
              maxLength: 160,
              decoration: InputDecoration(labelText: strings.placeName)),
          const SizedBox(height: AppSpacing.x2),
          TextField(
              controller: _placeAddress,
              maxLength: 500,
              decoration: InputDecoration(labelText: strings.placeAddress)),
          const SizedBox(height: AppSpacing.x2),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _latitude,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration:
                        InputDecoration(labelText: strings.placeLatitude))),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
                child: TextField(
                    controller: _longitude,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration:
                        InputDecoration(labelText: strings.placeLongitude))),
          ]),
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _showPlace = false;
                  _placeName.clear();
                  _placeAddress.clear();
                  _latitude.clear();
                  _longitude.clear();
                }),
                icon: const Icon(Icons.delete_outline),
                label: Text(strings.removePlace),
              )),
        ],
      ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.cancel)),
        FilledButton(
            onPressed: () {
              final lat = _latitude.text.trim().isEmpty
                  ? null
                  : double.tryParse(_latitude.text.trim());
              final lon = _longitude.text.trim().isEmpty
                  ? null
                  : double.tryParse(_longitude.text.trim());
              final hasBadCoordinates =
                  (_latitude.text.trim().isNotEmpty && lat == null) ||
                      (_longitude.text.trim().isNotEmpty && lon == null) ||
                      ((lat == null) != (lon == null)) ||
                      (lat != null &&
                          (lat < -90 || lat > 90 || lon! < -180 || lon > 180));
              if (_showPlace &&
                  (_placeName.text.trim().isEmpty &&
                          _placeAddress.text.trim().isEmpty ||
                      hasBadCoordinates)) {
                return;
              }
              Navigator.pop(
                  context,
                  _CardValues(
                    _kind,
                    _title.text.trim(),
                    _body.text.trim(),
                    _showPlace && _placeName.text.trim().isNotEmpty
                        ? _placeName.text.trim()
                        : null,
                    _showPlace && _placeAddress.text.trim().isNotEmpty
                        ? _placeAddress.text.trim()
                        : null,
                    _showPlace ? lat : null,
                    _showPlace ? lon : null,
                  ));
            },
            child: Text(strings.save)),
      ],
    );
  }
}

String _kindLabel(AppLocalizations strings, String kind) => switch (kind) {
      'note' => strings.noteKind,
      'travel' => strings.travelKind,
      _ => strings.activityKind,
    };
