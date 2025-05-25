import 'package:flutter/material.dart';
import '../models/piece_model.dart'; // Assuming piece_model.dart is in lib/models/

class PieceWidget extends StatelessWidget {
  final Piece piece;
  final double size;

  const PieceWidget({
    super.key,
    required this.piece,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 0.8, // Piece is slightly smaller than the square
      height: size * 0.8,
      decoration: BoxDecoration(
        color: piece.color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: piece.isKing
          ? Icon(
              Icons.star, // Simple king indicator
              color: piece.type == PieceType.red ? Colors.black : Colors.white,
              size: size * 0.4,
            )
          : null,
    );
  }
}