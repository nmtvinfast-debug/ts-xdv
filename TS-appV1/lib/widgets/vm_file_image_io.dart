import 'dart:io';

import 'package:flutter/material.dart';

Widget buildVmFileImage(String path, {BoxFit fit = BoxFit.cover}) {
  return Image.file(File(path), fit: fit, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey));
}
