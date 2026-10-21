import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/space_lifecycle_service.dart';
import '../theme/app_theme.dart';

class SpaceSettingsScreen extends StatefulWidget {
  const SpaceSettingsScreen({
    required this.memberCount,
    required this.onSpaceChanged,
    this.lifecycleService,
    super.key,
  });

  final int memberCount;
  final Future<void> Function() onSpaceChanged;
  final SpaceLifecycleActions? lifecycleService;

  @override
  State<SpaceSettingsScreen> createState() => _SpaceSettingsScreenState();
}

class _SpaceSettingsScreenState extends State<SpaceSettingsScreen> {
  late final SpaceLifecycleActions _service =
      widget.lifecycleService ?? const SpaceLifecycleService();
  late int _memberCount = widget.memberCount;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.x4),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
            child: Text(strings.settingsSpaceMemberCount(_memberCount)),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: Text(strings.signOut),
              onTap: _busy ? null : _signOut,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.exit_to_app),
              title: Text(strings.leaveSpace),
              subtitle: Text(strings.leaveSpaceSubtitle),
              onTap: _busy ? null : _confirmLeave,
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.delete_forever,
                  color: Theme.of(context).colorScheme.error),
              title: Text(strings.deleteAccount),
              subtitle: Text(strings.deleteAccountSubtitle),
              onTap: _busy ? null : _confirmDeleteAccount,
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: AppSpacing.x3),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: AppSpacing.x3),
            Text(error,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) Navigator.of(context).pop();
  }

  Future<SpaceDeletionPreview?> _loadPreview() async {
    try {
      final preview = await _service.loadDeletionPreview();
      if (mounted && preview.memberCount != null) {
        setState(() => _memberCount = preview.memberCount!);
      }
      return preview;
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).lifecycleError);
      }
      return null;
    }
  }

  Future<void> _confirmLeave() async {
    final strings = AppLocalizations.of(context);
    final preview = await _loadPreview();
    if (!mounted || preview == null) return;
    final lastMember = _memberCount == 1;
    final confirmed = await _showConfirmation(
      title: strings.leaveSpace,
      body: lastMember
          ? strings.leaveLastMemberBody(preview.plans, preview.files)
          : strings.leaveSpaceBody,
      requiresWord: lastMember,
    );
    if (!confirmed || !mounted) return;
    await _run(() async {
      final outcome = await _service.leaveSpace(
        expectedMemberCount: _memberCount,
        confirmationWord: lastMember ? 'DELETE' : '',
      );
      if (outcome.errorCode == 'reconfirm_required') {
        if (mounted && outcome.currentMemberCount != null) {
          setState(() {
            _memberCount = outcome.currentMemberCount!;
            _error = AppLocalizations.of(context).membershipChangedError;
          });
        }
        return;
      }
      if (mounted) {
        Navigator.of(context).pop();
        await widget.onSpaceChanged();
      }
    });
  }

  Future<void> _confirmDeleteAccount() async {
    final strings = AppLocalizations.of(context);
    final preview = await _loadPreview();
    if (!mounted || preview == null) return;
    final confirmed = await _showConfirmation(
      title: strings.deleteAccount,
      body: _memberCount == 1
          ? strings.deleteAccountLastMemberBody(preview.plans, preview.files)
          : strings.deleteAccountBody,
      requiresWord: true,
    );
    if (!confirmed || !mounted) return;
    await _run(() => _service.deleteAccount(
          expectedMemberCount: _memberCount,
          confirmationWord: 'DELETE',
        ));
  }

  Future<bool> _showConfirmation({
    required String title,
    required String body,
    required bool requiresWord,
  }) async {
    final strings = AppLocalizations.of(context);
    var acknowledged = false;
    var typedWord = '';
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(body),
                    const SizedBox(height: AppSpacing.x3),
                    Text(strings.backupRetentionNotice),
                    if (requiresWord) ...[
                      const SizedBox(height: AppSpacing.x3),
                      TextField(
                        onChanged: (value) =>
                            setDialogState(() => typedWord = value),
                        decoration: InputDecoration(
                          labelText: strings.typeDeleteToConfirm,
                        ),
                      ),
                    ],
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: acknowledged,
                      title: Text(strings.permanentDeletionAcknowledgement),
                      onChanged: (value) => setDialogState(
                        () => acknowledged = value ?? false,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(strings.cancel),
                ),
                FilledButton(
                  onPressed: acknowledged &&
                          (!requiresWord || typedWord.trim() == 'DELETE')
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  child: Text(strings.continueLabel),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on SpaceLifecycleException {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).lifecycleError);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).lifecycleError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
