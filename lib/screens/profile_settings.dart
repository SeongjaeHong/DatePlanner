import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

abstract interface class ProfileAccountActions {
  String? get email;
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}

class SupabaseProfileAccountActions implements ProfileAccountActions {
  const SupabaseProfileAccountActions();

  @override
  String? get email => Supabase.instance.client.auth.currentUser?.email;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final auth = Supabase.instance.client.auth;
    final accountEmail = email;
    if (accountEmail == null || accountEmail.isEmpty) {
      throw const AuthException('No signed-in email address.');
    }
    await auth.signInWithPassword(
        email: accountEmail, password: currentPassword);
    await auth.updateUser(UserAttributes(password: newPassword));
  }
}

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({this.accountActions, super.key});
  final ProfileAccountActions? accountActions;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late final ProfileAccountActions _accountActions =
      widget.accountActions ?? const SupabaseProfileAccountActions();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final strings = AppLocalizations.of(context);
    final current = _currentPassword.text;
    final next = _newPassword.text;
    if (current.isEmpty) {
      setState(() {
        _error = strings.currentPasswordRequired;
        _notice = null;
      });
      return;
    }
    if (next.length < 6) {
      setState(() {
        _error = strings.passwordTooShort;
        _notice = null;
      });
      return;
    }
    if (next != _confirmPassword.text) {
      setState(() {
        _error = strings.passwordsDoNotMatch;
        _notice = null;
      });
      return;
    }
    final email = _accountActions.email;
    if (email == null || email.isEmpty) {
      setState(() {
        _error = strings.passwordChangeFailed;
        _notice = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await _accountActions.changePassword(
        currentPassword: current,
        newPassword: next,
      );
      if (mounted) {
        _currentPassword.clear();
        _newPassword.clear();
        _confirmPassword.clear();
        setState(() => _notice = strings.passwordChanged);
      }
    } on AuthException catch (error) {
      if (mounted) {
        final message = error.message.toLowerCase();
        final code = error.code?.toLowerCase();
        setState(() => _error =
            code == 'weak_password' || message.contains('password')
                ? strings.weakPasswordError
                : strings.currentPasswordIncorrect);
      }
    } catch (_) {
      if (mounted) setState(() => _error = strings.passwordChangeFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final email = _accountActions.email ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(strings.profileSettings)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.x4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppLayout.signInColumn),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.x6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(strings.profileEmail,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.x1),
                    SelectableText(email),
                    const SizedBox(height: AppSpacing.x6),
                    Text(strings.changePassword,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.x2),
                    Text(strings.changePasswordPrompt),
                    const SizedBox(height: AppSpacing.x4),
                    TextField(
                      controller: _currentPassword,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration:
                          InputDecoration(labelText: strings.currentPassword),
                    ),
                    const SizedBox(height: AppSpacing.x3),
                    TextField(
                      controller: _newPassword,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                          labelText: strings.newPassword,
                          helperText: strings.passwordMinimumHint),
                    ),
                    const SizedBox(height: AppSpacing.x3),
                    TextField(
                      controller: _confirmPassword,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      onSubmitted: (_) => _busy ? null : _changePassword(),
                      decoration: InputDecoration(
                          labelText: strings.confirmNewPassword),
                    ),
                    if (_error case final error?) ...[
                      const SizedBox(height: AppSpacing.x3),
                      Text(error,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                    if (_notice case final notice?) ...[
                      const SizedBox(height: AppSpacing.x3),
                      Text(notice),
                    ],
                    const SizedBox(height: AppSpacing.x4),
                    FilledButton(
                      onPressed: _busy ? null : _changePassword,
                      child: Text(
                          _busy ? strings.pleaseWait : strings.changePassword),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
