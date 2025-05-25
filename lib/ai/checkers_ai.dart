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
  final int searchDepth; // How many plies (half-moves) AI looks ahead

  CheckersAI({this.searchDepth = 3}); // Default depth

  // --- Evaluation Function ---
  // Scores the given board state from the perspective of the aiPlayer
  double _evaluateBoard(List<List<Piece?>> board, PieceType aiPlayerType) {
    double score = 0;
    PieceType opponentPlayerType =
        (aiPlayerType == PieceType.red) ? PieceType.black : PieceType.red;

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null) {
          double pieceValue = piece.isKing ? 3.0 : 1.0;
          // Basic positional heuristic: add small value for advancing
          if (piece.type == aiPlayerType) {
            score += pieceValue;
            if (!piece.isKing) { // Encourage advancing non-kings
              if (aiPlayerType == PieceType.red) score += (7-r) * 0.05; // Red moves from row 7 to 0
              else score += r * 0.05; // Black moves from row 0 to 7
            } else { // Kings are valuable, slightly more so if central or defensive
                if (r > 1 && r < 6) score += 0.1; // Slight preference for central kings
            }
          } else if (piece.type == opponentPlayerType) {
            score -= pieceValue;
            if (!piece.isKing) {
              if (opponentPlayerType == PieceType.red) score -= (7-r) * 0.05;
              else score -= r * 0.05;
            } else {
                 if (r > 1 && r < 6) score -= 0.1;
            }
          }
        }
      }
    }
    return score;
  }

  bool _isValidPosition(int r, int c) {
    return r >= 0 && r < 8 && c >= 0 && c < 8;
  }

  // --- Move Generation Helpers (adapted for AI context) ---
  Set<BoardPosition> _getJumpsForPieceAI(
      BoardPosition pos, Piece piece, List<List<Piece?>> board) {
    Set<BoardPosition> jumps = {};
    int r = pos.row;
    int c = pos.col;

    List<BoardPosition> directionsDeltas = []; // Stores (deltaRow, deltaCol) for one step of jump
    if (piece.isKing) {
      directionsDeltas = [
        BoardPosition(-1, -1), BoardPosition(-1, 1), // Jump over up-left/right
        BoardPosition(1, -1), BoardPosition(1, 1),   // Jump over down-left/right
      ];
    } else {
      directionsDeltas = [
        BoardPosition(piece.moveDirection, -1), // Jump over forward-left
        BoardPosition(piece.moveDirection, 1),  // Jump over forward-right
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

  // --- Helper: Generate Successor States after a full atomic move (including multi-jumps) ---
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
          // Start simulation for this jump sequence
          List<List<Piece?>> currentSimBoard = board.map((row) => List<Piece?>.from(row)).toList();
          Piece pieceInAction = Piece(type: originalPiece.type, isKing: originalPiece.isKing); // Piece being moved in sim

          BoardPosition currentSimPos = fromPos;

          // Simulate first jump
          currentSimBoard[firstJumpToPos.row][firstJumpToPos.col] = pieceInAction;
          currentSimBoard[currentSimPos.row][currentSimPos.col] = null;
          int capturedR = currentSimPos.row + (firstJumpToPos.row - currentSimPos.row) ~/ 2;
          int capturedC = currentSimPos.col + (firstJumpToPos.col - currentSimPos.col) ~/ 2;
          currentSimBoard[capturedR][capturedC] = null;
          if (!pieceInAction.isKing && ((pieceInAction.type == PieceType.red && firstJumpToPos.row == 0) || (pieceInAction.type == PieceType.black && firstJumpToPos.row == 7))) {
            pieceInAction.isKing = true;
          }
          currentSimPos = firstJumpToPos; // Update current position of the piece in action

          // Simulate multi-jumps
          Set<BoardPosition> nextJumps;
          do {
            nextJumps = _getJumpsForPieceAI(currentSimPos, pieceInAction, currentSimBoard);
            if (nextJumps.isNotEmpty) {
              BoardPosition nextJumpToPos = nextJumps.first; // Simple: take the first available multi-jump path
              
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
    } else {
      // No jumps, generate regular moves
      for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++) {
          final piece = board[r][c];
          if (piece != null && piece.type == playerToMove) {
            final piecePos = BoardPosition(r, c);
            final regularMoves = _getRegularMovesForPieceAI(piecePos, piece, board);
            for (BoardPosition toPos in regularMoves) {
              List<List<Piece?>> boardCopy = board.map((row) => List<Piece?>.from(row)).toList();
              Piece movedPiece = Piece(type: piece.type, isKing: piece.isKing); // Create new instance for the copy
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

  // --- Minimax Algorithm ---
  double _minimax(List<List<Piece?>> board, int depth, bool isMaximizingPlayer, PieceType aiPlayerType) {
    if (depth == 0) {
      return _evaluateBoard(board, aiPlayerType);
    }

    PieceType currentPlayerForNode = isMaximizingPlayer
        ? aiPlayerType
        : (aiPlayerType == PieceType.red ? PieceType.black : PieceType.red);

    List<MapEntry<AIMove, List<List<Piece?>>>> childrenStatesAndMoves =
        _getSuccessorStates(board, currentPlayerForNode);

    if (childrenStatesAndMoves.isEmpty) {
      // No legal moves for the current player at this node = loss for them.
      // Score from AI's perspective:
      bool isAISperspectiveNodePlayer = (currentPlayerForNode == aiPlayerType);
      if (isAISperspectiveNodePlayer) { // AI's turn, but AI is stuck
        return -10000.0 - depth; // Heavy penalty for AI being stuck
      } else { // Opponent's turn, but opponent is stuck
        return 10000.0 + depth; // Big bonus for AI as opponent is stuck
      }
    }

    if (isMaximizingPlayer) { // AI's turn
      double maxEval = -double.infinity;
      for (var entry in childrenStatesAndMoves) {
        double eval = _minimax(entry.value, depth - 1, false, aiPlayerType);
        maxEval = max(maxEval, eval);
      }
      return maxEval;
    } else { // Opponent's turn
      double minEval = double.infinity;
      for (var entry in childrenStatesAndMoves) {
        double eval = _minimax(entry.value, depth - 1, true, aiPlayerType);
        minEval = min(minEval, eval);
      }
      return minEval;
    }
  }

  // --- Main AI Method: findBestMove using Minimax ---
  AIMove? findBestMove(List<List<Piece?>> currentBoard, PieceType aiPlayerType) {
    AIMove? bestMoveFound;
    double maxScoreFound = -double.infinity;

    List<MapEntry<AIMove, List<List<Piece?>>>> possibleFirstMovesAndStates =
        _getSuccessorStates(currentBoard, aiPlayerType);

    if (possibleFirstMovesAndStates.isEmpty) {
      // print("[AI findBestMove] No moves available for AI player $aiPlayerType.");
      return null;
    }

    // print("[AI findBestMove] AI ($aiPlayerType) considering ${possibleFirstMovesAndStates.length} initial moves/sequences. Depth: $searchDepth");

    for (var entry in possibleFirstMovesAndStates) {
      AIMove initialMove = entry.key; // Contains 'from' and the first 'to' of a sequence
      List<List<Piece?>> boardAfterInitialMoveSequence = entry.value;

      // Score this move by looking at the opponent's best response
      double score = _minimax(boardAfterInitialMoveSequence, searchDepth - 1, false, aiPlayerType); // false: opponent's turn

      // print("[AI findBestMove] Candidate Move: ${initialMove.from} to ${initialMove.to} (Jump: ${initialMove.isJump}), Evaluated Minimax Score: $score");
      
      if (bestMoveFound == null || score > maxScoreFound) {
        maxScoreFound = score;
        bestMoveFound = AIMove(
            from: initialMove.from,
            to: initialMove.to, // This is the first 'to' in the sequence
            score: score,       // This is the minimax score
            isJump: initialMove.isJump);
      }
    }
    
    // print("[AI findBestMove] CHOSEN Best Move for $aiPlayerType: $bestMoveFound");
    return bestMoveFound;
  }
}