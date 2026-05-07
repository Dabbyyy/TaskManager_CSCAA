import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CustomDialogs {
  // Fix for the "showConfirmDialog" error
  static Future<bool?> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("CONFIRM", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  static Future<void> showMessageDialog({
    required BuildContext context,
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // Support for the Logout/Repair DB dialog
  static void showLogoutOptions({
    required BuildContext context,
    required String role,
    required VoidCallback onRepair,
    VoidCallback? onLogout,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Account Options"),
        content: const Text("What would you like to do?"),
        actions: [
          if (role == 'admin')
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                onRepair();
              },
              child: const Text("REPAIR DB",
                  style: TextStyle(color: Colors.orange)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (onLogout != null) {
                onLogout();
              } else {
                FirebaseAuth.instance.signOut();
              }
            },
            child: const Text("LOGOUT", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
