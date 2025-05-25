// lib/ai/checkers_ai.dart

import 'dart:math';
import '../models/piece_model.dart';
import '../game_rules/game_rules.dart';

class AIMove {
  final BoardPosition from;
  final BoardPosition to;
  final double score;
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
  final GameRules rules;
  final int searchDepth;
  final int quiescenceSearchDepth; // Max depth for quiescence search
  final Random _random = Random();

  CheckersAI({
    required this.rules,
    this.searchDepth = 3, // Main search depth
    this.quiescenceSearchDepth = 2, // How many extra plies to look for captures
  });

  // --- Helper: Generate Successor States ---
  // Modified to accept 'capturesOnly' flag
  List<MapEntry<AIMove, List<List<Piece?>>>> _getSuccessorStates(
    List<List<Piece?>> board,
    PieceType playerToMove, {
    bool capturesOnly = false, // New flag
  }) {
    List<MapEntry<AIMove, List<List<Piece?>>>> successors = [];
    Map<BoardPosition, Set<BoardPosition>> moveOpportunities;

    if (capturesOnly) {
      // Get only jump moves
      moveOpportunities = rules.getAllMovesForPlayer(board, playerToMove, true); // true for jumpsOnly
    } else {
      // Get jumps if mandatory, otherwise regular moves
      moveOpportunities = rules.getAllMovesForPlayer(board, playerToMove, false);
    }

    moveOpportunities.forEach((fromPos, firstStepDestinations) {
      for (BoardPosition firstToPos in firstStepDestinations) {
        bool isFirstStepAJump = (firstToPos.row - fromPos.row).abs() == 2 ||
                                (firstToPos.col - fromPos.col).abs() == 2;
        // If capturesOnly is true, isFirstStepAJump must be true.
        // If we are in quiescence search and somehow a non-jump move was generated
        // by rules.getAllMovesForPlayer(..., true), we should skip it.
        // However, rules.getAllMovesForPlayer(..., true) should only return jumps.
        if (capturesOnly && !isFirstStepAJump) {
          continue; // Should not happen if rules.getAllMovesForPlayer is correct
        }


        List<List<Piece?>> boardAfterSequence = board.map((row) => List<Piece?>.from(row)).toList();
        BoardPosition currentPosOfPieceInAction = fromPos;
        bool currentTurnChanged = false;

        MoveResult result = rules.applyMoveAndGetResult(
          currentBoard: boardAfterSequence,
          from: currentPosOfPieceInAction,
          to: firstToPos,
          currentPlayer: playerToMove,
        );
        boardAfterSequence = result.board;
        currentPosOfPieceInAction = firstToPos;
        currentTurnChanged = result.turnChanged;

        if (isFirstStepAJump && !currentTurnChanged) {
          Piece? pieceInAction = boardAfterSequence[currentPosOfPieceInAction.row][currentPosOfPieceInAction.col];
          while (pieceInAction != null && !currentTurnChanged) {
            Set<BoardPosition> furtherJumps = rules.getFurtherJumps(currentPosOfPieceInAction, pieceInAction, boardAfterSequence);
            if (furtherJumps.isNotEmpty) {
              BoardPosition nextJumpToPos = furtherJumps.first;
              MoveResult multiJumpResult = rules.applyMoveAndGetResult(
                currentBoard: boardAfterSequence,
                from: currentPosOfPieceInAction,
                to: nextJumpToPos,
                currentPlayer: playerToMove,
              );
              boardAfterSequence = multiJumpResult.board;
              currentPosOfPieceInAction = nextJumpToPos;
              pieceInAction = boardAfterSequence[currentPosOfPieceInAction.row][currentPosOfPieceInAction.col];
              currentTurnChanged = multiJumpResult.turnChanged;
            } else {
              break;
            }
          }
        }
        successors.add(MapEntry(
            AIMove(from: fromPos, to: firstToPos, score: 0, isJump: isFirstStepAJump),
            boardAfterSequence));
      }
    });
    return successors;
  }

