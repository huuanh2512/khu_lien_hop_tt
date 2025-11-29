import 'package:flutter/material.dart';

IconData sportIcon(String? code) {
  switch ((code ?? '').toUpperCase()) {
    case 'SOCCER':
    case 'FOOTBALL':
      return Icons.sports_soccer;
    case 'TENNIS':
      return Icons.sports_tennis;
    case 'BADMINTON':
      return Icons.sports_tennis; // gần đúng
    case 'VOLLEYBALL':
      return Icons.sports_volleyball;
    case 'PICKLEBALL':
      return Icons.sports_tennis;
    case 'BASKETBALL':
      return Icons.sports_basketball;
    default:
      return Icons.sports;
  }
}
