// lib/ai/checkers_ai.dart

import 'dart:math';
import '../models/piece_model.dart'; // Your piece and board position models

// Helper class to represent a potential move for the AI
class AIMove {
  final BoardPosition from;
  final BoardPosition to; // For jumps, this is the first landing spot
  final double score;    // Score of the board state AFTER this move sequence (Minimax score)
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
  final int searchDepth;

  CheckersAI({this.searchDepth = 9}); // Default depth

  // --- Piece-Square Tables (PSTs) ---
  // Values are from the perspective of the piece type.
  // For BLACK (usually starts at top, row 0, moves towards row 7 to king)
  // For RED (usually starts at bottom, row 7, moves towards row 0 to king)
  // We'll define one set and flip row access for the other color.

  static const List<List<double>> _manPst = [
    // For a piece moving from row 0 towards row 7
    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], // Should not be here unless just moved back (king)
    [0.5, 0.6, 0.7, 0.7, 0.7, 0.7, 0.6, 0.5], // Advancing
    [0.4, 0.5, 0.6, 0.6, 0.6, 0.6, 0.5, 0.4],
    [0.3, 0.4, 0.5, 0.5, 0.5, 0.5, 0.4, 0.3], // Center-ish
    [0.2, 0.3, 0.4, 0.4, 0.4, 0.4, 0.3, 0.2],
    [0.1, 0.2, 0.3, 0.3, 0.3, 0.3, 0.2, 0.1],
    [0.05, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.05], // Near own back rank
    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], // Own back rank (men start here or near here)
  ];

  static const List<List<double>> _kingPst = [
    [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
    [0.5, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.5],
    [0.5, 0.6, 0.7, 0.7, 0.7, 0.7, 0.6, 0.5], // Good central rows
    [0.5, 0.6, 0.7, 0.8, 0.8, 0.7, 0.6, 0.5], // Strong center
    [0.5, 0.6, 0.7, 0.8, 0.8, 0.7, 0.6, 0.5], // Strong center
    [0.5, 0.6, 0.7, 0.7, 0.7, 0.7, 0.6, 0.5],
    [0.5, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.5],
    [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5], // Kings are generally good anywhere not trapped
  ];


  // --- Evaluation Function ---
  double _evaluateBoard(List<List<Piece?>> board, PieceType aiPlayerType) {
    double score = 0;
    PieceType opponentPlayerType =
        (aiPlayerType == PieceType.red) ? PieceType.black : PieceType.red;

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null) {
          double pieceValue = piece.isKing ? 3.0 : 1.0; // Material value
          double positionalValue = 0;

          if (piece.isKing) {
            // King PST is symmetrical, direct access
            positionalValue = _kingPst[r][c];
          } else {
            // Man PST: needs row flipping based on color
            if (piece.type == PieceType.black) { // Black moves from 0 towards 7
              positionalValue = _manPst[r][c];
            } else { // Red moves from 7 towards 0
              positionalValue = _manPst[7 - r][c]; // Flip row index for Red
            }
          }

          if (piece.type == aiPlayerType) {
            score += pieceValue + positionalValue;
          } else if (piece.type == opponentPlayerType) {
            score -= (pieceValue + positionalValue);
          }
        }
      }
    }
    return score;
  }

  bool _isValidPosition(int r, int c) {
    return r >= 0 && r < 8 && c >= 0 && c < 8;
  }

  Set<BoardPosition> _getJumpsForPieceAI(
      BoardPosition pos, Piece piece, List<List<Piece?>> board) {
    Set<BoardPosition> jumps = {};
    int r = pos.row;
    int c = pos.col;

    List<BoardPosition> directionsDeltas = [];
    if (piece.isKing) {
      directionsDeltas = [
        BoardPosition(-1, -1), BoardPosition(-1, 1),
        BoardPosition(1, -1), BoardPosition(1, 1),
      ];
    } else {
      directionsDeltas = [
        BoardPosition(piece.moveDirection, -1),
        BoardPosition(piece.moveDirection, 1),
      ];
    }

    for (var dirDelta in directionsDeltas) {
      int jumpOverRow = r + dirDelta.row;
      int jumpOverCol = c + dirDelta.col;
      int landRow = r + dirDelta.row * 2;
      int landCol = c + dirDelta.col * 2;

      if (_isValidPosition(landRow, landCol) && board[landRow][landCol] == null) {
        if (_isValidPosition(jumpOverRow, jumpOverCol)) {
          Piece? jumpedPiece = board[jumpOverRow][jumpOverCol];
          if (jumpedPiece != null && jumpedPiece.type != piece.type) {
            jumps.add(BoardPosition(landRow, landCol));
          }
        }
      }
    }
    return jumps;
  }

  Set<BoardPosition> _getRegularMovesForPieceAI(
      BoardPosition pos, Piece piece, List<List<Piece?>> board) {
    Set<BoardPosition> moves = {};
    int r = pos.row;
    int c = pos.col;

    List<BoardPosition> directionsDeltas = [];
    if (piece.isKing) {
      directionsDeltas = [
        BoardPosition(-1, -1), BoardPosition(-1, 1),
        BoardPosition(1, -1), BoardPosition(1, 1),
      ];
    } else {
      directionsDeltas = [
        BoardPosition(piece.moveDirection, -1),
        BoardPosition(piece.moveDirection, 1),
      ];
    }

    for (var moveDirDelta in directionsDeltas) {
      int nextRow = r + moveDirDelta.row;
      int nextCol = c + moveDirDelta.col;
      if (_isValidPosition(nextRow, nextCol) && board[nextRow][nextCol] == null) {
        moves.add(BoardPosition(nextRow, nextCol));
      }
    }
    return moves;
  }

  List<MapEntry<AIMove, List<List<Piece?>>>> _getSuccessorStates(
      List<List<Piece?>> board, PieceType playerToMove) {
    List<MapEntry<AIMove, List<List<Piece?>>>> successors = [];
    Map<BoardPosition, Set<BoardPosition>> allPotentialJumps = {};

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null && piece.type == playerToMove) {
          final piecePos = BoardPosition(r, c);
          final jumps = _getJumpsForPieceAI(piecePos, piece, board);
          if (jumps.isNotEmpty) {
            allPotentialJumps[piecePos] = jumps;
          }
        }
      }
    }

    bool jumpsAreMandatory = allPotentialJumps.isNotEmpty;

    if (jumpsAreMandatory) {
      allPotentialJumps.forEach((fromPos, firstJumpDestinations) {
        Piece originalPiece = board[fromPos.row][fromPos.col]!;
        for (BoardPosition firstJumpToPos in firstJumpDestinations) {
          List<List<Piece?>> currentSimBoard = board.map((row) => List<Piece?>.from(row)).toList();
          Piece pieceInAction = Piece(type: originalPiece.type, isKing: originalPiece.isKing);
          BoardPosition currentSimPos = fromPos;

          currentSimBoard[firstJumpToPos.row][firstJumpToPos.col] = pieceInAction;
          currentSimBoard[currentSimPos.row][currentSimPos.col] = null;
          int capturedR = currentSimPos.row + (firstJumpToPos.row - currentSimPos.row) ~/ 2;
          int capturedC = currentSimPos.col + (firstJumpToPos.col - currentSimPos.col) ~/ 2;
          currentSimBoard[capturedR][capturedC] = null;
          if (!pieceInAction.isKing && ((pieceInAction.type == PieceType.red && firstJumpToPos.row == 0) || (pieceInAction.type == PieceType.black && firstJumpToPos.row == 7))) {
            pieceInAction.isKing = true;
          }
          currentSimPos = firstJumpToPos;

          Set<BoardPosition> nextJumps;
          do {
            nextJumps = _getJumpsForPieceAI(currentSimPos, pieceInAction, currentSimBoard);
            if (nextJumps.isNotEmpty) {
              BoardPosition nextJumpToPos = nextJumps.first;
              currentSimBoard[nextJumpToPos.row][nextJumpToPos.col] = pieceInAction;
              currentSimBoard[currentSimPos.row][currentSimPos.col] = null;
              capturedR = currentSimPos.row + (nextJumpToPos.row - currentSimPos.row) ~/ 2;
              capturedC = currentSimPos.col + (nextJumpToPos.col - currentSimPos.col) ~/ 2;
              currentSimBoard[capturedR][capturedC] = null;
              if (!pieceInAction.isKing && ((pieceInAction.type == PieceType.red && nextJumpToPos.row == 0) || (pieceInAction.type == PieceType.black && nextJumpToPos.row == 7))) {
                pieceInAction.isKing = true;
              }
              currentSimPos = nextJumpToPos;
            }
          } while (nextJumps.isNotEmpty);
          
          successors.add(MapEntry(AIMove(from: fromPos, to: firstJumpToPos, score: 0, isJump: true), currentSimBoard));
        }
      });
    } else { // No jumps, generate regular moves
      for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++) {
          final piece = board[r][c];
          if (piece != null && piece.type == playerToMove) {
            final piecePos = BoardPosition(r, c);
            final regularMoves = _getRegularMovesForPieceAI(piecePos, piece, board);
            for (BoardPosition toPos in regularMoves) {
              List<List<Piece?>> boardCopy = board.map((row) => List<Piece?>.from(row)).toList();
              Piece movedPiece = Piece(type: piece.type, isKing: piece.isKing);
              boardCopy[toPos.row][toPos.col] = movedPiece;
              boardCopy[piecePos.row][piecePos.col] = null;
              if (!movedPiece.isKing && ((movedPiece.type == PieceType.red && toPos.row == 0) || (movedPiece.type == PieceType.black && toPos.row == 7))) {
                movedPiece.isKing = true;
              }
              successors.add(MapEntry(AIMove(from: piecePos, to: toPos, score: 0, isJump: false), boardCopy));
            }
          }
        }
      }
    }
    return successors;
  }

  double _minimax(List<List<Piece?>> board, int depth, double alpha, double beta, bool isMaximizingPlayer, PieceType aiPlayerType) {
    if (depth == 0) {
      return _evaluateBoard(board, aiPlayerType);
    }

    PieceType currentPlayerForNode = isMaximizingPlayer
        ? aiPlayerType
        : (aiPlayerType == PieceType.red ? PieceType.black : PieceType.red);

    List<MapEntry<AIMove, List<List<Piece?>>>> childrenStatesAndMoves =
        _getSuccessorStates(board, currentPlayerForNode);

    if (childrenStatesAndMoves.isEmpty) {
      bool isAISperspectiveNodePlayer = (currentPlayerForNode == aiPlayerType);
      if (isAISperspectiveNodePlayer) {
        return -10000.0 - depth; 
      } else {
        return 10000.0 + depth; 
      }
    }

    if (isMaximizingPlayer) {
      double maxEval = -double.infinity;
      for (var entry in childrenStatesAndMoves) {
        double eval = _minimax(entry.value, depth - 1, alpha, beta, false, aiPlayerType);
        maxEval = max(maxEval, eval);
        alpha = max(alpha, eval);
        if (beta <= alpha) {
          break; 
        }
      }
      return maxEval;
    } else { 
      double minEval = double.infinity;
      for (var entry in childrenStatesAndMoves) {
        double eval = _minimax(entry.value, depth - 1, alpha, beta, true, aiPlayerType);
        minEval = min(minEval, eval);
        beta = min(beta, eval);
        if (beta <= alpha) {
          break; 
        }
      }
      return minEval;
    }
  }

  AIMove? findBestMove(List<List<Piece?>> currentBoard, PieceType aiPlayerType) {
    AIMove? bestMoveFound;
    double maxScoreFound = -double.infinity;

    List<MapEntry<AIMove, List<List<Piece?>>>> possibleFirstMovesAndStates =
        _getSuccessorStates(currentBoard, aiPlayerType);

    if (possibleFirstMovesAndStates.isEmpty) {
      return null;
    }

    for (var entry in possibleFirstMovesAndStates) {
      AIMove initialMove = entry.key;
      List<List<Piece?>> boardAfterInitialMoveSequence = entry.value;
      double score = _minimax(boardAfterInitialMoveSequence, searchDepth - 1, maxScoreFound, double.infinity, false, aiPlayerType);
      
      if (bestMoveFound == null || score > maxScoreFound) {
        maxScoreFound = score;
        bestMoveFound = AIMove(
            from: initialMove.from,
            to: initialMove.to,
            score: score,
            isJump: initialMove.isJump);
      }
    }
    
    if (bestMoveFound == null && possibleFirstMovesAndStates.isNotEmpty) {
        AIMove firstAvailable = possibleFirstMovesAndStates.first.key;
        bestMoveFound = AIMove(from: firstAvailable.from, to: firstAvailable.to, score: maxScoreFound, isJump: firstAvailable.isJump);
    }
    return bestMoveFound;
  }
}