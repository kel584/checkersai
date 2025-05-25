import 'package:flutter/material.dart';
import '../models/piece_model.dart';
import 'square_widget.dart';

class BoardWidget extends StatelessWidget {
  final List<List<Piece?>> boardData;
  final double boardSize;
  final void Function(int row, int col) onSquareTap; // Callback for square taps
  final BoardPosition? selectedPiecePosition; // Position of the selected piece
  final Set<BoardPosition> validMoves; // Set of valid moves for the selected piece
  final BoardPosition? suggestedMoveFrom; // New
  final BoardPosition? suggestedMoveTo;   // New

  const BoardWidget({
    super.key,
    required this.boardData,
    required this.boardSize,
    required this.onSquareTap,
    this.selectedPiecePosition,
    required this.validMoves,
    this.suggestedMoveFrom, // New
    this.suggestedMoveTo,   // New
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
          final row = index ~/ 8;
          final col = index % 8;
          final isDark = (row + col) % 2 != 0;
          final piece = boardData[row][col];
          final position = BoardPosition(row, col);

          final bool isSelectedSquare = selectedPiecePosition == position;
          final bool isValidMoveSquare = validMoves.contains(position);
          final bool isAISuggestedFrom = suggestedMoveFrom == position; // New
          final bool isAISuggestedTo = suggestedMoveTo == position;

          return SquareWidget(
            isDark: isDark,
            piece: piece,
            size: squareSize,
            isSelected: isSelectedSquare,
            isValidMove: isValidMoveSquare,
            isSuggestedMoveFrom: isAISuggestedFrom, // Pass to SquareWidget
            isSuggestedMoveTo: isAISuggestedTo,     // Pass to SquareWidget
            onTap: () => onSquareTap(row, col),
          );
        },
        itemCount: 64,
        physics: const NeverScrollableScrollPhysics(),
      ),
    );
  }
}