import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'widgets/custom_dialogs.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _isLoading = false;
  String _employmentType = "Employee";
  String _office = "SOCCOM";
  final bool _isUploading = false;
  Uint8List? _idPhotoBytes;

  Future<void> _handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || (_isSignUp && (name.isEmpty || _idPhotoBytes == null))) {
      _showError(_isSignUp && _idPhotoBytes == null 
          ? "Please select identification photo first" 
          : "Please fill in all fields");
      return;
    }

    if (!email.endsWith('@hcdc.edu.ph')) {
      _showError("Please use your HCDC email address");
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isSignUp) {
        // 1. Check if user already exists
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(email)
              .get();
          if (doc.exists) {
            _showError("Account already exists in the system.");
            setState(() => _isLoading = false);
            return;
          }
        } catch (e) {
          debugPrint("Firestore check bypassed: $e");
        }

        // 2. Create Auth User
        UserCredential cred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        // 3. Compress and Convert to Base64 (Free Tier Strategy)
        String base64String = "";
        try {
          if (_idPhotoBytes != null) {
            debugPrint("Compressing photo for Firestore storage...");
            final image = img.decodeImage(_idPhotoBytes!);
            if (image != null) {
              final resized = (image.width > 800 || image.height > 800) 
                  ? img.copyResize(image, width: image.width > image.height ? 800 : null, height: image.height >= image.width ? 800 : null)
                  : image;
              final compressedBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 70));
              base64String = base64Encode(compressedBytes);
            }
          }
        } catch (e) {
          debugPrint("Photo compression failed: $e");
        }

        // 4. Set Role/Status Logic
        String initialStatus = (email == 'admin@hcdc.edu.ph') ? 'approved' : 'pending';
        String initialRole = (email == 'admin@hcdc.edu.ph') ? 'admin' : 'staff';

        // 5. Save to Firestore
        await FirebaseFirestore.instance.collection('users').doc(email).set({
          'fullName': name,
          'email': email,
          'uid': cred.user!.uid,
          'employmentType': _employmentType,
          'office': _office,
          'role': initialRole,
          'status': initialStatus,
          'photoBase64': base64String.isNotEmpty ? base64String : null,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
           await CustomDialogs.showMessageDialog(
              context: context,
              title: "Registration Success",
              message: "Your account is pending admin approval.");
           setState(() => _isSignUp = false);
        }
      } else {
        await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Authentication failed");
    } catch (e) {
      _showError("An unexpected error occurred.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadID() async {
    final ImagePicker picker = ImagePicker();
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text("Select Photo Source", style: TextStyle(fontWeight: FontWeight.bold))),
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

    final bytes = await image.readAsBytes();
    if (!mounted) return;
    
    final bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Photo"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Are you sure you want to use this photo for your identification?"),
            const SizedBox(height: 15),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(bytes, height: 200),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CHANGE")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("USE THIS PHOTO")),
        ],
      ),
    ) ?? false;

    if (confirm && mounted) {
      setState(() => _idPhotoBytes = bytes);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ID Selected Successfully!"), backgroundColor: Colors.blue),
      );
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3F598F), Color(0xFF700202)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 30),
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/logo.png', height: 80),
                  const SizedBox(height: 10),
                  const Text("CSCAA TASKFLOW",
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF3F598F))),
                  const Text("Task Management System for CSCAA Staff",
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 30),
                  if (_isSignUp) ...[
                    _buildInputField(
                        controller: _nameController,
                        hint: "Full Name",
                        icon: Icons.person_outline),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      initialValue: _office,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.business_outlined, color: Colors.grey, size: 20),
                        labelText: "Office",
                        border: UnderlineInputBorder(),
                      ),
                      items: ["SOCCOM", "Alumni Office"]
                          .map((type) => DropdownMenuItem<String>(value: type, child: Text(type)))
                          .toList(),
                      onChanged: (val) => setState(() => _office = val!),
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      initialValue: _employmentType,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.badge_outlined,
                            color: Colors.grey, size: 20),
                        labelText: "Employment Type",
                        border: UnderlineInputBorder(),
                      ),
                      items: ["Employee", "Student Assistant", "Intern", "Alumni"]
                          .map((type) =>
                              DropdownMenuItem<String>(value: type, child: Text(type)))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _employmentType = val!),
                    ),
                    const SizedBox(height: 15),
                    _isUploading 
                      ? const CircularProgressIndicator()
                      : OutlinedButton.icon(
                          onPressed: _pickAndUploadID,
                          icon: Icon(_idPhotoBytes == null ? Icons.upload_file : Icons.check_circle, 
                            color: _idPhotoBytes == null ? const Color(0xFF3F598F) : Colors.green),
                          label: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_idPhotoBytes == null ? "UPLOAD IDENTIFICATION" : "ID SELECTED",
                                style: TextStyle(color: _idPhotoBytes == null ? const Color(0xFF3F598F) : Colors.green, fontWeight: FontWeight.bold)),
                              if (_idPhotoBytes == null)
                                const Text("Accepts JPG/PNG photos of your ID", style: TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            side: BorderSide(color: _idPhotoBytes == null ? const Color(0xFF3F598F) : Colors.green),
                          ),
                        ),
                    const SizedBox(height: 15),
                  ],
                  _buildInputField(
                      controller: _emailController,
                      hint: "HCDC Email (@hcdc.edu.ph)",
                      icon: Icons.email_outlined),
                  const SizedBox(height: 15),
                  _buildInputField(
                    controller: _passwordController,
                    hint: "Password",
                    icon: Icons.lock_outline,
                    isPassword: true,
                    suffix: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 30),
                  _isLoading
                      ? const CircularProgressIndicator(
                          color: Color(0xFF3F598F))
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3F598F),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 55),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                          ),
                          onPressed: _handleAuth,
                          child: Text(_isSignUp ? "REGISTER ACCOUNT" : "LOGIN"),
                        ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => setState(() {
                      _isSignUp = !_isSignUp;
                      _isLoading = false;
                    }),
                    child: Text(
                      _isSignUp
                          ? "Already approved? Login here"
                          : "New Employee, Student Assistant, or Intern? Register for access",
                      style: const TextStyle(color: Color(0xFF3F598F)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword ? _obscurePassword : false,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.grey, size: 20),
        suffixIcon: suffix,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
        enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.grey)),
        focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF3F598F), width: 2)),
      ),
    );
  }
}
