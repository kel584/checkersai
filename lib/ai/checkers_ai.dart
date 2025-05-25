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
  final Random _random = Random(); // Add a Random instance

  CheckersAI({required this.rules, this.searchDepth = 3});

  List<MapEntry<AIMove, List<List<Piece?>>>> _getSuccessorStates(
      List<List<Piece?>> board, PieceType playerToMove) {
    List<MapEntry<AIMove, List<List<Piece?>>>> successors = [];
    Map<BoardPosition, Set<BoardPosition>> moveOpportunities =
        rules.getAllMovesForPlayer(board, playerToMove, false);

    moveOpportunities.forEach((fromPos, firstStepDestinations) {
      for (BoardPosition firstToPos in firstStepDestinations) {
        bool isFirstStepAJump = (firstToPos.row - fromPos.row).abs() == 2 || 
                                (firstToPos.col - fromPos.col).abs() == 2;
        
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

  double _minimax(List<List<Piece?>> board, int depth, double alpha, double beta, bool isMaximizingPlayer, PieceType aiPlayerType) {
    if (depth == 0) {
      return rules.evaluateBoardForAI(board, aiPlayerType);
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
    List<AIMove> bestMovesFound = []; // Store all moves with the best score
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
      
      AIMove currentAIMove = AIMove(
          from: initialMove.from,
          to: initialMove.to,
          score: score, // Use the minimax score for comparison
          isJump: initialMove.isJump
      );

      if (score > maxScoreFound) {
        maxScoreFound = score;
        bestMovesFound = [currentAIMove]; // New best score, reset list
      } else if (score == maxScoreFound) {
        bestMovesFound.add(currentAIMove); // Same best score, add to list
      }
    }
    
    if (bestMovesFound.isEmpty) {
      // This case should ideally not be reached if possibleFirstMovesAndStates was not empty.
      // But as a fallback, if all scores were -infinity (e.g. forced loss)
      if (possibleFirstMovesAndStates.isNotEmpty) {
          AIMove firstAvailable = possibleFirstMovesAndStates.first.key;
          return AIMove(from: firstAvailable.from, to: firstAvailable.to, score: maxScoreFound, isJump: firstAvailable.isJump);
      }
      return null;
    }

    // Randomly select one from the best moves
    return bestMovesFound[_random.nextInt(bestMovesFound.length)];
  }
}