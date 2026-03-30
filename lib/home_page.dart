import 'dart:io';

import 'package:face_verification/face_verification.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _userId = 'profile_user';
  static const _imageId = 'profile_face';

  final ImagePicker _picker = ImagePicker();

  File? _profileImage;
  File? _documentImage;

  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isProfileRegistered = false;

  String _statusMessage = 'Initializing face engine...';
  Color _statusColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await FaceVerification.instance.init();
      // Check if a profile was already registered (cached from previous session)
      final alreadyRegistered =
          await FaceVerification.instance.isFaceRegistered(_userId);
      setState(() {
        _isInitialized = true;
        _isProfileRegistered = alreadyRegistered;
        _statusMessage = alreadyRegistered
            ? 'Profile face loaded from cache. Ready to compare.'
            : 'Engine ready. Register a profile face to begin.';
        _statusColor = Colors.green;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Initialization failed: $e';
        _statusColor = Colors.red;
      });
    }
  }

  Future<void> _pickImage(ImageSource source, bool isProfile) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 90,
    );
    if (picked == null) return;
    setState(() {
      if (isProfile) {
        _profileImage = File(picked.path);
      } else {
        _documentImage = File(picked.path);
      }
    });
  }

  Future<void> _registerProfileFace() async {
    if (!_isInitialized) return;
    if (_profileImage == null) {
      _setStatus('Select a profile image first.', Colors.orange);
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Embedding and saving profile face...';
      _statusColor = Colors.blue;
    });

    try {
      await FaceVerification.instance.registerFromImagePath(
        id: _userId,
        imagePath: _profileImage!.path,
        imageId: _imageId,
        name: 'Profile User',
        replace: true, // overwrite if re-registering
      );
      setState(() {
        _isProfileRegistered = true;
      });
      _setStatus(
        'Profile face embedded and cached. Ready to compare.',
        Colors.green,
      );
    } catch (e) {
      _setStatus('Registration failed: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _compareFaces() async {
    if (!_isInitialized) return;
    if (!_isProfileRegistered) {
      _setStatus('Register a profile face first.', Colors.orange);
      return;
    }
    if (_documentImage == null) {
      _setStatus('Select a document/test image first.', Colors.orange);
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Comparing faces...';
      _statusColor = Colors.blue;
    });

    try {
      final matchedId = await FaceVerification.instance.verifyFromImagePath(
        imagePath: _documentImage!.path,
        threshold: 0.70,
        staffId: _userId,
      );

      if (matchedId == _userId) {
        _setStatus('✅ Same person — faces match!', Colors.green);
      } else {
        _setStatus('❌ Different person — faces do not match.', Colors.red);
      }
    } catch (e) {
      _setStatus('Comparison failed: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearProfile() async {
    try {
      await FaceVerification.instance.deleteUserFaces(_userId);
      setState(() {
        _isProfileRegistered = false;
        _profileImage = null;
        _documentImage = null;
      });
      _setStatus('Profile cleared. Register a new face to begin.', Colors.grey);
    } catch (e) {
      _setStatus('Clear failed: $e', Colors.red);
    }
  }

  void _setStatus(String msg, Color color) {
    setState(() {
      _statusMessage = msg;
      _statusColor = color;
    });
  }

  @override
  void dispose() {
    FaceVerification.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Recognition'),
        actions: [
          if (_isProfileRegistered)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear registered face',
              onPressed: _isLoading ? null : _clearProfile,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status banner
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.13),
                border: Border.all(color: _statusColor.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (_isLoading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(Icons.info_outline, color: _statusColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: TextStyle(color: _statusColor, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Profile image section
            _SectionHeader(
              label: '1. Profile Face',
              badge: _isProfileRegistered ? 'Registered ✓' : null,
              badgeColor: Colors.green,
            ),
            _ImageCard(file: _profileImage),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library, size: 16),
                    label: const Text('Gallery'),
                    onPressed: _isLoading
                        ? null
                        : () => _pickImage(ImageSource.gallery, true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.camera_alt, size: 16),
                    label: const Text('Camera'),
                    onPressed: _isLoading
                        ? null
                        : () => _pickImage(ImageSource.camera, true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _isLoading ? null : _registerProfileFace,
              child: const Text('Embed & Save Profile Face'),
            ),

            const SizedBox(height: 24),

            // Document image section
            const _SectionHeader(label: '2. Document / Test Image'),
            _ImageCard(file: _documentImage),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library, size: 16),
                    label: const Text('Gallery'),
                    onPressed: _isLoading
                        ? null
                        : () => _pickImage(ImageSource.gallery, false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.camera_alt, size: 16),
                    label: const Text('Camera'),
                    onPressed: _isLoading
                        ? null
                        : () => _pickImage(ImageSource.camera, false),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Compare button
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed:
                  (_isLoading || !_isProfileRegistered || _documentImage == null)
                      ? null
                      : _compareFaces,
              child: const Text(
                'Compare Faces',
                style: TextStyle(fontSize: 15),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final String? badge;
  final Color? badgeColor;

  const _SectionHeader({required this.label, this.badge, this.badgeColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: (badgeColor ?? Colors.blue).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  fontSize: 11,
                  color: badgeColor ?? Colors.blue,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  final File? file;

  const _ImageCard({this.file});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: file != null
          ? Image.file(
              file!,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            )
          : Container(
              height: 200,
              color: Colors.grey.shade100,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    'No image selected',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
    );
  }
}
