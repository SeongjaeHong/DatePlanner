import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/space_invitation_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';

String invitationErrorMessage(BuildContext context, String code) {
  final strings = AppLocalizations.of(context);
  return switch (code) {
    'INVITE_INVALID' => strings.inviteInvalid,
    'RATE_LIMITED' => strings.inviteRateLimited,
    'SPACE_FULL' => strings.spaceFull,
    'ALREADY_IN_TWO_PERSON_SPACE' => strings.alreadyInTwoPersonSpace,
    'SAME_SPACE' => strings.sameSpace,
    'DISCLOSURE_CHANGED' => strings.disclosureChanged,
    'INVITE_PENDING' => strings.invitationPendingError,
    _ => strings.invitationFlowError,
  };
}

class InvitePartnerScreen extends StatefulWidget {
  const InvitePartnerScreen({super.key});

  @override
  State<InvitePartnerScreen> createState() => _InvitePartnerScreenState();
}

class _InvitePartnerScreenState extends State<InvitePartnerScreen> {
  final _service = const SpaceInvitationService();
  late Future<List<Map<String, dynamic>>> _invitations =
      _service.listInvitations();
  bool _acknowledged = false;
  bool _busy = false;
  String? _error;
  String? _newCode;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.createInvitation();
      if (result['error_code'] case final String code) {
        throw InvitationFlowException(code);
      }
      if (!mounted) return;
      setState(() {
        _newCode = result['code'] as String;
        _invitations = _service.listInvitations();
      });
    } on InvitationFlowException catch (error) {
      if (mounted) {
        setState(() => _error = invitationErrorMessage(context, error.code));
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = AppLocalizations.of(context).invitationCreateError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(String id) async {
    final strings = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.revokeInvitation),
        content: Text(strings.revokeInvitationConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.revokeInvitation),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.revokeInvitation(id);
      if (!mounted) return;
      setState(() {
        _newCode = null;
        _acknowledged = false;
        _invitations = _service.listInvitations();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.invitationRevoked)),
      );
    } on InvitationFlowException catch (error) {
      if (mounted) {
        setState(() => _error = invitationErrorMessage(context, error.code));
      }
    } catch (_) {
      if (mounted) setState(() => _error = strings.invitationFlowError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.invitePartner)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.readingColumn),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.x4),
            children: [
              if (_error case final message?) ...[
                AppBanner(
                  message: message,
                  icon: Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: AppSpacing.x3),
              ],
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _invitations,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LoadingSkeleton(lines: 1);
                  }
                  if (snapshot.hasError) {
                    return ErrorState(
                      message: strings.invitationLoadError,
                      retryLabel: strings.retry,
                      onRetry: () => setState(
                        () => _invitations = _service.listInvitations(),
                      ),
                    );
                  }
                  final pending = snapshot.data
                      ?.where((item) => item['status'] == 'pending')
                      .toList();
                  if (pending != null && pending.isNotEmpty) {
                    return _pendingInvitation(context, pending.first);
                  }
                  return _disclosure(context);
                },
              ),
              if (_newCode case final code?) ...[
                const SizedBox(height: AppSpacing.x4),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.x4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(strings.invitationCode,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.x3),
                        SelectableText(
                          RegExp(r'.{4}')
                              .allMatches(code)
                              .map((match) => match.group(0)!)
                              .join(' '),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                            letterSpacing: AppSpacing.xHalf,
                            fontFeatures: const [],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x3),
                        Text(strings.invitationCodeOneTime),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pendingInvitation(BuildContext context, Map<String, dynamic> invite) {
    final strings = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.activeInvitation,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.x2),
            Text(_newCode == null
                ? strings.invitationCodeUnavailable
                : strings.invitationCode),
            const SizedBox(height: AppSpacing.x3),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _revoke(invite['id'] as String),
              icon: const Icon(Icons.block_outlined),
              label: Text(strings.revokeInvitation),
            ),
          ],
        ),
      ),
    );
  }

  Widget _disclosure(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.invitationDisclosureTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.x3),
            Text(strings.invitationDisclosureBody),
            const SizedBox(height: AppSpacing.x2),
            CheckboxListTile(
              value: _acknowledged,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _acknowledged = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(strings.invitationAcknowledgement),
            ),
            const SizedBox(height: AppSpacing.x2),
            SizedBox(
              height: AppTouchTarget.minimum,
              child: FilledButton.icon(
                onPressed: _busy || !_acknowledged ? null : _create,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: AppIconSize.small,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.vpn_key_outlined),
                label: Text(
                    _busy ? strings.pleaseWait : strings.createInvitationCode),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class JoinInvitationScreen extends StatefulWidget {
  const JoinInvitationScreen({required this.onJoined, super.key});
  final Future<void> Function() onJoined;

  @override
  State<JoinInvitationScreen> createState() => _JoinInvitationScreenState();
}

class _JoinInvitationScreenState extends State<JoinInvitationScreen> {
  final _service = const SpaceInvitationService();
  final _code = TextEditingController();
  Map<String, dynamic>? _review;
  String? _operationId;
  String? _error;
  bool _acknowledged = false;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_code.text.trim().isEmpty) {
      setState(() => _error = AppLocalizations.of(context).codeRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.prepareJoin(
        code: _code.text,
        operationId: _service.newOperationId(),
      );
      if (!mounted) return;
      _operationId = result['operation_id'] as String;
      if (result['status'] == 'completed') {
        await widget.onJoined();
        if (mounted) Navigator.of(context).pop();
        return;
      }
      setState(() {
        _review = result;
        _acknowledged = false;
      });
    } on InvitationFlowException catch (error) {
      if (mounted) {
        setState(() => _error = invitationErrorMessage(context, error.code));
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = AppLocalizations.of(context).invitationFlowError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final strings = AppLocalizations.of(context);
    final operationId = _operationId;
    final version = _review?['disclosure_version'] as int?;
    if (operationId == null || version == null || !_acknowledged) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.confirmJoin(
        operationId: operationId,
        disclosureVersion: version,
      );
      await widget.onJoined();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.joinSucceeded)),
      );
      Navigator.of(context).pop();
    } on InvitationFlowException catch (error) {
      if (mounted) {
        setState(() => _error = invitationErrorMessage(context, error.code));
      }
    } catch (_) {
      if (mounted) setState(() => _error = strings.invitationFlowError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final operationId = _operationId;
    if (operationId != null) {
      try {
        await _service.cancelJoin(operationId);
      } catch (_) {
        // The prepared record contains no moved data; it can be resumed safely.
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final review = _review;
    return Scaffold(
      appBar: AppBar(title: Text(strings.invitationJoinTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.formColumn),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.x4),
            children: [
              if (_error case final message?) ...[
                AppBanner(
                  message: message,
                  icon: Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: AppSpacing.x3),
              ],
              if (review == null) ...[
                Text(strings.invitationJoinPrompt,
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: AppSpacing.x3),
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: strings.invitationCode,
                    hintText: strings.invitationCodeHint,
                  ),
                ),
                const SizedBox(height: AppSpacing.x4),
                SizedBox(
                  height: AppTouchTarget.minimum,
                  child: FilledButton(
                    onPressed: _busy ? null : _prepare,
                    child: _busy
                        ? const CircularProgressIndicator()
                        : Text(strings.continueLabel),
                  ),
                ),
              ] else ...[
                Text(strings.reviewJoinTitle,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.x3),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.x4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(strings.joinReviewSharing(
                          review['inviter_name'] as String? ??
                              strings.yourPartner,
                        )),
                        const SizedBox(height: AppSpacing.x3),
                        Text(strings.joinReviewCounts(
                          review['inviter_name'] as String? ??
                              strings.yourPartner,
                          (review['counts']['their_plans'] as num).toInt(),
                          (review['counts']['their_files'] as num).toInt(),
                          (review['counts']['my_plans'] as num).toInt(),
                          (review['counts']['my_files'] as num).toInt(),
                        )),
                        const SizedBox(height: AppSpacing.x3),
                        Text(strings.joinReviewConsequences),
                      ],
                    ),
                  ),
                ),
                CheckboxListTile(
                  value: _acknowledged,
                  onChanged: _busy
                      ? null
                      : (value) =>
                          setState(() => _acknowledged = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(strings.joinReviewAcknowledgement),
                ),
                const SizedBox(height: AppSpacing.x2),
                SizedBox(
                  height: AppTouchTarget.minimum,
                  child: FilledButton(
                    onPressed: _busy || !_acknowledged ? null : _confirm,
                    child: _busy
                        ? const CircularProgressIndicator()
                        : Text(strings.confirmJoin),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.x2),
              SizedBox(
                height: AppTouchTarget.minimum,
                child: TextButton(
                  onPressed: _busy ? null : _cancel,
                  child: Text(strings.cancel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
