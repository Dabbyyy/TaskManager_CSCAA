import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'custom_dialogs.dart';

class TeamView extends StatelessWidget {
  const TeamView({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final users = snapshot.data!.docs;

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final userData = users[index].data() as Map<String, dynamic>;
            final String email = users[index].id;
            final String role = userData['role'] ?? 'staff';
            final String name = role == 'admin' ? 'Macky Ocay' : (userData['fullName'] ?? 'No Name');
            final String status = userData['status'] ?? 'pending';
            final String empType = userData['employmentType'] ?? '';
            final String ofc = userData['office'] ?? '';
            final String? photoBase64 = userData['photoBase64'];

            String subtitleText = "$email • ${role.toUpperCase()}";
            if (ofc.isNotEmpty) subtitleText += " • ${ofc.toUpperCase()}";
            if (empType.isNotEmpty) subtitleText += " • ${empType.toUpperCase()}";

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ListTile(
                leading: GestureDetector(
                  onTap: photoBase64 != null ? () {
                    showDialog(
                      context: context,
                      builder: (ctx) => Scaffold(
                        backgroundColor: Colors.black,
                        appBar: AppBar(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          title: Text("$name - ID"),
                        ),
                        body: Center(
                          child: InteractiveViewer(
                            child: Image.memory(base64Decode(photoBase64),
                              errorBuilder: (context, error, stackTrace) => const Center(child: Text("Error loading ID", style: TextStyle(color: Colors.white))),
                            ),
                          ),
                        ),
                      ),
                    );
                  } : null,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 25,
                        backgroundImage: photoBase64 != null ? MemoryImage(base64Decode(photoBase64)) : null,
                        child: photoBase64 == null ? const Icon(Icons.person) : null,
                      ),
                      if (photoBase64 != null)
                        const CircleAvatar(
                          radius: 8,
                          backgroundColor: Colors.white,
                          child: Icon(Icons.zoom_in, size: 10, color: Color(0xFF3F598F)),
                        ),
                    ],
                  ),
                ),
                title: Text(name),
                subtitle: Text(subtitleText),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (status == 'pending') ...[
                      IconButton(
                        icon: const Icon(Icons.check_circle, color: Colors.green),
                        tooltip: "Accept",
                        onPressed: () async {
                          final confirmed = await CustomDialogs.showConfirmDialog(
                            context: context,
                            title: "Accept User",
                            message: "Are you sure you want to approve $name?",
                          );
                          if (confirmed == true) {
                            _updateUserStatus(email, 'approved');
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        tooltip: "Reject",
                        onPressed: () async {
                          final confirmed = await CustomDialogs.showConfirmDialog(
                            context: context,
                            title: "Reject User",
                            message: "Are you sure you want to reject and remove $name?",
                          );
                          if (confirmed == true) {
                            await FirebaseFirestore.instance.collection('users').doc(email).delete();
                          }
                        },
                      ),
                    ] else ...[
                      if (role != 'admin')
                        IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert),
                          onPressed: () => _showUserOptions(context, email, role),
                        ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- LOGIC FUNCTIONS (Since you don't have UserService) ---

  void _updateUserStatus(String email, String status) {
    FirebaseFirestore.instance
        .collection('users')
        .doc(email)
        .update({'status': status});
  }

  void _showUserOptions(
      BuildContext context, String email, String currentRole) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("User Options", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentRole != 'admin')
              ListTile(
                leading: const Icon(Icons.shield),
                title: Text(currentRole == 'sub-admin'
                    ? "Demote to Staff"
                    : "Make Sub-Admin"),
                onTap: () {
                  String newRole =
                      currentRole == 'sub-admin' ? 'staff' : 'sub-admin';
                  FirebaseFirestore.instance
                      .collection('users')
                      .doc(email)
                      .update({'role': newRole});
                  Navigator.pop(ctx);
                },
              ),
            ListTile(
              leading: const Icon(Icons.lock_reset, color: Colors.blue),
              title: const Text("Reset Password", style: TextStyle(color: Colors.blue)),
              onTap: () async {
                Navigator.pop(ctx); // Close the option dialog first
                try {
                  await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Password reset email sent to $email")),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error: ${e.toString()}")),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title:
                  const Text("Remove User", style: TextStyle(color: Colors.red)),
              onTap: () async {
                // Using the CustomDialogs we fixed earlier
                final confirmed = await CustomDialogs.showConfirmDialog(
                  context: ctx,
                  title: "Remove User",
                  message: "Are you sure you want to remove $email?",
                );
                if (confirmed == true) {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(email)
                      .delete();
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
