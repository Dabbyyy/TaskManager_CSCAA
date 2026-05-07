import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EvaluationView extends StatelessWidget {
  final String currentRole;

  const EvaluationView({super.key, required this.currentRole});

  @override
  Widget build(BuildContext context) {
    final currentEmail = FirebaseAuth.instance.currentUser?.email ?? "";

    return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').where('status', isEqualTo: 'approved').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var docs = snapshot.data!.docs;

          // Admin can see all users, including themselves? Usually you don't evaluate yourself.
          // Let's hide the current user.
          docs = docs.where((doc) => doc.id != currentEmail).toList();

          // Sub-admin can only rate staff (except admin)
          if (currentRole == 'sub-admin') {
            docs = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['role'] != 'admin';
            }).toList();
          }

          if (docs.isEmpty) {
             return const Center(child: Text("No users to evaluate."));
          }

          return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (ctx, idx) {
                final user = docs[idx].data() as Map<String, dynamic>;
                final email = docs[idx].id;
                final name = user['fullName'] ?? email;
                final role = user['role'] ?? 'staff';
                final empType = user['employmentType'] ?? '';
                final office = user['office'] ?? '';

                String subtitleText = "$email • ${role.toUpperCase()}";
                if (office.isNotEmpty) subtitleText += " • ${office.toUpperCase()}";
                if (empType.isNotEmpty) subtitleText += " • ${empType.toUpperCase()}";

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ExpansionTile(
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(subtitleText, style: const TextStyle(fontSize: 12)),
                    leading: const CircleAvatar(backgroundColor: Color(0xFF3F598F), child: Icon(Icons.person, color: Colors.white)),
                    children: [
                      ListTile(
                        leading: const Icon(Icons.star_rate, color: Colors.orange),
                        title: const Text("Rate & Add Evaluation"),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                        onTap: () {
                          _showRatingDialog(context, email, name);
                        },
                      ),
                      // Stream view of previous evaluations for this user
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('evaluations')
                            .where('targetEmail', isEqualTo: email)
                            .orderBy('timestamp', descending: true)
                            .snapshots(),
                        builder: (ctx, evalSnap) {
                           if (!evalSnap.hasData || evalSnap.data!.docs.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text("No evaluations yet.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                              );
                           }
                           return ListView.builder(
                             shrinkWrap: true,
                             physics: const NeverScrollableScrollPhysics(),
                             itemCount: evalSnap.data!.docs.length,
                             itemBuilder: (c, i) {
                               final eval = evalSnap.data!.docs[i].data() as Map<String, dynamic>;
                               return ListTile(
                                 dense: true,
                                 title: Text("${eval['feedback']} (Rating: ${eval['rating']})"),
                                 subtitle: Text("By: ${eval['evaluatorEmail']} • ${eval['timestamp'] != null ? (eval['timestamp'] as Timestamp).toDate().toString().split('.')[0] : ''}"),
                               );
                             }
                           );
                        }
                      )
                    ],
                  ),
                );
              });
        });
  }

  void _showRatingDialog(BuildContext context, String targetEmail, String targetName) {
    double selectedRating = 3.0;
    final controller = TextEditingController();

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) {
              return AlertDialog(
                  title: Text("Rate $targetName", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(5, (index) {
                            return IconButton(
                              icon: Icon(
                                index < selectedRating ? Icons.star : Icons.star_border,
                                color: Colors.amber,
                                size: 36,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  selectedRating = index + 1.0;
                                });
                              },
                            );
                          }),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: controller,
                          decoration: const InputDecoration(labelText: "Comments / Evaluation", border: OutlineInputBorder()),
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                        )
                      ]),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3F598F)),
                        onPressed: () async {
                          if (controller.text.trim().isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Please add a comment.")));
                            return;
                          }
                          await FirebaseFirestore.instance.collection('evaluations').add({
                            'targetEmail': targetEmail,
                            'rating': selectedRating,
                            'feedback': controller.text.trim(),
                            'timestamp': FieldValue.serverTimestamp(),
                            'evaluatorRole': currentRole,
                            'evaluatorEmail': FirebaseAuth.instance.currentUser?.email ?? "Unknown",
                          });
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Evaluation added!")));
                          }
                        },
                        child: const Text("SUBMIT", style: TextStyle(color: Colors.white)))
                  ]);
            })
    );
  }
}
