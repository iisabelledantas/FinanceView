import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/domain/auth_models.dart';
import '../../features/auth/presentation/auth_provider.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/confirm_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/transactions/presentation/transactions_screen.dart';
import '../../features/import/presentation/import_screen.dart';
import '../../features/analysis/presentation/analysis_screen.dart';
import '../../features/budgets/presentation/budgets_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/login',

    redirect: (context, state) {
      final isAuthenticated = authState is AuthAuthenticated;
      final isAuthRoute = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/signup') ||
          state.matchedLocation.startsWith('/confirm');

      if (!isAuthenticated && !isAuthRoute) return '/login';

      if (isAuthenticated && isAuthRoute) return '/dashboard';

      return null; // Sem redirecionamento
    },
    routes: [
      GoRoute(path: '/login',   builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup',  builder: (_, __) => const SignUpScreen()),
      GoRoute(
        path: '/confirm',
        builder: (_, state) => ConfirmScreen(
          email: state.uri.queryParameters['email'] ?? '',
        ),
      ),

      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard',    builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/transactions', builder: (_, __) => const TransactionsScreen()),
          GoRoute(path: '/import',       builder: (_, __) => const ImportScreen()),
          GoRoute(path: '/analysis',     builder: (_, __) => const AnalysisScreen()),
          GoRoute(path: '/budgets',      builder: (_, __) => const BudgetsScreen()),
        ],
      ),
    ],
  );
});

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;

    final destinations = [
      (path: '/dashboard',    icon: Icons.home_outlined,        label: 'Início'),
      (path: '/transactions', icon: Icons.list_outlined,         label: 'Extratos'),
      (path: '/import',       icon: Icons.upload_file_outlined,  label: 'Importar'),
      (path: '/analysis',     icon: Icons.insights_outlined,     label: 'Análise'),
      (path: '/budgets',      icon: Icons.account_balance_wallet_outlined, label: 'Metas'),
    ];

    final currentIndex = destinations.indexWhere((d) => location.startsWith(d.path));

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex < 0 ? 0 : currentIndex,
        onDestinationSelected: (i) => context.go(destinations[i].path),
        destinations: destinations.map((d) => NavigationDestination(
          icon: Icon(d.icon),
          label: d.label,
        )).toList(),
      ),
    );
  }
}