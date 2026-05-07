import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

// Temporarily removed image_cropper to fix compilation and allow upload
// Removed dart:io for web compatibility

class UserHeader extends StatelessWidget {
  final String name;
  final String employmentType;
  final String? office;
  final String? photoBase64;

  const UserHeader({
    super.key,
    required this.name,
    required this.employmentType,
    this.office,
    this.photoBase64,
  });

  Future<void> _updateID(BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    
    // Choose Source
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text("Update Photo Source", style: TextStyle(fontWeight: FontWeight.bold))),
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text("Camera"),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text("Gallery"),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    );

    if (source == null) return;
    final XFile? image = await picker.pickImage(source: source);
    
    if (image == null) return;

    // Confirmation Modal
    final bytes = await image.readAsBytes();
    if (!context.mounted) return;
    
    final bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Photo"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Update your identification photo with this one?"),
            const SizedBox(height: 15),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(bytes, height: 200),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("USE THIS PHOTO")),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    try {
      final email = FirebaseAuth.instance.currentUser?.email;
      if (email == null) return;

      debugPrint("Compressing photo for update...");
      final image = img.decodeImage(bytes);
      if (image != null) {
        final resized = (image.width > 800 || image.height > 800) 
            ? img.copyResize(image, width: image.width > image.height ? 800 : null, height: image.height >= image.width ? 800 : null)
            : image;
        final compressed = Uint8List.fromList(img.encodeJpg(resized, quality: 70));
        final base64String = base64Encode(compressed);

        await FirebaseFirestore.instance.collection('users').doc(email).update({
          'photoBase64': base64String,
        });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Profile Photo Updated!"), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Update Failed: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "Hello, $name!",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3F598F),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.waving_hand, color: Colors.orange, size: 20),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF3F598F).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              (office != null && office!.isNotEmpty) ? "${office!.toUpperCase()} • ${employmentType.toUpperCase()}" : employmentType.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3F598F),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: const Color(0xFF3F598F).withValues(alpha: 0.1),
                backgroundImage: photoBase64 != null ? MemoryImage(base64Decode(photoBase64!)) : null,
                child: photoBase64 == null ? const Icon(Icons.person, color: Color(0xFF3F598F)) : null,
              ),
              const SizedBox(width: 15),
              if (photoBase64 == null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _updateID(context),
                    icon: const Icon(Icons.upload, size: 16),
                    label: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("UPLOAD IDENTIFICATION", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        Text("Accepts JPG/PNG photos", style: TextStyle(fontSize: 9, color: Colors.grey)),
                      ],
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF3F598F),
                      side: const BorderSide(color: Color(0xFF3F598F)),
                    ),
                  ),
                ),
              if (photoBase64 != null)
                OutlinedButton.icon(
                  onPressed: () => _updateID(context),
                  icon: const Icon(Icons.refresh, size: 16, color: Colors.green),
                  label: const Text("UPDATE PHOTO", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    side: const BorderSide(color: Colors.green),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(thickness: 1, color: Color(0xFFEEEEEE)),
        ],
      ),
    );
  }
}
