import 'package:flutter/material.dart';

Color parseAccentColor(String? accent, {Color fallback = const Color(0xFF6B8AFD)}) {
  if (accent == null || accent.trim().isEmpty) return fallback;
  final str = accent.trim();

  // Hex: #RRGGBB or #AARRGGBB
  if (str.startsWith('#')) {
    final hex = str.replaceAll('#', '');
    if (hex.length == 6) {
      final val = int.tryParse('FF$hex', radix: 16);
      if (val != null) return Color(val);
    } else if (hex.length == 8) {
      final val = int.tryParse(hex, radix: 16);
      if (val != null) return Color(val);
    }
  }

  // "r g b" format (e.g. "107 138 253")
  final parts = str.split(RegExp(r'\s+'));
  if (parts.length >= 3) {
    final r = int.tryParse(parts[0]);
    final g = int.tryParse(parts[1]);
    final b = int.tryParse(parts[2]);
    if (r != null && g != null && b != null) {
      return Color.fromARGB(255, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
    }
  }

  return fallback;
}

String formatDuration(double seconds) {
  if (seconds.isNaN || seconds.isInfinite || seconds <= 0) return '0:00';
  final s = seconds.toInt();
  final m = s ~/ 60;
  final rem = s % 60;
  return '$m:${rem < 10 ? '0' : ''}$rem';
}
