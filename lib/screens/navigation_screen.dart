import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'widgets/task_feed.dart';
import 'widgets/calendar_monitor.dart';
import 'widgets/team_view.dart';
import 'widgets/user_header.dart';
import 'widgets/task_modal.dart';
import 'widgets/custom_dialogs.dart';
import 'notifications_page.dart';
import '../services/notification_service.dart';

const Color kPrimaryColor = Color(0xFF3F598F);

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => MainNavigationScreenState();
}

class MainNavigationScreenState extends State<MainNavigationScreen> {
  int _idx = 0;
  String name = "User",
      role = "staff",
      status = "pending",
      employmentType = "staff",
      office = "",
      photoBase64 = "";
  bool isLoadingUser = true;
  int unreadCount = 0; // Tracking unread notifications locally

  // Stream subscriptions for proper cleanup
  StreamSubscription<QuerySnapshot>? _notifSub;
  StreamSubscription<DocumentSnapshot>? _statusSub;

  @override
  void initState() {
    super.initState();
    NotificationService.requestPermissions(); // Request permissions on start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.requestBackgroundExecution(context);
    });
    _listenToUserStatus();
    _listenToNotifications();
    _loadUnreadCount();
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      unreadCount = prefs.getInt('unread_count') ?? 0;
    });
  }

  Future<void> _incrementUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    int current = prefs.getInt('unread_count') ?? 0;
    await prefs.setInt('unread_count', current + 1);
    setState(() {
      unreadCount = current + 1;
    });
  }

  Future<void> _resetUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('unread_count', 0);
    setState(() {
      unreadCount = 0;
    });
  }

  /// Listens for unread notifications sent to the current user and shows an in-app banner.
  void _listenToNotifications() {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;

    _notifSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('to', isEqualTo: email)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;

          // Mark as read immediately so the banner only appears once
          change.doc.reference.update({'isRead': true});

          final title = data['title'] ?? 'Task Update';
          final taskName = data['taskName'] ?? 'a task';
          final eventTitle = data['eventTitle'] ?? '';
          
          // Use body from Firestore if available, otherwise construct one
          String body = data['body'] ?? '';
          if (body.isEmpty) {
            body = eventTitle.isNotEmpty
                ? 'Check "$taskName" under "$eventTitle".'
                : 'Check your task: "$taskName".';
          }

          // Trigger system-level "popup" notification (outside the app)
          NotificationService.showNotification(
            title: title,
            body: body,
            payload: json.encode({
              'title': title,
              'body': body,
              'taskName': taskName,
              'eventTitle': eventTitle,
              'id': change.doc.id,
            }),
          );

          // Update local unread count
          _incrementUnreadCount();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.notifications_active, color: Colors.white, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                          Text(body,
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFF700202),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(12),
              ),
            );
          }
        }
      }
    }, onError: (e) {
      debugPrint("Notification stream error: $e");
    });
  }

  void _listenToUserStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _statusSub = FirebaseFirestore.instance
          .collection('users')
          .doc(user.email)
          .snapshots()
          .listen((doc) {
        if (mounted && doc.exists) {
          final data = doc.data();
          setState(() {
            role = data?['role'] ?? "staff";
            name = role == 'admin' ? "Macky Ocay" : (data?['fullName'] ?? "Member");
            status = data?['status'] ?? "pending";
            employmentType = role == 'admin' ? "admin" : (data?['employmentType'] ?? "staff");
            office = data?['office'] ?? "SOCCOM";
            photoBase64 = data?['photoBase64'] ?? "";
            isLoadingUser = false;
          });
        }
      }, onError: (e) {
        if (mounted) setState(() => isLoadingUser = false);
      });
    }
  }

  Future<void> _signOut() async {
    // Cancel listeners immediately to prevent "Permission Denied" crashes
    await _notifSub?.cancel();
    await _statusSub?.cancel();
    await FirebaseAuth.instance.signOut();
  }

  // Admin utility function to ensure data integrity
  Future<void> repairUserStatuses() async {
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    WriteBatch batch = FirebaseFirestore.instance.batch();
    int count = 0;
    for (var doc in snapshot.docs) {
      if (!doc.data().containsKey('status')) {
        batch.update(doc.reference, {'status': 'approved'});
        count++;
      }
    }
    await batch.commit();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Fixed $count users.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoadingUser) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: kPrimaryColor)));
    }

    final bool isPrivileged = role == 'admin' || role == 'sub-admin';

    // Redirect unapproved users (except main admin)
    if (role != 'admin' && status == 'pending') return _buildStatusScreen();

    // Define Tabs dynamically based on role
    final List<Map<String, dynamic>> tabs = [
      {
        'label': 'Events',
        'icon': Icons.assignment_outlined,
        'view': TaskFeed(isArchive: false, isAdmin: isPrivileged)
      },
      {
        'label': 'Calendar',
        'icon': Icons.calendar_month_outlined,
        'view': CalendarMonitor(isAdmin: isPrivileged)
      },
    ];

    if (isPrivileged) {
      tabs.add({
        'label': 'Archive',
        'icon': Icons.archive_outlined,
        // Sub-admins only see their own archive via filtering logic in TaskFeed
        'view': TaskFeed(
            isArchive: true,
            isAdmin: role == 'admin',
            subAdminEmail: role == 'sub-admin'
                ? FirebaseAuth.instance.currentUser?.email
                : null)
      });
      if (role == 'admin') {
        tabs.add({
          'label': 'Teams',
          'icon': Icons.group_outlined,
          'view': const TeamView()
        });
      }
    }

    // Safety check for index out of bounds after role changes
    int safeIdx = _idx >= tabs.length ? 0 : _idx;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryColor,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', height: 30),
            const SizedBox(width: 10),
            const Text("CSCAA TASKFLOW",
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ],
        ),
      ),
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: kPrimaryColor),
              accountName: Text(name),
              accountEmail: Text(FirebaseAuth.instance.currentUser?.email ?? ""),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                backgroundImage: photoBase64.isNotEmpty ? MemoryImage(base64Decode(photoBase64)) : null,
                child: photoBase64.isEmpty ? const Icon(Icons.person, color: kPrimaryColor, size: 40) : null,
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ...tabs.asMap().entries.map((entry) {
                    int idx = entry.key;
                    Map<String, dynamic> t = entry.value;
                    return ListTile(
                      leading: Icon(t['icon'], color: _idx == idx ? kPrimaryColor : Colors.grey),
                      title: Text(t['label'], style: TextStyle(color: _idx == idx ? kPrimaryColor : Colors.black, fontWeight: _idx == idx ? FontWeight.bold : FontWeight.normal)),
                      onTap: () {
                        setState(() => _idx = idx);
                        Navigator.pop(context); // Close drawer
                      },
                    );
                  }),
                  ListTile(
                    leading: Badge(
                      label: unreadCount > 0 ? Text(unreadCount.toString()) : null,
                      isLabelVisible: unreadCount > 0,
                      child: const Icon(Icons.notifications_outlined, color: Colors.grey),
                    ),
                    title: const Text("Notifications"),
                    onTap: () async {
                      Navigator.pop(context);
                      await Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsPage()));
                      _resetUnreadCount();
                    },
                  ),
                ],
              ),
            ),
             ListTile(
               leading: const Icon(Icons.logout, color: Colors.grey),
               title: const Text("Logout", style: TextStyle(color: Colors.grey)),
                 onTap: () async {
                   Navigator.pop(context);
                   // Logout logic
                   await NotificationService.removeTokenOnLogout();
                   if (!context.mounted) return;
                   CustomDialogs.showLogoutOptions(
                     context: context,
                     role: role,
                     onRepair: repairUserStatuses,
                     onLogout: _signOut,
                   );
                 }
             ),
             const SizedBox(height: 10),
          ],
        ),
      ),
      body: Column(children: [
        UserHeader(name: name, employmentType: employmentType, office: office, photoBase64: photoBase64.isEmpty ? null : photoBase64),
        Expanded(child: tabs[safeIdx]['view']),
      ]),
      floatingActionButton: (safeIdx == 0 && isPrivileged)
          ? FloatingActionButton(
              backgroundColor: kPrimaryColor,
              onPressed: () => TaskModal.show(context, userRole: role),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildStatusScreen() {
    return Scaffold(
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.hourglass_top, size: 80, color: kPrimaryColor),
          const SizedBox(height: 20),
          const Text("Approval Pending",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text("Please wait for Admin approval.",
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 30),
          ElevatedButton(
              onPressed: _signOut,
              child: const Text("Log Out")),
        ]),
      ),
    );
  }
}
