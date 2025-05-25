import 'package:flutter/material.dart';

enum PieceType {
  red,
  black,
}

class Piece {
  final PieceType type;
  bool isKing;

  Piece({required this.type, this.isKing = false});

  Color get color {
    return type == PieceType.red ? Colors.red[700]! : Colors.black87;
  }

  // Helper to determine movement direction (1 for red (down), -1 for black (up))
  int get moveDirection {
    // Red pieces (bottom, rows 5,6,7) move to lower row indices (forward is -1)
    // Black pieces (top, rows 0,1,2) move to higher row indices (forward is +1)
    return type == PieceType.red ? -1 : 1;
  }
}

// New class for representing board positions
@immutable // Good practice for value-like objects
class BoardPosition {
  final int row;
  final int col;

  const BoardPosition(this.row, this.col);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoardPosition &&
          runtimeType == other.runtimeType &&
          row == other.row &&
          col == other.col;

  @override
  int get hashCode => row.hashCode ^ col.hashCode;

  @override
  String toString() => 'BoardPosition(row: $row, col: $col)';
}