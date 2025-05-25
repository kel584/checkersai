// lib/widgets/board_widget.dart
import '../models/piece_model.dart';
import 'package:flutter/material.dart';
import 'square_widget.dart';

class BoardWidget extends StatelessWidget {
  final List<List<Piece?>> boardData;
  final double boardSize;
  final void Function(int row, int col) onSquareTap;
  final BoardPosition? selectedPiecePosition;
  final Set<BoardPosition> validMoves;
  final BoardPosition? suggestedMoveFrom;
  final BoardPosition? suggestedMoveTo;
  final bool isBoardFlipped; // <-- NEW: Property to indicate if board is flipped

  const BoardWidget({
    super.key,
    required this.boardData,
    required this.boardSize,
    required this.onSquareTap,
    this.selectedPiecePosition,
    required this.validMoves,
    this.suggestedMoveFrom,
    this.suggestedMoveTo,
    this.isBoardFlipped = false, // Default to not flipped
  });

  @override
  Widget build(BuildContext context) {
    final double squareSize = boardSize / 8.0;

    return Container(
      width: boardSize,
      height: boardSize,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
        ),
        itemBuilder: (context, index) {
          // Determine the logical row and column based on the index and flip state
          int visualRow = index ~/ 8;
          int visualCol = index % 8;
          
          int logicalRow;
          int logicalCol;

          if (isBoardFlipped) {
            logicalRow = 7 - visualRow;
            logicalCol = 7 - visualCol;
          } else {
            logicalRow = visualRow;
            logicalCol = visualCol;
          }

          // Use logicalRow and logicalCol to access boardData and for interactions
          final piece = (_isValidPosition(logicalRow, logicalCol)) 
                        ? boardData[logicalRow][logicalCol] 
                        : null; // Safety check, though index should be within 0-63
          
          final currentLogicalPosition = BoardPosition(logicalRow, logicalCol);

          final bool isDarkSquare = (visualRow + visualCol) % 2 != 0; // Visual darkness based on visual grid
          // Or, if you want square colors to flip too (e.g. A1 is always dark):
          // final bool isDarkSquare = (logicalRow + logicalCol) % 2 != 0; 


          final bool isSelectedSquare = selectedPiecePosition == currentLogicalPosition;
          final bool isValidMoveSquare = validMoves.contains(currentLogicalPosition);
          final bool isAISuggestedFrom = suggestedMoveFrom == currentLogicalPosition;
          final bool isAISuggestedTo = suggestedMoveTo == currentLogicalPosition;

          return SquareWidget(
            isDark: isDarkSquare, // Visual property
            piece: piece,
            size: squareSize,
            isSelected: isSelectedSquare,
            isValidMove: isValidMoveSquare,
            isSuggestedMoveFrom: isAISuggestedFrom,
            isSuggestedMoveTo: isAISuggestedTo,
            onTap: () => onSquareTap(logicalRow, logicalCol), // Pass LOGICAL coordinates
          );
        },
        itemCount: 64,
        physics: const NeverScrollableScrollPhysics(),
      ),
    );
  }

  // Helper for bounds checking if needed, though logicalRow/Col from index should be fine
  bool _isValidPosition(int r, int c) {
    return r >= 0 && r < 8 && c >= 0 && c < 8;
  }
}