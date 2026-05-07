import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'custom_dialogs.dart';

class TaskModal {
  static const Color kPrimaryColor = Color(0xFF3F598F);

  static void show(BuildContext context,
      {DocumentSnapshot? existingTask, required String userRole}) {
    final titleCtrl = TextEditingController(
        text: existingTask != null ? existingTask['title'] : "");
    final instrCtrl = TextEditingController(
        text: existingTask != null ? existingTask['instructions'] : "");
    String selectedPriority =
        existingTask != null ? existingTask['priority'] : "Medium";
    String selectedOffice = existingTask != null 
        ? ((existingTask.data() as Map<String, dynamic>).containsKey('office') ? existingTask['office'] : "SOCCOM")
        : "SOCCOM";
    final Map<String, dynamic>? currentData =
        existingTask?.data() as Map<String, dynamic>?;
    List<Map<String, dynamic>> subTasks =
        currentData != null && currentData.containsKey('subTasks')
            ? List<Map<String, dynamic>>.from(currentData['subTasks'])
            : [];

    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return FutureBuilder<QuerySnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .where('status', isEqualTo: 'approved')
                .get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 300,
                  child: Center(
                      child: CircularProgressIndicator(color: kPrimaryColor)),
                );
              }

              final Map<String, String> staffMap = {};
              for (var doc in snapshot.data!.docs) {
                final userData = doc.data() as Map<String, dynamic>;
                if (userData['role'] == 'admin') continue;

                // Filter by office
                String ofc = userData['office'] ?? '';
                if (ofc != selectedOffice) continue;

                String displayName = userData['fullName'] ?? doc.id;
                String empType = userData['employmentType'] ?? '';

                String extraInfo = "";
                if (empType.isNotEmpty) {
                  extraInfo += empType;
                }

                if (extraInfo.isNotEmpty) {
                  displayName += " ($extraInfo)";
                }
                staffMap[doc.id] = displayName;
              }

              return Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                    left: 20,
                    right: 20,
                    top: 20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                            existingTask == null
                                ? "Create New Event"
                                : "Edit Event",
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                          controller: titleCtrl,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                              labelText: "Event Title",
                              border: OutlineInputBorder())),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedOffice,
                        decoration: const InputDecoration(
                            labelText: "Create task for",
                            border: OutlineInputBorder()),
                        items: ["SOCCOM", "Alumni"].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                        onChanged: (val) => setModalState(() => selectedOffice = val!),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                          controller: instrCtrl,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                              labelText: "Event description",
                              border: OutlineInputBorder())),
                      const SizedBox(height: 12),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedPriority,
                        items: ["High", "Medium", "Low"]
                            .map((p) => DropdownMenuItem(
                                value: p, child: Text(p)))
                            .toList(),
                        onChanged: (val) {
                          setModalState(() {
                            selectedPriority = val!;
                          });
                        },
                        decoration: const InputDecoration(
                            labelText: "Event priority",
                            border: OutlineInputBorder()),
                      ),
                      if (subTasks.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text("TASKS:",
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey)),
                        const SizedBox(height: 10),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: subTasks.length,
                          itemBuilder: (context, index) {
                            final st = subTasks[index];
                            final assignedNames = (st['assignedTo'] as List)
                                .map((e) => staffMap[e] ?? e)
                                .join(", ");
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(st['task']),
                              subtitle: Text("Assigned: $assignedNames\nPriority: ${st['priority'] ?? 'N/A'} | Due: ${st['deadline'] != null ? DateFormat('MMM d').format((st['deadline'] as Timestamp).toDate()) : 'N/A'}",
                                  style: const TextStyle(fontSize: 11)),
                              trailing: IconButton(
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  setModalState(() {
                                    subTasks.removeAt(index);
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 55),
                                  side: const BorderSide(color: Colors.grey),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12))),
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text("CANCEL",
                                  style: TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimaryColor,
                                  minimumSize: const Size(0, 55),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12))),
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      if (titleCtrl.text.isEmpty) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                            const SnackBar(
                                                content: Text(
                                                    "Please enter an event title")));
                                        return;
                                      }

                                      if (existingTask == null) {
                                        // CREATE NEW EVENT -> PROCEED TO TASK
                                        showAddTaskDialog(context, staffMap, (newTask) async {
                                          if (ctx.mounted) setModalState(() => isSaving = true);
                                          
                                          try {
                                            final data = {
                                              'title': titleCtrl.text.trim(),
                                              'instructions': instrCtrl.text.trim(),
                                              'priority': selectedPriority,
                                              'office': selectedOffice,
                                              'assignedTo': newTask['assignedTo'],
                                              'subTasks': [newTask],
                                              'deadline': newTask['deadline'],
                                              'isDone': false,
                                              'isAccepted': false,
                                              'status': 'Pending',
                                              'createdAt': FieldValue.serverTimestamp(),
                                              'createdBy': FirebaseAuth.instance.currentUser?.email,
                                            };
                                            
                                            await FirebaseFirestore.instance.collection('tasks').add(data);
                                            
                                            // Create notifications for assigned users to trigger the "pop-up" heads-up effect
                                            for (String userEmail in (newTask['assignedTo'] as List)) {
                                              await FirebaseFirestore.instance.collection('notifications').add({
                                                'to': userEmail,
                                                'title': 'New Task Assigned',
                                                'taskName': newTask['task'],
                                                'eventTitle': titleCtrl.text.trim(),
                                                'isRead': false, // Will be picked up by navigation_screen listener
                                                'createdAt': FieldValue.serverTimestamp(),
                                              });
                                            }
                                            
                                            if (ctx.mounted) {
                                              Navigator.pop(ctx);
                                              if (context.mounted) {
                                                await CustomDialogs.showMessageDialog(
                                                  context: context,
                                                  title: "Success",
                                                  message: "Event & Task Created Successfully",
                                                );
                                              }
                                            }
                                          } catch (e) {
                                            if (ctx.mounted) {
                                              ScaffoldMessenger.of(ctx).showSnackBar(
                                                  SnackBar(content: Text("Error: ${e.toString()}")));
                                            }
                                          } finally {
                                            if (ctx.mounted) setModalState(() => isSaving = false);
                                          }
                                        });
                                      } else {
                                        // UPDATE EXISTING EVENT
                                        final confirmed = await CustomDialogs.showConfirmDialog(
                                          context: context,
                                          title: "Confirm Update Event",
                                          message: "Are you sure you want to update this event?",
                                        );

                                        if (confirmed != true) return;

                                        if (ctx.mounted) setModalState(() => isSaving = true);

                                        try {
                                          await existingTask.reference.update({
                                            'title': titleCtrl.text.trim(),
                                            'instructions': instrCtrl.text.trim(),
                                            'priority': selectedPriority,
                                            'office': selectedOffice,
                                          });

                                          if (ctx.mounted) {
                                            Navigator.pop(ctx);
                                            if (context.mounted) {
                                              await CustomDialogs.showMessageDialog(
                                                context: context,
                                                title: "Success",
                                                message: "Event Updated Successfully",
                                              );
                                            }
                                          }
                                        } catch (e) {
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(ctx).showSnackBar(
                                                SnackBar(content: Text("Error: ${e.toString()}")));
                                          }
                                        } finally {
                                          if (ctx.mounted) setModalState(() => isSaving = false);
                                        }
                                      }
                                    },
                              child: isSaving
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2))
                                  : Text(
                                      existingTask == null
                                          ? "CREATE EVENT"
                                          : "UPDATE EVENT",
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static void showAddTaskDialog(
      BuildContext context,
      Map<String, String> staffMap,
      Function(Map<String, dynamic>) onAdded,
      {Map<String, dynamic>? existingTask}) {
    final titleCtrl = TextEditingController(text: existingTask != null ? existingTask['task'] : "");
    final instrCtrl = TextEditingController(text: existingTask != null ? existingTask['instructions'] : "");
    String selectedPriority = existingTask != null ? existingTask['priority'] : "Medium";
    DateTime? selectedDeadline = existingTask != null && existingTask['deadline'] != null
        ? (existingTask['deadline'] as Timestamp).toDate()
        : null;
    List<String> assignedTo = existingTask != null && existingTask['assignedTo'] != null
        ? List<String>.from(existingTask['assignedTo'])
        : [];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Center(child: Text(existingTask == null ? "Create Task" : "Edit Task", style: const TextStyle(fontWeight: FontWeight.bold))),
            content: SingleChildScrollView(
              child: SizedBox(
                width: MediaQuery.of(ctx).size.width * 0.8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                          labelText: "Task Name",
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: instrCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: "Instructions",
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                             initialValue: selectedPriority,
                             items: ["High", "Medium", "Low"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                             onChanged: (v) => setDialogState(() => selectedPriority = v!),
                             decoration: const InputDecoration(labelText: "Priority", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                            icon: const Icon(Icons.event, size: 16),
                            label: Text(selectedDeadline == null ? "Deadline" : DateFormat('MMM d').format(selectedDeadline!), style: const TextStyle(fontSize: 12)),
                            onPressed: () async {
                              DateTime? d = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime(2030));
                              if (d != null && context.mounted) {
                                TimeOfDay? t = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.now());
                                if (t != null) {
                                  setDialogState(() => selectedDeadline =
                                      DateTime(d.year, d.month, d.day, t.hour, t.minute));
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    const Text("Assign To:", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                          labelText: "Select Staff to Assign",
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                      items: staffMap.keys
                          .map((email) => DropdownMenuItem(
                                value: email,
                                child: Text(staffMap[email]!),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null && !assignedTo.contains(val)) {
                          setDialogState(() {
                            assignedTo.add(val);
                          });
                        }
                      },
                      initialValue: null,
                      hint: const Text("Select to add..."),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: assignedTo.map((email) {
                        return InputChip(
                          label: Text(staffMap[email] ?? email, style: const TextStyle(fontSize: 12)),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () {
                            setDialogState(() {
                              assignedTo.remove(email);
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("CANCEL")),
              ElevatedButton(
                onPressed: () {
                  if (titleCtrl.text.trim().isEmpty) {
                    CustomDialogs.showMessageDialog(context: context, title: "Missing Field", message: "Please enter a task name.");
                    return;
                  }
                  if (assignedTo.isEmpty) {
                    CustomDialogs.showMessageDialog(context: context, title: "Missing Field", message: "Please assign at least one member.");
                    return;
                  }
                  if (selectedDeadline == null) {
                    CustomDialogs.showMessageDialog(context: context, title: "Missing Field", message: "Please set a deadline.");
                    return;
                  }
                  Navigator.pop(ctx);
                  onAdded({
                    'task': titleCtrl.text.trim(),
                    'instructions': instrCtrl.text.trim(),
                    'priority': selectedPriority,
                    'deadline': selectedDeadline,
                    'assignedTo': assignedTo,
                    'isDone': existingTask != null ? (existingTask['isDone'] ?? false) : false,
                  });
                },
                child: Text(existingTask != null ? "SAVE TASK" : "ADD TASK"),
              ),
            ],
          );
        },
      ),
    );
  }
}
