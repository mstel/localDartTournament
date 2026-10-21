import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme_controller.dart';

class AppBrandMark extends StatelessWidget {
  const AppBrandMark({
    super.key,
    this.size = 36,
    this.icon = Icons.sports_score,
  });

  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Uint8List?>(
    valueListenable: AppThemeController.instance.logoBytesNotifier,
    builder: (context, bytes, _) {
      if (bytes == null) {
        return Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
          size: size,
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: size,
          ),
        ),
      );
    },
  );
}
