import 'dart:io';

import 'package:face_verification/face_verification.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
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
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  File? _profileImage;
  File? _documentImage;

  _FaceInsights _profileInsights = const _FaceInsights.empty();
  _FaceInsights _documentInsights = const _FaceInsights.empty();

  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isAnalyzingProfile = false;
  bool _isAnalyzingDocument = false;
  bool _isProfileRegistered = false;

  String _statusMessage = 'Initializing face engine...';
  Color _statusColor = Colors.grey;

  String _comparisonResult = 'No comparison yet.';
  Color _comparisonColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await FaceVerification.instance.init();
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

    final file = File(picked.path);
    setState(() {
      if (isProfile) {
        _profileImage = file;
      } else {
        _documentImage = file;
      }
    });

    await _analyzeImage(file, isProfile);
  }

  Future<void> _analyzeImage(File imageFile, bool isProfile) async {
    setState(() {
      if (isProfile) {
        _isAnalyzingProfile = true;
      } else {
        _isAnalyzingDocument = true;
      }
    });

    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final faces = await _faceDetector.processImage(inputImage);
      final insights = _FaceInsights.fromFaces(faces);

      setState(() {
        if (isProfile) {
          _profileInsights = insights;
        } else {
          _documentInsights = insights;
        }
      });
    } catch (e) {
      setState(() {
        if (isProfile) {
          _profileInsights = _FaceInsights(errorMessage: 'Analysis failed: $e');
        } else {
          _documentInsights = _FaceInsights(errorMessage: 'Analysis failed: $e');
        }
      });
    } finally {
      setState(() {
        if (isProfile) {
          _isAnalyzingProfile = false;
        } else {
          _isAnalyzingDocument = false;
        }
      });
    }
  }

  Future<void> _registerProfileFace() async {
    if (!_isInitialized) return;

    if (_profileImage == null) {
      _setStatus('Select a profile image first.', Colors.orange);
      return;
    }

    if (_profileInsights.faceCount != 1) {
      _setStatus('Profile image must contain exactly 1 face.', Colors.orange);
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
        replace: true,
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

    if (_documentInsights.faceCount != 1) {
      _setStatus('Document image must contain exactly 1 face.', Colors.orange);
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
        _setComparison('Same person detected.', Colors.green);
        _setStatus('Comparison complete.', Colors.green);
      } else {
        _setComparison('Different person or low confidence.', Colors.red);
        _setStatus('Comparison complete.', Colors.red);
      }
    } catch (e) {
      _setComparison('Comparison failed.', Colors.red);
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
        _profileInsights = const _FaceInsights.empty();
        _documentInsights = const _FaceInsights.empty();
      });
      _setComparison('No comparison yet.', Colors.grey);
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

  void _setComparison(String msg, Color color) {
    setState(() {
      _comparisonResult = msg;
      _comparisonColor = color;
    });
  }

  @override
  void dispose() {
    _faceDetector.close();
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
            _StatusBanner(
              isLoading: _isLoading,
              statusMessage: _statusMessage,
              statusColor: _statusColor,
            ),
            const SizedBox(height: 20),
            _SectionHeader(
              label: '1. Profile Face',
              badge: _isProfileRegistered ? 'Registered' : null,
              badgeColor: Colors.green,
            ),
            _ImageAnalysisRow(
              imageFile: _profileImage,
              insights: _profileInsights,
              isAnalyzing: _isAnalyzingProfile,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library, size: 16),
                  label: const Text('Profile Gallery'),
                  onPressed: _isLoading
                      ? null
                      : () => _pickImage(ImageSource.gallery, true),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('Profile Camera'),
                  onPressed: _isLoading
                      ? null
                      : () => _pickImage(ImageSource.camera, true),
                ),
                FilledButton(
                  onPressed: _isLoading ? null : _registerProfileFace,
                  child: const Text('Embed & Save Profile'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _SectionHeader(label: '2. Document / Test Face'),
            _ImageAnalysisRow(
              imageFile: _documentImage,
              insights: _documentInsights,
              isAnalyzing: _isAnalyzingDocument,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library, size: 16),
                  label: const Text('Document Gallery'),
                  onPressed: _isLoading
                      ? null
                      : () => _pickImage(ImageSource.gallery, false),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('Document Camera'),
                  onPressed: _isLoading
                      ? null
                      : () => _pickImage(ImageSource.camera, false),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed:
                  (_isLoading || !_isProfileRegistered || _documentImage == null)
                      ? null
                      : _compareFaces,
              child: const Text('Compare Faces'),
            ),
            const SizedBox(height: 16),
            _ComparisonCard(
              result: _comparisonResult,
              color: _comparisonColor,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _FaceInsights {
  final int faceCount;
  final String ageGroup;
  final String smile;
  final String leftEye;
  final String rightEye;
  final String qualityHint;
  final String? errorMessage;

  const _FaceInsights({
    this.faceCount = 0,
    this.ageGroup = 'Other',
    this.smile = '-',
    this.leftEye = '-',
    this.rightEye = '-',
    this.qualityHint = 'Select an image to analyze.',
    this.errorMessage,
  });

  const _FaceInsights.empty()
      : faceCount = 0,
        ageGroup = 'Other',
        smile = '-',
        leftEye = '-',
        rightEye = '-',
        qualityHint = 'Select an image to analyze.',
        errorMessage = null;

  factory _FaceInsights.fromFaces(List<Face> faces) {
    if (faces.isEmpty) {
      return const _FaceInsights(
        faceCount: 0,
        ageGroup: 'Other',
        qualityHint: 'No face detected.',
      );
    }

    final face = faces.first;

    final smileProb = face.smilingProbability;
    final leftEyeProb = face.leftEyeOpenProbability;
    final rightEyeProb = face.rightEyeOpenProbability;

    final smile = smileProb == null
        ? '-'
        : '${(smileProb * 100).toStringAsFixed(1)}%';
    final leftEye = leftEyeProb == null
        ? '-'
        : '${(leftEyeProb * 100).toStringAsFixed(1)}%';
    final rightEye = rightEyeProb == null
        ? '-'
        : '${(rightEyeProb * 100).toStringAsFixed(1)}%';

    String qualityHint;
    if (faces.length > 1) {
      qualityHint = 'Multiple faces detected. Use a single-face image.';
    } else if (face.boundingBox.width < 100 || face.boundingBox.height < 100) {
      qualityHint = 'Face looks small. Move closer for better matching.';
    } else {
      qualityHint = 'Good: one face detected.';
    }

    // ML Kit face detection does not provide true age estimation.
    const ageGroup = 'Other';

    return _FaceInsights(
      faceCount: faces.length,
      ageGroup: ageGroup,
      smile: smile,
      leftEye: leftEye,
      rightEye: rightEye,
      qualityHint: qualityHint,
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final bool isLoading;
  final String statusMessage;
  final Color statusColor;

  const _StatusBanner({
    required this.isLoading,
    required this.statusMessage,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.13),
        border: Border.all(color: statusColor.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (isLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.info_outline, color: statusColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusMessage,
              style: TextStyle(color: statusColor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  final String result;
  final Color color;

  const _ComparisonCard({required this.result, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              result,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageAnalysisRow extends StatelessWidget {
  final File? imageFile;
  final _FaceInsights insights;
  final bool isAnalyzing;

  const _ImageAnalysisRow({
    required this.imageFile,
    required this.insights,
    required this.isAnalyzing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ImageCard(file: imageFile),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InsightCard(
            insights: insights,
            isAnalyzing: isAnalyzing,
          ),
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  final _FaceInsights insights;
  final bool isAnalyzing;

  const _InsightCard({required this.insights, required this.isAnalyzing});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: isAnalyzing
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Image Analysis',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _MetricRow(label: 'Faces', value: insights.faceCount.toString()),
                _MetricRow(label: 'Age Group', value: insights.ageGroup),
                _MetricRow(label: 'Smile', value: insights.smile),
                _MetricRow(label: 'Left Eye Open', value: insights.leftEye),
                _MetricRow(label: 'Right Eye Open', value: insights.rightEye),
                const SizedBox(height: 8),
                Text(
                  insights.errorMessage ?? insights.qualityHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: insights.errorMessage == null
                        ? Colors.grey.shade700
                        : Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Note: age estimation is not available in ML Kit face detection.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetricRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
      borderRadius: BorderRadius.circular(10),
      child: file != null
          ? Image.file(
              file!,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
            )
          : Container(
              height: 220,
              color: Colors.grey.shade100,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 40,
                    color: Colors.grey.shade400,
                  ),
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
