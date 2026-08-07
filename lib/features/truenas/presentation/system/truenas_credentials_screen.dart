import 'package:flutter/material.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/features/truenas/domain/models/credentials.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_system_providers.dart';
import 'package:cupola/features/truenas/presentation/truenas_actions.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_form_sheet.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

class TrueNasCredentialsScreen extends ConsumerStatefulWidget {
  const TrueNasCredentialsScreen({super.key});

  @override
  ConsumerState<TrueNasCredentialsScreen> createState() =>
      _TrueNasCredentialsScreenState();
}

class _TrueNasCredentialsScreenState
    extends ConsumerState<TrueNasCredentialsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TrueNasSectionScaffold(
      title: 'Credentials',
      appBarBottom: TabBar(
        controller: _tab,
        tabs: const [
          Tab(text: 'Users'),
          Tab(text: 'Groups'),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: const [_UsersTab(), _GroupsTab()],
      ),
    );
  }
}

class _UsersTab extends ConsumerWidget {
  const _UsersTab();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final values = await showTrueNasFormSheet(
      context: context,
      title: 'New user',
      submitLabel: 'Create',
      fields: const [
        TrueNasFormField(key: 'username', label: 'Username', required: true),
        TrueNasFormField(key: 'full_name', label: 'Full name'),
        TrueNasFormField(
          key: 'password',
          label: 'Password',
          required: true,
          obscure: true,
        ),
      ],
    );
    if (values == null || !context.mounted) return;
    await runTrueNasAction(
      context,
      ref,
      action: () => ref.read(truenasCredentialsApiProvider).createUser({
        'username': values['username'],
        'full_name': values['full_name'] ?? values['username'],
        'password': values['password'],
        'group_create': true,
      }),
      successMessage: 'User created',
      failureMessage: 'Could not create user',
      invalidate: [truenasUsersProvider],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(truenasUsersProvider);
    return _CrudList(
      onCreate: () => _create(context, ref),
      onRefresh: () => ref.invalidate(truenasUsersProvider),
      child: users.when(
        loading: () => AppSkeleton.listRows(),
        error: (e, _) => AppErrorState(
          error: e,
          onRetry: () => ref.invalidate(truenasUsersProvider),
        ),
        data: (list) =>
            Column(children: [for (final user in list) _UserTile(user: user)]),
      ),
    );
  }
}

class _UserTile extends ConsumerWidget {
  final TrueNasUser user;
  const _UserTile({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AppCard.surfaceOutlined(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.username,
                  style: theme.textTheme.bodyMedium!.weight(FontWeight.w600),
                ),
                Text(
                  '${user.fullName ?? '—'}${user.uid != null ? ' · uid ${user.uid}' : ''}'
                  '${user.builtin ? ' · built-in' : ''}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!user.builtin)
            IconButton(
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: theme.colorScheme.error,
              ),
              tooltip: 'Delete user',
              onPressed: () async {
                final result = await showAppConfirmDialog(
                  context: context,
                  title: 'Delete ${user.username}?',
                  message: 'The user account will be removed.',
                  confirmLabel: 'Delete',
                  destructive: true,
                );
                if (!result.confirmed || !context.mounted) return;
                await runTrueNasAction(
                  context,
                  ref,
                  action: () => ref
                      .read(truenasCredentialsApiProvider)
                      .deleteUser(user.id),
                  successMessage: 'User deleted',
                  failureMessage: 'Could not delete user',
                  invalidate: [truenasUsersProvider],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _GroupsTab extends ConsumerWidget {
  const _GroupsTab();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final values = await showTrueNasFormSheet(
      context: context,
      title: 'New group',
      submitLabel: 'Create',
      fields: const [
        TrueNasFormField(key: 'name', label: 'Group name', required: true),
      ],
    );
    if (values == null || !context.mounted) return;
    await runTrueNasAction(
      context,
      ref,
      action: () => ref.read(truenasCredentialsApiProvider).createGroup({
        'name': values['name'],
      }),
      successMessage: 'Group created',
      failureMessage: 'Could not create group',
      invalidate: [truenasGroupsProvider],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(truenasGroupsProvider);
    return _CrudList(
      onCreate: () => _create(context, ref),
      onRefresh: () => ref.invalidate(truenasGroupsProvider),
      child: groups.when(
        loading: () => AppSkeleton.listRows(),
        error: (e, _) => AppErrorState(
          error: e,
          onRetry: () => ref.invalidate(truenasGroupsProvider),
        ),
        data: (list) => Column(
          children: [for (final group in list) _GroupTile(group: group)],
        ),
      ),
    );
  }
}

class _GroupTile extends ConsumerWidget {
  final TrueNasGroup group;
  const _GroupTile({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AppCard.surfaceOutlined(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: theme.textTheme.bodyMedium!.weight(FontWeight.w600),
                ),
                Text(
                  '${group.userCount} users${group.gid != null ? ' · gid ${group.gid}' : ''}'
                  '${group.builtin ? ' · built-in' : ''}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!group.builtin)
            IconButton(
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: theme.colorScheme.error,
              ),
              tooltip: 'Delete group',
              onPressed: () async {
                final result = await showAppConfirmDialog(
                  context: context,
                  title: 'Delete ${group.name}?',
                  message: 'The group will be removed.',
                  confirmLabel: 'Delete',
                  destructive: true,
                );
                if (!result.confirmed || !context.mounted) return;
                await runTrueNasAction(
                  context,
                  ref,
                  action: () => ref
                      .read(truenasCredentialsApiProvider)
                      .deleteGroup(group.id),
                  successMessage: 'Group deleted',
                  failureMessage: 'Could not delete group',
                  invalidate: [truenasGroupsProvider],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _CrudList extends StatelessWidget {
  final Widget child;
  final VoidCallback onCreate;
  final VoidCallback onRefresh;

  const _CrudList({
    required this.child,
    required this.onCreate,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async => onRefresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              FloatingNavBarMetrics.getScrollViewBottomPadding(context),
            ),
            children: [child],
          ),
        ),
        Positioned(
          right: AppSpacing.lg,
          bottom: AppSpacing.lg,
          child: FloatingActionButton(
            heroTag: null,
            backgroundColor: AppColors.truenas,
            onPressed: onCreate,
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }
}