  // --- Quiescence Search ---
  double _quiescenceSearch(List<List<Piece?>> board, int depth, double alpha, double beta, bool isMaximizingPlayer, PieceType aiPlayerType) {
    // Evaluate the current "stand-pat" score (don't make a capture)
    double standPatScore = rules.evaluateBoardForAI(board, aiPlayerType);

    if (isMaximizingPlayer) {
      if (standPatScore >= beta) {
        return beta; // Fail-high
      }
      alpha = max(alpha, standPatScore);
    } else { // Minimizing player
      if (standPatScore <= alpha) {
        return alpha; // Fail-low
      }
      beta = min(beta, standPatScore);
    }

    if (depth == 0) { // Quiescence depth limit reached
      return standPatScore;
    }

    PieceType currentPlayerForNode = isMaximizingPlayer
        ? aiPlayerType
        : (aiPlayerType == PieceType.red ? PieceType.black : PieceType.red);

    // Generate ONLY capture moves for quiescence search
    List<MapEntry<AIMove, List<List<Piece?>>>> captureMovesAndStates =
        _getSuccessorStates(board, currentPlayerForNode, capturesOnly: true);

    if (captureMovesAndStates.isEmpty) {
      return standPatScore; // Position is quiet, no captures to explore
    }

    if (isMaximizingPlayer) {
      double maxEval = standPatScore; // Initialize with stand-pat score
      for (var entry in captureMovesAndStates) {
        double eval = _quiescenceSearch(entry.value, depth - 1, alpha, beta, false, aiPlayerType);
        maxEval = max(maxEval, eval);
        alpha = max(alpha, eval);
        if (beta <= alpha) {
          break;
        }
      }
      return maxEval;
    } else { // Minimizing player
      double minEval = standPatScore; // Initialize with stand-pat score
      for (var entry in captureMovesAndStates) {
        double eval = _quiescenceSearch(entry.value, depth - 1, alpha, beta, true, aiPlayerType);
        minEval = min(minEval, eval);
        beta = min(beta, eval);
        if (beta <= alpha) {
          break;
        }
      }
      return minEval;
    }
  }


  // --- Minimax Algorithm with Alpha-Beta Pruning ---
  double _minimax(List<List<Piece?>> board, int depth, double alpha, double beta, bool isMaximizingPlayer, PieceType aiPlayerType) {
    if (depth == 0) {
      // Call quiescence search instead of direct evaluation
      return _quiescenceSearch(board, quiescenceSearchDepth, alpha, beta, isMaximizingPlayer, aiPlayerType);
    }

    PieceType currentPlayerForNode = isMaximizingPlayer
        ? aiPlayerType
        : (aiPlayerType == PieceType.red ? PieceType.black : PieceType.red);

    // Generate all moves (jumps if mandatory, else regular)
    List<MapEntry<AIMove, List<List<Piece?>>>> childrenStatesAndMoves =
        _getSuccessorStates(board, currentPlayerForNode, capturesOnly: false);

    if (childrenStatesAndMoves.isEmpty) {
      bool isAISperspectiveNodePlayer = (currentPlayerForNode == aiPlayerType);
      if (isAISperspectiveNodePlayer) {
        return -10000.0 - depth; // AI is stuck
      } else {
        return 10000.0 + depth; // Opponent is stuck
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
    } else { // Minimizing player
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

  // --- Main AI Method: findBestMove using Minimax with Alpha-Beta ---
  AIMove? findBestMove(List<List<Piece?>> currentBoard, PieceType aiPlayerType) {
    List<AIMove> bestMovesFound = [];
    double maxScoreFound = -double.infinity;

    List<MapEntry<AIMove, List<List<Piece?>>>> possibleFirstMovesAndStates =
        _getSuccessorStates(currentBoard, aiPlayerType, capturesOnly: false);

    if (possibleFirstMovesAndStates.isEmpty) {
      return null;
    }

    for (var entry in possibleFirstMovesAndStates) {
      AIMove initialMove = entry.key;
      List<List<Piece?>> boardAfterInitialMoveSequence = entry.value;
      
      // Initial alpha for the root is -infinity, beta is +infinity
      // maxScoreFound acts as alpha for the calls from the root for the first level of moves
      double score = _minimax(boardAfterInitialMoveSequence, searchDepth - 1, maxScoreFound, double.infinity, false, aiPlayerType);
      
      AIMove currentAIMove = AIMove(
          from: initialMove.from,
          to: initialMove.to,
          score: score,
          isJump: initialMove.isJump
      );

      if (bestMovesFound.isEmpty || score > maxScoreFound) {
        maxScoreFound = score;
        bestMovesFound = [currentAIMove];
      } else if (score == maxScoreFound) {
        bestMovesFound.add(currentAIMove);
      }
    }
    
    if (bestMovesFound.isEmpty) {
      if (possibleFirstMovesAndStates.isNotEmpty) {
          AIMove firstAvailable = possibleFirstMovesAndStates.first.key;
          return AIMove(from: firstAvailable.from, to: firstAvailable.to, score: maxScoreFound, isJump: firstAvailable.isJump);
      }
      return null;
    }
    return bestMovesFound[_random.nextInt(bestMovesFound.length)];
  }
}