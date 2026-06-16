import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_client.dart';

final insightsRepositoryProvider = Provider((ref) =>
    InsightsRepository(ref.watch(apiClientProvider)));

class InsightsRepository {
  final ApiClient _api;
  final _storage = const FlutterSecureStorage();

  InsightsRepository(this._api);

  Future<String> _userId() async =>
      await _storage.read(key: 'user_id') ?? '';

  Future<Map<String, dynamic>> getInsights({String? period}) async {
    final userId = await _userId();
    final params = {'user_id': userId, if (period != null) 'period': period};
    final response = await _api.get('/insights', params: params);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMarket() async {
    final response = await _api.get('/market');
    return response.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getBudgets() async {
    final userId = await _userId();
    final response = await _api.get('/budgets', params: {'user_id': userId});
    final data = response.data;
    return data is List ? data : (data['items'] ?? []);
  }

  Future<void> saveBudget(String category, double limit) async {
    final userId = await _userId();
    await _api.post('/budgets', data: {
      'user_id': userId,
      'category': category,
      'monthly_limit': limit,
    });
  }
}

// Provider do período selecionado — compartilhado entre telas
final selectedPeriodProvider = StateProvider<String>((ref) {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
});

// Provider dos insights — recarrega quando o período muda
final insightsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  final period = ref.watch(selectedPeriodProvider);
  return ref.watch(insightsRepositoryProvider).getInsights(period: period);
});

final marketProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) =>
    ref.watch(insightsRepositoryProvider).getMarket());

final budgetsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) =>
    ref.watch(insightsRepositoryProvider).getBudgets());