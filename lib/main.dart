import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'l10n/generated/app_localizations.dart';
import 'screens/space_invitations.dart';
import 'screens/space_settings.dart';
import 'screens/plans.dart';
import 'screens/calendar.dart';
import 'theme/app_theme.dart';
import 'widgets/app_components.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (SupabaseConnection.isConfigured) {
    await Supabase.initialize(
        url: _supabaseUrl, publishableKey: _supabaseAnonKey);
  }
  runApp(const DatePlannerApp());
}

class DatePlannerApp extends StatelessWidget {
  const DatePlannerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AppGate(),
      );
}

class SupabaseConnection {
  static bool get isConfigured =>
      _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;
}

class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (!SupabaseConnection.isConfigured) return const SetupRequiredScreen();
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) =>
          Supabase.instance.client.auth.currentSession == null
              ? const SignInScreen()
              : const SpaceGate(),
    );
  }
}

class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.formColumn),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.favorite_outline,
                  size: AppIconSize.hero,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.x4),
                Text(
                  strings.setupTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.x3),
                Text(
                  strings.setupBody,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool create}) async {
    final strings = AppLocalizations.of(context);
    final email = _email.text.trim();
    final password = _password.text;
    final emailError = email.isEmpty
        ? strings.emailRequired
        : RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
            ? null
            : strings.invalidEmailError;
    final validationError =
        emailError ?? (password.isEmpty ? strings.passwordRequired : null);
    if (validationError != null) {
      setState(() {
        _busy = false;
        _error = validationError;
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
      final auth = Supabase.instance.client.auth;
      if (create) {
        final response = await auth.signUp(
          email: email,
          password: password,
        );
        if (response.session == null && mounted) {
          setState(() => _notice = strings.confirmEmailNotice);
        }
      } else {
        await auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _error = _authErrorMessage(error, create, strings));
      }
    } catch (_) {
      if (mounted) setState(() => _error = strings.connectionError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authErrorMessage(
    AuthException error,
    bool creatingAccount,
    AppLocalizations strings,
  ) {
    final code = error.code?.toLowerCase();
    final message = error.message.toLowerCase();
    if (code == 'weak_password' || message.contains('password')) {
      return strings.weakPasswordError;
    }
    if (code == 'email_address_invalid' || message.contains('invalid email')) {
      return strings.invalidEmailError;
    }
    if (code == 'user_already_exists' ||
        code == 'user_already_registered' ||
        message.contains('already registered') ||
        message.contains('already been registered')) {
      return strings.accountExistsError;
    }
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit' ||
        error.statusCode == '429') {
      return strings.authRateLimitError;
    }
    return creatingAccount
        ? strings.accountCreateError
        : strings.genericAuthError;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
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
                    Icon(
                      Icons.favorite_outline,
                      size: AppIconSize.large,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: AppSpacing.x4),
                    Text(
                      strings.signInHeadline,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      strings.signInPrompt,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.x6),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(labelText: strings.email),
                    ),
                    const SizedBox(height: AppSpacing.x3),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(labelText: strings.password),
                    ),
                    if (_error case final error?) ...[
                      const SizedBox(height: AppSpacing.x3),
                      Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (_notice case final notice?) ...[
                      const SizedBox(height: AppSpacing.x3),
                      Text(
                        notice,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.x4),
                    SizedBox(
                      height: AppTouchTarget.minimum,
                      child: FilledButton(
                        onPressed: _busy ? null : () => _submit(create: false),
                        child: Text(
                          _busy ? strings.pleaseWait : strings.signIn,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: AppTouchTarget.minimum,
                      child: TextButton(
                        onPressed: _busy ? null : () => _submit(create: true),
                        child: Text(strings.createAccount),
                      ),
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

class SpaceGate extends StatefulWidget {
  const SpaceGate({super.key});

  @override
  State<SpaceGate> createState() => _SpaceGateState();
}

class _SpaceGateState extends State<SpaceGate> {
  late Future<Map<String, dynamic>?> _space = _load();

  Future<Map<String, dynamic>?> _load() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser!;

    // Provision on first authenticated launch. The RPC is idempotent and
    // serializes concurrent calls per user, so sign-in, reload, and retry all
    // resolve to the same one-member Space. An invitee's Space is later merged
    // by confirm_join without copying rows or moving storage objects.
    await client.rpc('create_personal_space');

    // Retry any private objects queued by a prior last-member deletion. This
    // worker only drains paths already authorized by the server-side queue.
    unawaited(client.functions.invoke('drain-file-deletion-queue').then<void>(
          (_) {},
          onError: (Object _) {},
        ));

    final row = await client
        .from('space_members')
        .select('space_id, spaces(id, name)')
        .eq('user_id', user.id)
        .maybeSingle();
    if (row == null) {
      throw StateError('Space provisioning completed without membership');
    }
    final space = row['spaces'] as Map<String, dynamic>?;
    if (space == null) {
      throw StateError('Space membership has no active Space');
    }
    final memberRows = List<Map<String, dynamic>>.from(await client
        .from('space_members')
        .select('user_id, role')
        .eq('space_id', row['space_id']));
    final memberIds = memberRows
        .map((member) => member['user_id'] as String)
        .toSet()
        .toList();
    final profiles = memberIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(await client
            .from('profiles')
            .select('id, display_name')
            .inFilter('id', memberIds));
    final profilesById = {
      for (final profile in profiles) profile['id'] as String: profile,
    };
    final members = memberRows
        .map((member) => {
              ...member,
              'profiles':
                  profilesById[member['user_id']] ?? <String, dynamic>{},
            })
        .toList();
    return {...space, 'members': members};
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
        future: _space,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Scaffold(
              body: ErrorState(
                message: AppLocalizations.of(context).spaceLoadError,
                retryLabel: AppLocalizations.of(context).retry,
                onRetry: () => setState(() => _space = _load()),
              ),
            );
          }
          return AppShell(
            spaceId: snapshot.data!['id'] as String,
            spaceName: snapshot.data!['name'] as String? ??
                AppLocalizations.of(context).defaultSpaceName,
            members: List<Map<String, dynamic>>.from(
                snapshot.data!['members'] as List),
            onSpaceChanged: () async {
              if (mounted) setState(() => _space = _load());
            },
          );
        },
      );
}

enum Destination { plans, calendar, space }

Future<void> _noSpaceChange() async {}

class AppShell extends StatefulWidget {
  const AppShell({
    required this.spaceName,
    this.spaceId = '',
    this.members = const [],
    this.onSpaceChanged = _noSpaceChange,
    super.key,
  });
  final String spaceName;
  final String spaceId;
  final List<Map<String, dynamic>> members;
  final Future<void> Function() onSpaceChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  Destination _selected = Destination.plans;

  List<String> _labels(AppLocalizations strings) => [
        strings.plans,
        strings.calendar,
        strings.space,
      ];
  static const _icons = [
    Icons.favorite_outline,
    Icons.calendar_month_outlined,
    Icons.people_outline,
  ];

  Widget _destination(int index, AppLocalizations strings, double width) {
    if (index == Destination.plans.index && widget.spaceId.isNotEmpty) {
      return PlansScreen(spaceId: widget.spaceId);
    }
    if (index == Destination.space.index) {
      return SpaceScreen(
        spaceName: widget.spaceName,
        members: widget.members,
        onSpaceChanged: widget.onSpaceChanged,
      );
    }
    if (index == Destination.calendar.index && widget.spaceId.isNotEmpty) {
      return CalendarScreen(
        spaceId: widget.spaceId,
        onViewPlans: () => setState(() => _selected = Destination.plans),
      );
    }
    final title = _labels(strings)[index];
    final horizontal = width < AppLayout.compactBreakpoint
        ? AppSpacing.compactScreen
        : width < AppLayout.expandedBreakpoint
            ? AppSpacing.mediumScreen
            : AppSpacing.expandedScreen;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.readingColumn),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontal,
            vertical: AppSpacing.x6,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(title: title),
              Expanded(
                child: UnfinishedDestination(
                  title: strings.notAvailableTitle(title),
                  message: strings.notAvailableBody,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signOut() => Supabase.instance.client.auth.signOut();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final strings = AppLocalizations.of(context);
          final compact = box.maxWidth < AppLayout.compactBreakpoint;
          final medium = box.maxWidth < AppLayout.expandedBreakpoint;
          final labels = _labels(strings);
          final index = _selected.index;
          final page = _destination(index, strings, box.maxWidth);
          if (compact) {
            return Scaffold(
              appBar: AppBar(title: Text(labels[index])),
              body: page,
              bottomNavigationBar: NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (value) =>
                    setState(() => _selected = Destination.values[value]),
                destinations: List.generate(
                  3,
                  (i) => NavigationDestination(
                    icon: Icon(_icons[i]),
                    label: labels[i],
                  ),
                ),
              ),
            );
          }
          return Scaffold(
            body: Row(
              children: [
                if (medium)
                  NavigationRail(
                    selectedIndex: index,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (value) =>
                        setState(() => _selected = Destination.values[value]),
                    destinations: List.generate(
                      3,
                      (i) => NavigationRailDestination(
                        icon: Icon(_icons[i]),
                        label: Text(labels[i]),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: AppLayout.sidebarWidth,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.x6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              strings.brand,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ),
                        ...List.generate(
                          3,
                          (i) => ListTile(
                            selected: index == i,
                            leading: Icon(_icons[i]),
                            title: Text(labels[i]),
                            onTap: () => setState(
                                () => _selected = Destination.values[i]),
                          ),
                        ),
                        const Spacer(),
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.logout),
                          title: Text(strings.signOut),
                          onTap: _signOut,
                        ),
                      ],
                    ),
                  ),
                VerticalDivider(
                    width: 1, color: Theme.of(context).dividerColor),
                Expanded(
                  child: Column(
                    children: [
                      if (medium)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding:
                                const EdgeInsets.only(right: AppSpacing.x4),
                            child: TextButton.icon(
                              onPressed: _signOut,
                              icon: const Icon(Icons.logout),
                              label: Text(strings.signOut),
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: AppSpacing.x4),
                      Expanded(child: page),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class SpaceScreen extends StatelessWidget {
  const SpaceScreen({
    required this.spaceName,
    required this.members,
    required this.onSpaceChanged,
    super.key,
  });
  final String spaceName;
  final List<Map<String, dynamic>> members;
  final Future<void> Function() onSpaceChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < AppLayout.compactBreakpoint
        ? AppSpacing.compactScreen
        : width < AppLayout.expandedBreakpoint
            ? AppSpacing.mediumScreen
            : AppSpacing.expandedScreen;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.readingColumn),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: AppSpacing.x6,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(title: strings.yourSpace),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: Text(
                    spaceName,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  subtitle: Text(strings.spaceMemberCount(members.length)),
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              Text(
                strings.spaceMembersHeading,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.x2),
              ...members.map((member) {
                final profile = member['profiles'] is Map
                    ? Map<String, dynamic>.from(member['profiles'] as Map)
                    : <String, dynamic>{};
                final isYou = member['user_id'] ==
                    Supabase.instance.client.auth.currentUser?.id;
                final displayName = profile['display_name'] as String?;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                        isYou ? Icons.person_outline : Icons.favorite_outline,
                      ),
                    ),
                    title: Text(
                      isYou
                          ? strings.youLabel
                          : (displayName ?? strings.spaceMember),
                    ),
                    subtitle: Text(
                      member['role'] == 'owner'
                          ? strings.spaceOwner
                          : strings.spaceMember,
                    ),
                  ),
                );
              }),
              const SizedBox(height: AppSpacing.x3),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_add_alt),
                  title: Text(strings.invitePartner),
                  subtitle: Text(strings.inviteSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: members.length >= 2
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const InvitePartnerScreen(),
                            ),
                          ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.input_outlined),
                  title: Text(strings.joinWithCode),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => JoinInvitationScreen(
                        onJoined: onSpaceChanged,
                      ),
                    ),
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(strings.settings),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _settings(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _settings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpaceSettingsScreen(
          memberCount: members.length,
          onSpaceChanged: onSpaceChanged,
        ),
      ),
    );
  }
}
