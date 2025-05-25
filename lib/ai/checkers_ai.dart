// lib/ai/checkers_ai.dart

import '../models/piece_model.dart'; // Assuming your models are here

// Helper class to represent a potential move for the AI
class AIMove {
  final BoardPosition from;
  final BoardPosition to;
  final double score; // Score of the board state AFTER this move
  final bool isJump;

  AIMove({
    required this.from,
    required this.to,
    required this.score,
    this.isJump = false,
  });

  @override
  String toString() {
    return 'AIMove(from: $from, to: $to, score: $score, isJump: $isJump)';
  }
}

class CheckersAI {
  // --- Evaluation Function ---
  // Scores the given board state from the perspective of the aiPlayer
  double _evaluateBoard(List<List<Piece?>> board, PieceType aiPlayerType) {
    double score = 0;
    PieceType opponentPlayerType = (aiPlayerType == PieceType.red) ? PieceType.black : PieceType.red;

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null) {
          if (piece.type == aiPlayerType) {
            score += piece.isKing ? 3.0 : 1.0; // AI's pieces
            // Add positional scores later (e.g., center control, king row proximity)
          } else if (piece.type == opponentPlayerType) {
            score -= piece.isKing ? 3.0 : 1.0; // Opponent's pieces
          }
        }
      }
    }
    return score;
  }

  // --- Move Generation (Can reuse or adapt from GameScreen) ---
  // These would be static or utility functions, or part of this class,
  // needing access to _isValidPosition and board data.
  // For simplicity, let's assume we'll pass necessary helpers or board.

  bool _isValidPosition(int r, int c) {
    return r >= 0 && r < 8 && c >= 0 && c < 8;
  }

  // Simplified version of _getJumpMovesForPiece for AI context
  Set<BoardPosition> _getJumpsForPieceAI(BoardPosition pos, Piece piece, List<List<Piece?>> board) {
    Set<BoardPosition> jumps = {};
    int r = pos.row;
    int c = pos.col;
    // (Logic similar to _getJumpMovesForPiece in GameScreen, using the passed 'board')
    // Example for non-king (needs to be completed for kings too):
    List<BoardPosition> directionsToCheck = [];
    if (piece.isKing) {
      directionsToCheck = [
        BoardPosition(-2, -2), BoardPosition(-2, 2),
        BoardPosition(2, -2), BoardPosition(2, 2),
      ];
    } else {
      directionsToCheck = [
        BoardPosition(piece.moveDirection * 2, -2),
        BoardPosition(piece.moveDirection * 2, 2),
      ];
    }

    for (var jumpDir in directionsToCheck) {
      int landRow = r + jumpDir.row;
      int landCol = c + jumpDir.col;
      int jumpOverRow = r + jumpDir.row ~/ 2;
      int jumpOverCol = c + jumpDir.col ~/ 2;

      if (_isValidPosition(landRow, landCol) && board[landRow][landCol] == null) {
        if (_isValidPosition(jumpOverRow, jumpOverCol)) { // Check bounds for jumped piece
            Piece? jumpedPiece = board[jumpOverRow][jumpOverCol];
            if (jumpedPiece != null && jumpedPiece.type != piece.type) {
                jumps.add(BoardPosition(landRow, landCol));
            }
        }
      }
    }
    return jumps;
  }

  // Simplified version of _getRegularMovesForPiece for AI context
  Set<BoardPosition> _getRegularMovesForPieceAI(BoardPosition pos, Piece piece, List<List<Piece?>> board) {
    Set<BoardPosition> moves = {};
    int r = pos.row;
    int c = pos.col;
    // (Logic similar to _getRegularMovesForPiece in GameScreen, using the passed 'board')
    // Example for non-king (needs to be completed for kings too):
    List<BoardPosition> directionsToCheck = [];
    if (piece.isKing) {
        directionsToCheck = [
            BoardPosition(-1, -1), BoardPosition(-1, 1),
            BoardPosition(1, -1), BoardPosition(1, 1),
        ];
    } else {
        directionsToCheck = [
            BoardPosition(piece.moveDirection, -1),
            BoardPosition(piece.moveDirection, 1),
        ];
    }
    for (var moveDir in directionsToCheck) {
        int nextRow = r + moveDir.row;
        int nextCol = c + moveDir.col;
        if (_isValidPosition(nextRow, nextCol) && board[nextRow][nextCol] == null) {
            moves.add(BoardPosition(nextRow, nextCol));
        }
    }
    return moves;
  }


  // --- Main AI Method ---
  AIMove? findBestMove(List<List<Piece?>> currentBoard, PieceType aiPlayerType) {
    List<AIMove> possibleMoves = [];
    Map<BoardPosition, Set<BoardPosition>> allAIMovesMap = {}; // To hold all moves from all pieces

    // 1. Generate all possible jumps for the AI player first
    Map<BoardPosition, Set<BoardPosition>> allAIJumps = {};
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = currentBoard[r][c];
        if (piece != null && piece.type == aiPlayerType) {
          final piecePos = BoardPosition(r, c);
          final jumps = _getJumpsForPieceAI(piecePos, piece, currentBoard);
          if (jumps.isNotEmpty) {
            allAIJumps[piecePos] = jumps;
          }
        }
      }
    }

    bool jumpsAreMandatory = allAIJumps.isNotEmpty;

    if (jumpsAreMandatory) {
      allAIMovesMap = allAIJumps; // Only consider jumps
    } else {
      // No jumps, generate regular moves
      for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++) {
          final piece = currentBoard[r][c];
          if (piece != null && piece.type == aiPlayerType) {
            final piecePos = BoardPosition(r, c);
            final regularMoves = _getRegularMovesForPieceAI(piecePos, piece, currentBoard);
            if (regularMoves.isNotEmpty) {
              allAIMovesMap[piecePos] = regularMoves;
            }
          }
        }
      }
    }

    // 2. For each possible move, simulate it and evaluate the resulting board
    allAIMovesMap.forEach((fromPos, toPositions) {
      Piece pieceToMoveInitially = currentBoard[fromPos.row][fromPos.col]!; // We know piece exists
      
      toPositions.forEach((toPos) {
        // Create a deep copy of the board for simulation
        List<List<Piece?>> boardCopy = currentBoard.map((row) => List<Piece?>.from(row)).toList();
        
        // Simulate the move (simplified: does not handle multi-jumps for evaluation here)
        Piece pieceToMove = Piece(type: pieceToMoveInitially.type, isKing: pieceToMoveInitially.isKing); //
        boardCopy[toPos.row][toPos.col] = pieceToMove;
        boardCopy[fromPos.row][fromPos.col] = null;
        
        bool wasJump = (toPos.row - fromPos.row).abs() == 2;
        if (wasJump) {
          int capturedRow = fromPos.row + (toPos.row - fromPos.row) ~/ 2;
          int capturedCol = fromPos.col + (toPos.col - fromPos.col) ~/ 2;
          boardCopy[capturedRow][capturedCol] = null; // Remove captured piece
          // Check for kinging after jump
          if (!pieceToMove.isKing && 
              ((pieceToMove.type == PieceType.red && toPos.row == 0) || 
               (pieceToMove.type == PieceType.black && toPos.row == 7))) {
            pieceToMove.isKing = true; // King the piece on the copied board
          }
        } else {
          // Check for kinging after regular move
           if (!pieceToMove.isKing && 
              ((pieceToMove.type == PieceType.red && toPos.row == 0) || 
               (pieceToMove.type == PieceType.black && toPos.row == 7))) {
            pieceToMove.isKing = true;
          }
        }
        // TODO: For a stronger greedy AI, if 'wasJump', it should check for multi-jumps
        // and simulate the entire sequence, then evaluate. For now, this is simpler.

        double score = _evaluateBoard(boardCopy, aiPlayerType);
        possibleMoves.add(AIMove(from: fromPos, to: toPos, score: score, isJump: wasJump));
      });
    });

    if (possibleMoves.isEmpty) {
      return null; // No moves available
    }

    // 3. Choose the move with the best score for the AI
    // If jumps were mandatory, we only have jump moves in possibleMoves (due to how allAIMovesMap was populated)
    // Or if not, we have regular moves.
    // If both jump and regular moves were considered (not ideal for simple greedy, better to separate),
    // then prioritize jumps. Our current logic correctly separates this.

    possibleMoves.sort((a, b) {
      // Prioritize jumps, then by score.
      // If AI is maximizing, higher score is better.
      if (a.isJump && !b.isJump) return -1; // a (jump) comes before b (non-jump)
      if (!a.isJump && b.isJump) return 1;  // b (jump) comes before a (non-jump)
      return b.score.compareTo(a.score); // Higher score first
    });
    
    // print("[AI] Best moves considered: ${possibleMoves.map((m) => m.toString()).toList()}");
    return possibleMoves.first;
  }
}