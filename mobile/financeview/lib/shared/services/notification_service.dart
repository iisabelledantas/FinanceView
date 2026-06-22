import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _notificationsEnabled = false;

  bool get notificationsEnabled => _notificationsEnabled;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        ),
      );

      await _createAndroidChannel();
      _notificationsEnabled = await requestPermissions();
    } catch (error) {
      debugPrint('Falha ao inicializar notificações locais: $error');
      _notificationsEnabled = false;
    }

    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    final androidGranted = await android?.requestNotificationsPermission();
    final iosGranted = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    return androidGranted ?? iosGranted ?? true;
  }

  Future<void> notifyBudgetSaved({
    required String category,
    required double limit,
  }) async {
    await _show(
      id: _stableId('budget-saved-$category'),
      title: 'Meta criada',
      body:
          'Você definiu uma meta de R\$ ${limit.toStringAsFixed(2)} para $category.',
    );
  }

  Future<void> notifyBudgetUsage({
    required String category,
    required double spent,
    required double limit,
  }) async {
    if (limit <= 0) return;

    final pct = spent / limit;
    if (pct < 0.8) return;

    final alertType = pct >= 1 ? 'exceeded' : 'warning';
    final dedupeKey = _dailyKey('budget-$alertType-$category');
    if (!await _shouldNotify(dedupeKey)) return;

    await _show(
      id: _stableId(dedupeKey),
      title: pct >= 1 ? 'Meta excedida' : 'Meta em atenção',
      body: pct >= 1
          ? '$category ultrapassou o limite mensal.'
          : '$category chegou a ${(pct * 100).toStringAsFixed(0)}% do limite.',
    );
  }

  Future<void> notifyMonthlyAnalysisReminder() async {
    final now = DateTime.now();
    final isReminderDay = now.day >= 25;
    if (!isReminderDay) return;

    final dedupeKey = '${now.year}-${now.month}-monthly-analysis';
    if (!await _shouldNotify(dedupeKey)) return;

    await _show(
      id: _stableId(dedupeKey),
      title: 'Análise mensal',
      body: 'Revise seus gastos e metas antes de fechar o mês.',
    );
  }

  Future<void> _createAndroidChannel() async {
    const channel = AndroidNotificationChannel(
      'financeview_alerts',
      'Alertas FinanceView',
      description: 'Alertas locais de metas, orçamento e análise mensal.',
      importance: Importance.high,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await initialize();
    if (!_notificationsEnabled) return;

    const androidDetails = AndroidNotificationDetails(
      'financeview_alerts',
      'Alertas FinanceView',
      channelDescription:
          'Alertas locais de metas, orçamento e análise mensal.',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();

    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
      );
    } catch (error) {
      debugPrint('Falha ao exibir notificação local: $error');
    }
  }

  Future<bool> _shouldNotify(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('notification:$key') == true) return false;
    await prefs.setBool('notification:$key', true);
    return true;
  }

  String _dailyKey(String key) {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}-$key';
  }

  int _stableId(String value) {
    return value.codeUnits.fold<int>(0, (hash, unit) {
      return (hash * 31 + unit) & 0x7fffffff;
    });
  }
}
