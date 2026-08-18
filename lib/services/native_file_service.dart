import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

class NativeFileService {
  static final ImagePicker _imagePicker = ImagePicker();

  /// Captures an image from the camera and returns base64 payload
  static Future<Map<String, dynamic>?> pickFromCamera() async {
    final XFile? photo = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (photo == null) return null;

    final bytes = await File(photo.path).readAsBytes();
    return {
      'name': photo.name,
      'mimeType': photo.mimeType ?? 'image/jpeg',
      'base64': base64Encode(bytes),
      'size': bytes.length,
    };
  }

  /// Picks design images or documents (PDF, DOCX, Images)
  static Future<Map<String, dynamic>?> pickDesignOrDocument() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'docx'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;

    return {
      'name': file.name,
      'extension': file.extension,
      'base64': file.bytes != null ? base64Encode(file.bytes!) : null,
      'size': file.size,
    };
  }
}