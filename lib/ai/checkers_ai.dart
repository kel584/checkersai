// lib/ai/checkers_ai.dart
import 'dart:math';
import '../models/piece_model.dart';
import '../models/bitboard_state.dart'; // Ensure this is imported
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
  final int quiescenceSearchDepth;
  final Random _random = Random();

  CheckersAI({
    required this.rules,
    this.searchDepth = 4,
    this.quiescenceSearchDepth = 3,
  });

  // _getSuccessorStates now takes BitboardState and returns MapEntry<AIMove, BitboardState>
  List<MapEntry<AIMove, BitboardState>> _getSuccessorStates(
    BitboardState board, // Takes BitboardState
    PieceType playerToMove, {
    bool capturesOnly = false,
  }) {
    List<MapEntry<AIMove, BitboardState>> successors = [];
    Map<BoardPosition, Set<BoardPosition>> moveOpportunities;

    // rules.getAllMovesForPlayer MUST take BitboardState and work with it
    if (capturesOnly) {
      moveOpportunities = rules.getAllMovesForPlayer(board, playerToMove, true);
    } else {
      moveOpportunities = rules.getAllMovesForPlayer(board, playerToMove, false);
    }

    moveOpportunities.forEach((fromPos, firstStepDestinations) {
      for (BoardPosition firstToPos in firstStepDestinations) {
        // Determine if this first step is a jump based on game rules or inference
        // This inference is okay if getAllMovesForPlayer prioritizes jumps correctly
        bool isFirstStepAJump = (firstToPos.row - fromPos.row).abs() == 2 ||
                                (firstToPos.col - fromPos.col).abs() == 2;
        
        if (capturesOnly && !isFirstStepAJump) {
          continue; 
        }

        BitboardState boardStateForSimulation = board.copy(); // Start with a copy
        BoardPosition currentPosOfPieceInAction = fromPos;
        bool currentTurnChanged = false;
        Piece? pieceDetailsForMultiJump = boardStateForSimulation.getPieceAt(fromPos.row, fromPos.col);


        // Simulate the first step
        MoveResult result = rules.applyMoveAndGetResult( // This method MUST work with BitboardState
          currentBoard: boardStateForSimulation, 
          from: currentPosOfPieceInAction,
          to: firstToPos,
          currentPlayer: playerToMove,
        );
        boardStateForSimulation = result.board; // result.board is BitboardState
        currentPosOfPieceInAction = firstToPos;
        currentTurnChanged = result.turnChanged;
        if (result.pieceKinged && pieceDetailsForMultiJump != null) {
            pieceDetailsForMultiJump = boardStateForSimulation.getPieceAt(currentPosOfPieceInAction.row, currentPosOfPieceInAction.col);
        }


        // Simulate multi-jumps if applicable
        if (isFirstStepAJump && !currentTurnChanged && pieceDetailsForMultiJump != null) {
          Piece pieceInAction = pieceDetailsForMultiJump; // Use potentially kinged piece
          
          while (!currentTurnChanged) { // Loop while current player can still jump
            // rules.getFurtherJumps MUST work with BitboardState
            Set<BoardPosition> furtherJumps = rules.getFurtherJumps(currentPosOfPieceInAction, pieceInAction, boardStateForSimulation);
            if (furtherJumps.isNotEmpty) {
              BoardPosition nextJumpToPos = furtherJumps.first; // AI takes the first available multi-jump path
              MoveResult multiJumpResult = rules.applyMoveAndGetResult(
                currentBoard: boardStateForSimulation,
                from: currentPosOfPieceInAction,
                to: nextJumpToPos,
                currentPlayer: playerToMove,
              );
              boardStateForSimulation = multiJumpResult.board;
              currentPosOfPieceInAction = nextJumpToPos;
              // Update pieceInAction if it kinged during the multi-jump
              if (multiJumpResult.pieceKinged) {
                 pieceInAction = boardStateForSimulation.getPieceAt(currentPosOfPieceInAction.row, currentPosOfPieceInAction.col) ?? pieceInAction;
              }
              currentTurnChanged = multiJumpResult.turnChanged;
            } else {
              break; // No more further jumps for this piece
            }
          }
        }
        successors.add(MapEntry(
            AIMove(from: fromPos, to: firstToPos, score: 0, isJump: isFirstStepAJump),
            boardStateForSimulation // Store the final BitboardState after all jumps
        ));
      }
    });
    return successors;
  }

  double _quiescenceSearch(BitboardState board, int depth, double alpha, double beta, bool isMaximizingPlayer, PieceType aiPlayerType) {
    // rules.evaluateBoardForAI MUST take BitboardState
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

    // _getSuccessorStates now returns MapEntry<AIMove, BitboardState>
    List<MapEntry<AIMove, BitboardState>> captureMovesAndStates =
        _getSuccessorStates(board, currentPlayerForNode, capturesOnly: true);

    if (captureMovesAndStates.isEmpty) return standPatScore;

    if (isMaximizingPlayer) {
      double maxEval = standPatScore;
      for (var entry in captureMovesAndStates) {
        // entry.value is BitboardState
        double eval = _quiescenceSearch(entry.value, depth - 1, alpha, beta, false, aiPlayerType);
        maxEval = max(maxEval, eval);
        alpha = max(alpha, eval);
        if (beta <= alpha) break;
      }
      return maxEval;
    } else { // Minimizing player
      double minEval = standPatScore;
      for (var entry in captureMovesAndStates) {
        // entry.value is BitboardState
        double eval = _quiescenceSearch(entry.value, depth - 1, alpha, beta, true, aiPlayerType);
        minEval = min(minEval, eval);
        beta = min(beta, eval);
        if (beta <= alpha) break;
      }
      return minEval;
    }
  }

  // _minimax now takes BitboardState
  double _minimax(BitboardState board, int depth, double alpha, double beta, bool isMaximizingPlayer, PieceType aiPlayerType) {
    if (depth == 0) {
      // Call quiescence search, which now takes BitboardState
      return _quiescenceSearch(board, quiescenceSearchDepth, alpha, beta, isMaximizingPlayer, aiPlayerType);
    }

    PieceType currentPlayerForNode = isMaximizingPlayer
        ? aiPlayerType
        : (aiPlayerType == PieceType.red ? PieceType.black : PieceType.red);

    // _getSuccessorStates now returns MapEntry<AIMove, BitboardState>
    List<MapEntry<AIMove, BitboardState>> childrenStatesAndMoves =
        _getSuccessorStates(board, currentPlayerForNode, capturesOnly: false);

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
        // entry.value is BitboardState
        double eval = _minimax(entry.value, depth - 1, alpha, beta, false, aiPlayerType);
        maxEval = max(maxEval, eval);
        alpha = max(alpha, eval);
        if (beta <= alpha) break;
      }
      return maxEval;
    } else { // Minimizing player
      double minEval = double.infinity;
      for (var entry in childrenStatesAndMoves) {
        // entry.value is BitboardState
        double eval = _minimax(entry.value, depth - 1, alpha, beta, true, aiPlayerType);
        minEval = min(minEval, eval);
        beta = min(beta, eval);
        if (beta <= alpha) break;
      }
      return minEval;
    }
  }

  // findBestMove now takes BitboardState
  AIMove? findBestMove(BitboardState currentBoard, PieceType aiPlayerType) {
    AIMove? bestMoveFromOverallIterations;

    for (int currentIterativeDepth = 1; currentIterativeDepth <= searchDepth; currentIterativeDepth++) {
      List<AIMove> bestMovesAtThisDepth = [];
      double iterationMaxScore = -double.infinity;

      // _getSuccessorStates takes BitboardState and returns entries with BitboardState
      List<MapEntry<AIMove, BitboardState>> possibleFirstMovesAndStates =
          _getSuccessorStates(currentBoard, aiPlayerType, capturesOnly: false);

      if (possibleFirstMovesAndStates.isEmpty) {
        return null;
      }

      if (bestMoveFromOverallIterations != null) {
        possibleFirstMovesAndStates.sort((a, b) {
          bool aIsPrevBest = a.key.from == bestMoveFromOverallIterations!.from && a.key.to == bestMoveFromOverallIterations.to && a.key.isJump == bestMoveFromOverallIterations.isJump;
          bool bIsPrevBest = b.key.from == bestMoveFromOverallIterations.from && b.key.to == bestMoveFromOverallIterations.to && b.key.isJump == bestMoveFromOverallIterations.isJump;
          if (aIsPrevBest) return -1; if (bIsPrevBest) return 1;
          if (a.key.isJump && !b.key.isJump) return -1; if (!a.key.isJump && b.key.isJump) return 1;
          return 0;
        });
      } else {
         possibleFirstMovesAndStates.sort((a,b) {
            if (a.key.isJump && !b.key.isJump) return -1; if (!a.key.isJump && b.key.isJump) return 1;
            return 0;
        });
      }

      for (var entry in possibleFirstMovesAndStates) {
        AIMove initialMove = entry.key;
        BitboardState boardAfterInitialMoveSequence = entry.value; // This is BitboardState
        
        double score = _minimax(boardAfterInitialMoveSequence, currentIterativeDepth - 1,
                                -double.infinity, double.infinity, 
                                false, aiPlayerType);
        
        AIMove currentEvaluatedMove = AIMove(
            from: initialMove.from, to: initialMove.to, score: score, isJump: initialMove.isJump);

        if (bestMovesAtThisDepth.isEmpty || score > iterationMaxScore) {
          iterationMaxScore = score;
          bestMovesAtThisDepth = [currentEvaluatedMove];
        } else if (score == iterationMaxScore) {
          bestMovesAtThisDepth.add(currentEvaluatedMove);
        }
      }
      
      if (bestMovesAtThisDepth.isNotEmpty) {
        bestMoveFromOverallIterations = bestMovesAtThisDepth[_random.nextInt(bestMovesAtThisDepth.length)];
      } else if (possibleFirstMovesAndStates.isNotEmpty && bestMoveFromOverallIterations == null) {
        AIMove firstAvailable = possibleFirstMovesAndStates.first.key;
        bestMoveFromOverallIterations = AIMove(from: firstAvailable.from, to: firstAvailable.to, score: iterationMaxScore, isJump: firstAvailable.isJump);
      }
    }
    return bestMoveFromOverallIterations;
  }
}