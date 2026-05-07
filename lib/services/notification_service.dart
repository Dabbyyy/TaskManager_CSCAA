import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Top-level background message handler for FCM (called by OS when app is closed)
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('🔔 BG FCM message received: ${message.messageId}');

  try {
    await Firebase.initializeApp();
  } catch (_) {}

  final plugin = FlutterLocalNotificationsPlugin();

  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );

  final title = message.data['title'] ?? message.notification?.title;
  final body = message.data['body'] ?? message.notification?.body;

  if (title != null && body != null) {
    await plugin.show(
      message.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'cscaa_main_channel',
          'TaskFlow Notifications',
          channelDescription: 'Notifications for CSCAA task reminders and updates.',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: Color(0xFF3F598F),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'cscaa_main_channel',
    'TaskFlow Notifications',
    description: 'Notifications for CSCAA task reminders and updates.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  // ── Initialize ─────────────────────────────────────────────────────────────
  static Future<void> initialize() async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse r) {
        debugPrint('Notification tapped: ${r.payload}');
      },
    );

    // Create high-importance channel (Android)
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Register the top-level background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Show notification when FCM arrives while app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title = message.data['title'] ?? message.notification?.title;
      final body = message.data['body'] ?? message.notification?.body;
      if (title != null && body != null) {
        _showLocal(title: title, body: body, payload: jsonEncode(message.data));
      }
    });
  }

  // ── Request Permissions + Save FCM Token ───────────────────────────────────
  static Future<void> requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await _saveFCMToken();
  }

  // ── "Run in Background" dialog (shown once on first launch) ───────────────
  static Future<void> requestBackgroundExecution(BuildContext context) async {
    if (!Platform.isAndroid) return;

    final prefs = await SharedPreferences.getInstance();
    final hasAsked = prefs.getBool('asked_bg_execution') ?? false;
    if (hasAsked) return;

    // Mark as asked immediately so we only ever show this once
    await prefs.setBool('asked_bg_execution', true);

    final isGranted = await Permission.ignoreBatteryOptimizations.isGranted;
    if (isGranted) return;

    if (!context.mounted) return;

    final shouldRequest = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        title: const Row(
          children: [
            Icon(Icons.notifications_active, color: Color(0xFF3F598F)),
            SizedBox(width: 10),
            Text('Always Notify Me'),
          ],
        ),
        content: const Text(
          'To make sure you always get task notifications — even when this app is closed — '
          'please allow it to run in the background.\n\n'
          'Tap "Allow" and then select "Allow" on the next screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3F598F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    if (shouldRequest == true) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  // ── Show a local notification (in-app) ────────────────────────────────────
  static Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _showLocal(title: title, body: body, payload: payload);
  }

  static Future<void> _showLocal({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF3F598F),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  // ── Send a TRUE push notification via FCM v1 API ──────────────────────────
  //
  // This method:
  //  1. Loads the Firebase Service Account JSON from assets/service_account.json
  //  2. Obtains a short-lived OAuth2 access token
  //  3. Calls the FCM v1 send endpoint
  //
  // The push is delivered by Google's servers → arrives on device even when
  // the recipient's app is completely closed / killed.
  static Future<void> sendPushNotification({
    required String toEmail,
    required String title,
    required String body,
  }) async {
    try {
      // 1 — Look up recipient's FCM token
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(toEmail)
          .get();
      if (!userDoc.exists) return;

      final String? token = userDoc.data()?['fcmToken'];
      if (token == null || token.isEmpty) {
        debugPrint('No FCM token for $toEmail — skipping push.');
        return;
      }

      // 2 — Load service account credentials from bundled asset
      final saJson = await rootBundle.loadString('assets/service_account.json');
      final saMap = jsonDecode(saJson) as Map<String, dynamic>;
      final projectId = saMap['project_id'] as String;

      final accountCredentials = ServiceAccountCredentials.fromJson(saMap);
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

      final authClient = await clientViaServiceAccount(accountCredentials, scopes);

      // 3 — Build FCM v1 message
      final payload = {
        'message': {
          'token': token,
          'notification': {'title': title, 'body': body},
          'data': {'title': title, 'body': body},
          'android': {
            'priority': 'HIGH',
            'notification': {
              'channel_id': 'cscaa_main_channel',
              'notification_priority': 'PRIORITY_MAX',
              'default_sound': true,
              'default_vibrate_timings': true,
            },
          },
          'apns': {
            'payload': {
              'aps': {
                'alert': {'title': title, 'body': body},
                'sound': 'default',
                'badge': 1,
              },
            },
          },
        },
      };

      final url = Uri.parse(
          'https://fcm.googleapis.com/v1/projects/$projectId/messages:send');

      final response = await authClient.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      authClient.close();

      if (response.statusCode == 200) {
        debugPrint('✅ FCM push sent to $toEmail');
      } else {
        debugPrint('❌ FCM error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error sending FCM push: $e');
    }
  }

  // ── Save / Refresh FCM Token ───────────────────────────────────────────────
  static Future<void> _saveFCMToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.email)
          .update({'fcmToken': token}).catchError((_) {});
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.email)
          .update({'fcmToken': newToken}).catchError((_) {});
    });
  }

  // ── Remove FCM token on logout ─────────────────────────────────────────────
  static Future<void> removeTokenOnLogout() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.email)
          .update({'fcmToken': FieldValue.delete()}).catchError((_) {});
    }
  }
}
