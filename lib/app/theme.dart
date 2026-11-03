import 'package:flutter/material.dart';

// Flaxxa Pulse brand orange (from the Pulse flame mark in the logo).
const Color _seed = Color(0xFFF26522);

ThemeData pulseTheme(Brightness brightness) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
  );
}
