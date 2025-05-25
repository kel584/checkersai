// lib/widgets/square_widget.dart
import 'package:flutter/material.dart';
import '../models/piece_model.dart'; // Ensure Piece is available
import 'piece_widget.dart';          // Ensure PieceWidget is available

class SquareWidget extends StatelessWidget {
  final bool isDark;
  final Piece? piece;
  final double size;
  final bool isSelected;
  final bool isValidMove;
  final bool isSuggestedMoveFrom; // New
  final bool isSuggestedMoveTo;   // New
  final void Function()? onTap;

  const SquareWidget({
    super.key,
    required this.isDark,
    this.piece,
    required this.size,
    this.isSelected = false,
    this.isValidMove = false,
    this.isSuggestedMoveFrom = false, // New
    this.isSuggestedMoveTo = false,   // New
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color squareBaseColor = isDark ? Colors.brown[600]! : Colors.brown[300]!;
    BoxBorder? border;
    List<Widget> stackChildren = [];

    // 1. Base square color
    stackChildren.add(Container(color: squareBaseColor));

    // 2. Piece (if any)
    if (piece != null) {
      stackChildren.add(Center(
        child: PieceWidget(
          piece: piece!,
          size: size,
        ),
      ));
    }

    // 3. Player's valid move indicator (dot)
    if (isValidMove && piece == null) { // Show dot only on empty valid move squares
      stackChildren.add(Center(
        child: Container(
          width: size * 0.25,
          height: size * 0.25,
          decoration: BoxDecoration(
            color: Colors.blueAccent.withOpacity(0.7),
            shape: BoxShape.circle,
          ),
        ),
      ));
    }
    
    // 4. Border highlights (order matters if they overwrite 'border')

    // Player selection highlight
    if (isSelected) {
      border = Border.all(color: Colors.greenAccent[400]!, width: 3);
    } 
    // AI Suggested 'FROM' square highlight
    else if (isSuggestedMoveFrom) { 
      // Using 'else if' so it doesn't clash directly with 'isSelected' border
      // but AI 'from' is usually also the piece selected by AI, could be combined.
      // For now, let's make it distinct.
      border = Border.all(color: Colors.purpleAccent[400]!, width: 3.5);
      // Optional: Add an icon for AI 'from'
      stackChildren.add(
        Positioned(
          top: size * 0.05,
          left: size * 0.05,
          child: Icon(Icons.psychology_alt, color: Colors.purpleAccent[100]!.withOpacity(0.9), size: size * 0.3),
        )
      );
    }
    // AI Suggested 'TO' square highlight (can coexist with valid move dot if empty)
    else if (isSuggestedMoveTo) {
      border = Border.all(color: Colors.orangeAccent[400]!, width: 3.5);
       // Optional: Add an icon for AI 'to'
      stackChildren.add(
        Center(
          child: Icon(Icons.gps_fixed, color: Colors.orangeAccent[100]!.withOpacity(0.9), size: size * 0.5),
        )
      );
    }
    // Player's valid move border (if not selected or AI suggested)
    else if (isValidMove) {
        border = Border.all(color: Colors.blueAccent.withOpacity(0.7), width: 2.5);
    }


    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          // The base color is now the first child of the Stack
          border: border,
        ),
        child: Stack(
          alignment: Alignment.center, // Default alignment for children like PieceWidget
          children: stackChildren,
        ),
      ),
    );
  }
}