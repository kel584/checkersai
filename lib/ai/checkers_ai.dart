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
  final int searchDepth; // This now becomes the MAX depth for iterative deepening
  final int quiescenceSearchDepth;
  final Random _random = Random();

  CheckersAI({
    required this.rules,
    this.searchDepth = 4, // Max depth for iterative deepening (e.g., start with 4-5)
    this.quiescenceSearchDepth = 2,
  });

  List<MapEntry<AIMove, List<List<Piece?>>>> _getSuccessorStates(
    List<List<Piece?>> board,
    PieceType playerToMove, {
    bool capturesOnly = false,
  }) {
    List<MapEntry<AIMove, List<List<Piece?>>>> successors = [];
    Map<BoardPosition, Set<BoardPosition>> moveOpportunities;

    if (capturesOnly) {
      moveOpportunities = rules.getAllMovesForPlayer(board, playerToMove, true);
    } else {
      moveOpportunities = rules.getAllMovesForPlayer(board, playerToMove, false);
    }

    moveOpportunities.forEach((fromPos, firstStepDestinations) {
      for (BoardPosition firstToPos in firstStepDestinations) {
        bool isFirstStepAJump = (firstToPos.row - fromPos.row).abs() == 2 ||
                                (firstToPos.col - fromPos.col).abs() == 2;
        
        if (capturesOnly && !isFirstStepAJump) {
          continue; 
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

  double _quiescenceSearch(List<List<Piece?>> board, int depth, double alpha, double beta, bool isMaximizingPlayer, PieceType aiPlayerType) {
    double standPatScore = rules.evaluateBoardForAI(board, aiPlayerType);

    if (isMaximizingPlayer) {
      if (standPatScore >= beta) return beta;
      alpha = max(alpha, standPatScore);
    } else {
      if (standPatScore <= alpha) return alpha;
      beta = min(beta, standPatScore);
    }

    if (depth == 0) return standPatScore;

    PieceType currentPlayerForNode = isMaximizingPlayer
        ? aiPlayerType
        : (aiPlayerType == PieceType.red ? PieceType.black : PieceType.red);

    List<MapEntry<AIMove, List<List<Piece?>>>> captureMovesAndStates =
        _getSuccessorStates(board, currentPlayerForNode, capturesOnly: true);

    if (captureMovesAndStates.isEmpty) return standPatScore;

    if (isMaximizingPlayer) {
      double maxEval = standPatScore;
      for (var entry in captureMovesAndStates) {
        double eval = _quiescenceSearch(entry.value, depth - 1, alpha, beta, false, aiPlayerType);
        maxEval = max(maxEval, eval);
        alpha = max(alpha, eval);
        if (beta <= alpha) break;
      }
      return maxEval;
    } else {
      double minEval = standPatScore;
      for (var entry in captureMovesAndStates) {
        double eval = _quiescenceSearch(entry.value, depth - 1, alpha, beta, true, aiPlayerType);
        minEval = min(minEval, eval);
        beta = min(beta, eval);
        if (beta <= alpha) break;
      }
      return minEval;
    }
  }

  double _minimax(List<List<Piece?>> board, int depth, double alpha, double beta, bool isMaximizingPlayer, PieceType aiPlayerType) {
    if (depth == 0) {
      return _quiescenceSearch(board, quiescenceSearchDepth, alpha, beta, isMaximizingPlayer, aiPlayerType);
    }

    PieceType currentPlayerForNode = isMaximizingPlayer
        ? aiPlayerType
        : (aiPlayerType == PieceType.red ? PieceType.black : PieceType.red);

    List<MapEntry<AIMove, List<List<Piece?>>>> childrenStatesAndMoves =
        _getSuccessorStates(board, currentPlayerForNode, capturesOnly: false);

    if (childrenStatesAndMoves.isEmpty) {
      bool isAISperspectiveNodePlayer = (currentPlayerForNode == aiPlayerType);
      if (isAISperspectiveNodePlayer) return -10000.0 - depth;
      else return 10000.0 + depth;
    }

    if (isMaximizingPlayer) {
      double maxEval = -double.infinity;
      for (var entry in childrenStatesAndMoves) {
        double eval = _minimax(entry.value, depth - 1, alpha, beta, false, aiPlayerType);
        maxEval = max(maxEval, eval);
        alpha = max(alpha, eval);
        if (beta <= alpha) break;
      }
      return maxEval;
    } else {
      double minEval = double.infinity;
      for (var entry in childrenStatesAndMoves) {
        double eval = _minimax(entry.value, depth - 1, alpha, beta, true, aiPlayerType);
        minEval = min(minEval, eval);
        beta = min(beta, eval);
        if (beta <= alpha) break;
      }
      return minEval;
    }
  }

  // --- Main AI Method: findBestMove with Iterative Deepening ---
  AIMove? findBestMove(List<List<Piece?>> currentBoard, PieceType aiPlayerType) {
    AIMove? bestMoveFromOverallIterations; // Stores the best move from the deepest fully completed search

    for (int currentIterativeDepth = 1; currentIterativeDepth <= searchDepth; currentIterativeDepth++) {
      // print("[AI ID] Searching at depth: $currentIterativeDepth");
      List<AIMove> bestMovesAtThisDepth = [];
      double iterationMaxScore = -double.infinity;

      List<MapEntry<AIMove, List<List<Piece?>>>> possibleFirstMovesAndStates =
          _getSuccessorStates(currentBoard, aiPlayerType, capturesOnly: false);

      if (possibleFirstMovesAndStates.isEmpty) {
        // print("[AI ID] No moves available for AI at depth $currentIterativeDepth.");
        return null; // No moves at all for the AI
      }

      // Move Ordering: Try the best move from the PREVIOUS iteration first
      if (bestMoveFromOverallIterations != null) {
        possibleFirstMovesAndStates.sort((a, b) {
          // Check if move 'a' is the best move from the previous iteration
          bool aIsPrevBest = a.key.from == bestMoveFromOverallIterations!.from && 
                             a.key.to == bestMoveFromOverallIterations!.to &&
                             a.key.isJump == bestMoveFromOverallIterations!.isJump; // also check jump status
          // Check if move 'b' is the best move from the previous iteration
          bool bIsPrevBest = b.key.from == bestMoveFromOverallIterations!.from && 
                             b.key.to == bestMoveFromOverallIterations!.to &&
                             b.key.isJump == bestMoveFromOverallIterations!.isJump;

          if (aIsPrevBest) return -1; // 'a' comes first
          if (bIsPrevBest) return 1;  // 'b' comes first

          // Secondary sorting: jumps before non-jumps
          if (a.key.isJump && !b.key.isJump) return -1;
          if (!a.key.isJump && b.key.isJump) return 1;
          
          return 0; // Keep original relative order for other moves
        });
      } else { // First iteration (depth 1), just prioritize jumps
        possibleFirstMovesAndStates.sort((a,b) {
          if (a.key.isJump && !b.key.isJump) return -1;
          if (!a.key.isJump && b.key.isJump) return 1;
          return 0;
        });
      }

      for (var entry in possibleFirstMovesAndStates) {
        AIMove initialMove = entry.key;
        List<List<Piece?>> boardAfterInitialMoveSequence = entry.value;
        
        // For each root move, we start a fresh alpha-beta search for its subtree
        double score = _minimax(boardAfterInitialMoveSequence, currentIterativeDepth - 1,
                                -double.infinity, double.infinity, // Initial alpha, beta for this path
                                false, aiPlayerType); // false because it's opponent's turn next
        
        AIMove currentEvaluatedMove = AIMove(
            from: initialMove.from,
            to: initialMove.to,
            score: score,
            isJump: initialMove.isJump);

        if (bestMovesAtThisDepth.isEmpty || score > iterationMaxScore) {
          iterationMaxScore = score;
          bestMovesAtThisDepth = [currentEvaluatedMove];
        } else if (score == iterationMaxScore) {
          bestMovesAtThisDepth.add(currentEvaluatedMove);
        }
      }
      
      if (bestMovesAtThisDepth.isNotEmpty) {
        // Update the overall best move with the result from this completed depth
        bestMoveFromOverallIterations = bestMovesAtThisDepth[_random.nextInt(bestMovesAtThisDepth.length)];
        // print("[AI ID] Depth $currentIterativeDepth, Best move: $bestMoveFromOverallIterations, Score: $iterationMaxScore");
      } else if (possibleFirstMovesAndStates.isNotEmpty && bestMoveFromOverallIterations == null) {
        // This case handles if all moves at the first depth lead to very bad (e.g. -inf) scores
        AIMove firstAvailable = possibleFirstMovesAndStates.first.key;
        bestMoveFromOverallIterations = AIMove(from: firstAvailable.from, to: firstAvailable.to, score: iterationMaxScore, isJump: firstAvailable.isJump);
      }

      // TODO (Future): Implement a time limit check here.
      // If time is up and bestMoveFromOverallIterations is not null, break the loop.
    }
    
    // print("[AI ID] Final chosen move after all iterations: $bestMoveFromOverallIterations");
    return bestMoveFromOverallIterations; // Return the best move from the deepest fully completed search
  }
}