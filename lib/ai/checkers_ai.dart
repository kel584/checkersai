import 'dart:developer' as developer;
import 'dart:math';
import '../models/piece_model.dart';
import '../models/bitboard_state.dart';
import '../game_rules/game_rules.dart';
import '../utils/bit_utils.dart';

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
  String toString() =>
      'AIMove(from: $from, to: $to, score: $score, isJump: $isJump)';
}

class CheckersAI {
  final GameRules rules;
  final int maxSearchDepth;
  final int quiescenceSearchDepth;
  final Random _random = Random();

  CheckersAI({
    required this.rules,
    this.maxSearchDepth = 9,
    this.quiescenceSearchDepth = 8,
  });

  // Dynamic depth based on piece count
  int _getSearchDepth(BitboardState board) {
    final pieceCount = popCount(board.blackMen | board.blackKings | board.redMen | board.redKings);
    return pieceCount <= 10 ? maxSearchDepth + 4 : maxSearchDepth;
  }

  // Enhanced evaluation that considers opening principles
double _enhancedPositionalEvaluation(BitboardState board, PieceType player) {
  double score = 0.0;
  final isBlack = player == PieceType.black;
  final totalPieces = popCount(board.blackMen | board.blackKings | board.redMen | board.redKings);
  
  // Opening phase bonuses (when piece count > 20)
  if (totalPieces > 20) {
    score += _evaluateOpeningPrinciples(board, player) * 1.5; // Increased weight
  }
  
  // Control of center squares - always important
  score += _evaluateCenterControl(board, player) * (totalPieces > 20 ? 4.0 : 2.0);
  
  // Piece mobility and flexibility
  score += _evaluateMobility(board, player) * 1.5;
  
  // Formation and structure bonuses
  score += _evaluateFormation(board, player) * 1.0;
  
  // Development bonus in opening
  if (totalPieces > 20) {
    score += _evaluateDevelopment(board, player) * 2.0;
  }
  
  return score;
}

double _evaluateDevelopment(BitboardState board, PieceType player) {
  double score = 0.0;
  final isBlack = player == PieceType.black;
  final backRank = isBlack ? [0, 1, 2, 3, 4, 5, 6, 7] : [56, 57, 58, 59, 60, 61, 62, 63];
  final playerMen = isBlack ? board.blackMen : board.redMen;
  
  var developedPieces = 0;
  var totalBackRankPieces = 0;
  
  for (final square in backRank) {
    if (isSet(playerMen, square)) {
      totalBackRankPieces++;
    }
  }
  
  // Count pieces that have moved from back rank
  final expectedBackRankPieces = isBlack ? 8 : 8; // Assuming standard starting position
  developedPieces = expectedBackRankPieces - totalBackRankPieces;
  
  // Reward development but don't overdevelop
  if (developedPieces >= 2 && developedPieces <= 5) {
    score += developedPieces * 15.0;
  } else if (developedPieces > 5) {
    score += 5 * 15.0 + (developedPieces - 5) * 5.0; // Diminishing returns
  }
  
  return score;
}

  double _evaluateMiddlegamePosition(AIMove move, BitboardState board, PieceType player) {
  double score = 0.0;
  final toSquare = move.to.row * 8 + move.to.col;
  
  // Center still valuable but less critical
  final centerSquares = [27, 28, 35, 36];
  if (centerSquares.contains(toSquare)) {
    score += 15.0;
  }
  
  // Advancement towards opponent side
  final advancement = player == PieceType.black 
      ? move.to.row - move.from.row 
      : move.from.row - move.to.row;
  if (advancement > 0) {
    score += advancement * 8.0;
  }
  
  // King promotion proximity
  final promotionRow = player == PieceType.black ? 7 : 0;
  final distanceToPromotion = (move.to.row - promotionRow).abs();
  if (distanceToPromotion <= 2) {
    score += (3 - distanceToPromotion) * 10.0;
  }
  
  return score;
}

  double _evaluateOpeningPrinciples(BitboardState board, PieceType player) {
    double score = 0.0;
    final isBlack = player == PieceType.black;
    
    // Bonus for controlling key central squares
    final centralSquares = [18, 21, 26, 29, 34, 37, 42, 45]; // Central area
    for (final sq in centralSquares) {
      if (_isSquareControlledBy(board, sq, player)) {
        score += 8.0; // Significant bonus for central control
      }
    }
    
    // Bonus for developing pieces from back rank
    final backRank = isBlack ? [1, 3, 5, 7] : [56, 58, 60, 62];
    for (final sq in backRank) {
      if (!_hasPlayerPieceAt(board, sq, player)) {
        score += 5.0; // Bonus for developing back rank pieces
      }
    }
    
    return score;
  }

  double _evaluateCenterControl(BitboardState board, PieceType player) {
    double score = 0.0;
    final centerSquares = [27, 28, 35, 36]; // True center
    final extendedCenter = [18, 21, 26, 29, 34, 37, 42, 45];
    
    for (final sq in centerSquares) {
      if (_hasPlayerPieceAt(board, sq, player)) {
        score += 12.0;
      }
    }
    
    for (final sq in extendedCenter) {
      if (_hasPlayerPieceAt(board, sq, player)) {
        score += 6.0;
      }
    }
    
    return score;
  }

  double _evaluateMobility(BitboardState board, PieceType player) {
    final moves = rules.getAllMovesForPlayer(board, player, false);
    final captures = rules.getAllMovesForPlayer(board, player, true);
    
    return moves.length * 2.0 + captures.length * 5.0;
  }

  double _evaluateFormation(BitboardState board, PieceType player) {
    double score = 0.0;
    final isBlack = player == PieceType.black;
    
    // Bonus for maintaining connected pieces (avoid holes in formation)
    final playerMask = isBlack ? board.blackMen : board.redMen;
    var pieces = playerMask;
    
    while (pieces != 0) {
      final sq = lsbIndex(pieces);
      if (sq >= 0 && sq < 64) {
        pieces = clearBit(pieces, sq);
        
        // Check for adjacent friendly pieces
        final adjacentSquares = _getAdjacentSquares(sq);
        for (final adjSq in adjacentSquares) {
          if (_hasPlayerPieceAt(board, adjSq, player)) {
            score += 3.0; // Bonus for connected pieces
          }
        }
      }
    }
    
    return score;
  }

  List<int> _getAdjacentSquares(int square) {
    final row = square ~/ 8;
    final col = square % 8;
    final adjacent = <int>[];
    
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final newRow = row + dr;
        final newCol = col + dc;
        if (newRow >= 0 && newRow < 8 && newCol >= 0 && newCol < 8) {
          adjacent.add(newRow * 8 + newCol);
        }
      }
    }
    return adjacent;
  }

  bool _hasPlayerPieceAt(BitboardState board, int square, PieceType player) {
    if (square < 0 || square >= 64) return false;
    final mask = 1 << square;
    return player == PieceType.black 
        ? (board.blackMen & mask) != 0 || (board.blackKings & mask) != 0
        : (board.redMen & mask) != 0 || (board.redKings & mask) != 0;
  }

  bool _isSquareControlledBy(BitboardState board, int square, PieceType player) {
    // A square is "controlled" if a player's piece can move to it or attacks it
    final moves = rules.getAllMovesForPlayer(board, player, false);
    for (final entry in moves.entries) {
      for (final destination in entry.value) {
        if (destination.row * 8 + destination.col == square) {
          return true;
        }
      }
    }
    return false;
  }

double _getMovePositionalValue(AIMove move, BitboardState board, PieceType player, int totalPieces) {
  double score = 0.0;
  final toSquare = move.to.row * 8 + move.to.col;
  final fromSquare = move.from.row * 8 + move.from.col;
  
  // Opening phase (lots of pieces)
  if (totalPieces > 20) {
    // Reduced preference for central development
    final centerSquares = [27, 28, 35, 36]; // True center
    final extendedCenter = [18, 19, 20, 21, 26, 29, 34, 37, 42, 43, 44, 45]; // Extended center
    final innerCenter = [19, 20, 27, 28, 35, 36, 43, 44]; // Key squares
    
    if (centerSquares.contains(toSquare)) {
      score += 20.0; // Reduced bonus for true center
    } else if (innerCenter.contains(toSquare)) {
      score += 15.0; // Reduced bonus for inner center
    } else if (extendedCenter.contains(toSquare)) {
      score += 10.0; // Reduced bonus for extended center
    }
    
    // Reduced penalty for moves to edges and corners in opening
    final col = move.to.col;
    final row = move.to.row;
    if (col == 0 || col == 7 || row == 0 || row == 7) {
      score -= 10.0; // Reduced penalty for edge moves
    }
    
    // Reward forward development
    final advancement = player == PieceType.black 
        ? move.to.row - move.from.row 
        : move.from.row - move.to.row;
    if (advancement > 0) {
      score += advancement * 12.0; // Maintain forward movement reward
    }
    
    // Bonus for developing from back rank
    final backRow = player == PieceType.black ? 0 : 7;
    if (move.from.row == backRow) {
      score += 18.0; // Maintain development bonus
    }
    
    // Penalty for moving same piece twice in opening
    final midRow = player == PieceType.black ? 3 : 4;
    if (move.from.row == midRow) {
      score -= 8.0; // Maintain penalty for redeveloping
    }

    // New: Bonus for setting up captures
    if (_setsUpCapture(move, board, player)) {
      score += 15.0; // Encourage moves that enable future captures
    }
  } else {
    // Middlegame/Endgame positioning
    score += _evaluateMiddlegamePosition(move, board, player);
  }
  
  // Safety evaluation - maintain enhanced penalty
  if (_wouldBeInDanger(board, move, player)) {
    score -= 50.0; // Higher penalty for unsafe moves
  }
  
  // Reduced randomness for tie-breaking
  score += (_random.nextDouble() - 0.5) * 1.0; // Reduced range: -0.5 to +0.5
  
  return score;
}

bool _setsUpCapture(AIMove move, BitboardState board, PieceType player) {
  final tempBoard = board.copy();
  rules.applyMoveAndGetResult(
    currentBoard: tempBoard,
    from: move.from,
    to: move.to,
    currentPlayer: player,
  );
  final captures = rules.getAllMovesForPlayer(tempBoard, player, true);
  return captures.isNotEmpty;
}

  bool _wouldBeInDanger(BitboardState board, AIMove move, PieceType player) {
    final tempBoard = board.copy();
    rules.applyMoveAndGetResult(
      currentBoard: tempBoard,
      from: move.from,
      to: move.to,
      currentPlayer: player,
    );
    
    final opponent = player == PieceType.black ? PieceType.red : PieceType.black;
    final opponentCaptures = rules.getAllMovesForPlayer(tempBoard, opponent, true);
    
    return opponentCaptures.entries.any((entry) => 
      entry.value.any((dest) => dest == move.to));
  }

  List<MapEntry<AIMove, BitboardState>> _getSuccessorStates(
    BitboardState board,
    PieceType playerToMove,
    {bool capturesOnly = false,
  }) {
    List<MapEntry<AIMove, BitboardState>> successors = [];
    Map<BoardPosition, Set<BoardPosition>> moveOpportunities;

    if (capturesOnly) {
      moveOpportunities = rules.getAllMovesForPlayer(board, playerToMove, true);
    } else {
      moveOpportunities = rules.getAllMovesForPlayer(board, playerToMove, false);
    }

    moveOpportunities.forEach((fromPos, squareDestinations) {
      for (final square in squareDestinations) {
        final isJumpMove = (square.row - fromPos.row).abs() == 2 ||
            (square.col - fromPos.col).abs() == 2;

        if (capturesOnly && !isJumpMove) {
          continue;
        }

        BitboardState boardStateForSimulation = board.copy();
        BoardPosition currentPosOfSquareInAction = fromPos;
        bool currentTurnChanged = false;
        Piece? pieceDetailsForMultiJump = boardStateForSimulation.getPieceAt(fromPos.row, fromPos.col);

        final result = rules.applyMoveAndGetResult(
          currentBoard: boardStateForSimulation,
          from: currentPosOfSquareInAction,
          to: square,
          currentPlayer: playerToMove,
        );
        boardStateForSimulation = result.board;
        currentPosOfSquareInAction = square;
        currentTurnChanged = result.turnChanged;
        if (result.pieceKinged && pieceDetailsForMultiJump != null) {
          pieceDetailsForMultiJump = boardStateForSimulation.getPieceAt(currentPosOfSquareInAction.row, currentPosOfSquareInAction.col);
        }

        if (isJumpMove && !currentTurnChanged && pieceDetailsForMultiJump != null) {
          Piece pieceInAction = pieceDetailsForMultiJump;

          while (!currentTurnChanged) {
            final furtherJumps = rules.getFurtherJumps(currentPosOfSquareInAction, pieceInAction, boardStateForSimulation);
            if (furtherJumps.isNotEmpty) {
              final nextJumpToPos = furtherJumps.first;
              final multiJumpResult = rules.applyMoveAndGetResult(
                currentBoard: boardStateForSimulation,
                from: currentPosOfSquareInAction,
                to: nextJumpToPos,
                currentPlayer: playerToMove,
              );
              boardStateForSimulation = multiJumpResult.board;
              currentPosOfSquareInAction = nextJumpToPos;
              if (multiJumpResult.pieceKinged) {
                pieceInAction = boardStateForSimulation.getPieceAt(currentPosOfSquareInAction.row, currentPosOfSquareInAction.col) ?? pieceInAction;
              }
              currentTurnChanged = multiJumpResult.turnChanged;
            } else {
              break;
            }
          }
        }
        successors.add(MapEntry(
          AIMove(from: fromPos, to: square, score: 0, isJump: isJumpMove),
          boardStateForSimulation,
        ));
      }
      
    });
    return successors;
  }

  double _quiescenceSearch(BitboardState board, int depth, double alpha, double beta, bool isMaximizingPlayer, PieceType aiPlayerType) {
    final standPatScore = rules.evaluateBoardForAI(board, aiPlayerType) + _enhancedPositionalEvaluation(board, aiPlayerType);

    if (isMaximizingPlayer) {
      if (standPatScore >= beta) return standPatScore;
      alpha = max(alpha, standPatScore);
    } else {
      if (standPatScore <= alpha) return standPatScore;
      beta = min(beta, standPatScore);
    }

    if (depth == 0) {
      final pieceCount = popCount(board.blackMen | board.blackKings | board.redMen | board.redKings);
      if (pieceCount <= 10) {
        final oppMen = aiPlayerType == PieceType.black ? board.allRedPieces : board.allBlackPieces;
        final isBlack = aiPlayerType == PieceType.black;
        if (_hasImmediatePromotionThreat(oppMen, isBlack, board)) {
          return isMaximizingPlayer ? standPatScore - 500 : standPatScore + 500;
        }
      }
      return standPatScore;
    }

    final currentPlayerForNode = isMaximizingPlayer
        ? aiPlayerType
        : (aiPlayerType == PieceType.black ? PieceType.red : PieceType.black);

    final captureMovesAndStates = _getSuccessorStates(board, currentPlayerForNode, capturesOnly: true);

    if (captureMovesAndStates.isEmpty) {
      return standPatScore;
    }

    captureMovesAndStates.sort((a, b) => _compareMoves(a.key, b.key, board, currentPlayerForNode));

    if (isMaximizingPlayer) {
      double maxEval = standPatScore;
      for (final entry in captureMovesAndStates) {
        final eval = _quiescenceSearch(entry.value, depth - 1, alpha, beta, false, aiPlayerType);
        maxEval = max(maxEval, eval);
        alpha = max(alpha, eval);
        if (beta <= alpha) break;
      }
      return maxEval;
    } else {
      double minEval = standPatScore;
      for (final entry in captureMovesAndStates) {
        final eval = _quiescenceSearch(entry.value, depth - 1, alpha, beta, true, aiPlayerType);
        minEval = min(minEval, eval);
        beta = min(beta, eval);
        if (beta <= alpha) break;
      }
      return minEval;
    }
  }

  bool _hasImmediatePromotionThreat(int oppMen, bool isBlack, BitboardState board) {
    var pieces = oppMen;
    var safetyCounter = 0;
    while (pieces != 0 && safetyCounter < 64) {
      final sq = lsbIndex(pieces);
      if (sq < 0 || sq >= 64) break;
      pieces = clearBit(pieces, sq);
      safetyCounter++;

      final r = sq ~/ 8, c = sq % 8;
      final forward = isBlack ? -1 : 1;
      final nr = r + forward;
      if (nr >= 0 && nr < 8) {
        final targetSquare = nr * 8 + c;
        if (targetSquare < 64 && isSet(board.allEmptySquares, targetSquare)) {
          return true;
        }
      }
    }
    return false;
  }

  // Enhanced move comparison that considers position quality
int _compareMoves(AIMove a, AIMove b, BitboardState board, PieceType player) {
  double aScore = 0, bScore = 0;
  final totalPieces = popCount(board.blackMen | board.blackKings | board.redMen | board.redKings);
  
  // Captures always get highest priority
  if (a.isJump && !b.isJump) return -1; // a is better
  if (b.isJump && !a.isJump) return 1;  // b is better
  
  if (a.isJump && b.isJump) {
    // Both are captures - prioritize by capture value and safety
    aScore += _getCaptureValue(a, board, player);
    bScore += _getCaptureValue(b, board, player);
    
    // Safety consideration for captures
    if (_isExposedAfterMove(board, a, player)) aScore -= 30;
    if (_isExposedAfterMove(board, b, player)) bScore -= 30;
  } else {
    // Both are non-captures - use enhanced positional scoring
    aScore = _getMovePositionalValue(a, board, player, totalPieces);
    bScore = _getMovePositionalValue(b, board, player, totalPieces);
  }
  
  // Higher score should come first (descending order)
  return bScore.compareTo(aScore);
}

double _getCaptureValue(AIMove move, BitboardState board, PieceType player) {
  double value = 100.0; // Base capture value
  
  // Bonus for capturing advanced pieces
  final capturedRow = move.to.row;
  final opponentAdvancement = player == PieceType.black 
      ? 7 - capturedRow  // For black, lower row numbers are more advanced for red
      : capturedRow;     // For red, higher row numbers are more advanced for black
  
  value += opponentAdvancement * 15.0; // Reward capturing advanced pieces
  
  // Check if capturing a king (though this might need game-specific logic)
  final captureSquare = move.to.row * 8 + move.to.col;
  final opponentKings = player == PieceType.black ? board.redKings : board.blackKings;
  if (isSet(opponentKings, captureSquare)) {
    value += 180.0; // Huge bonus for capturing kings
  }
  
  return value;
}

  bool _isExposedAfterMove(BitboardState board, AIMove move, PieceType player) {
    final tempBoard = board.copy();
    rules.applyMoveAndGetResult(
      currentBoard: tempBoard,
      from: move.from,
      to: move.to,
      currentPlayer: player,
    );
    final oppPlayer = player == PieceType.black ? PieceType.red : PieceType.black;
    final oppCaptures = _getSuccessorStates(tempBoard, oppPlayer, capturesOnly: true);
    return oppCaptures.any((entry) => entry.key.to == move.to);
  }

  bool _isNearPromotionZone(BoardPosition pos, PieceType player) {
    final rank = player == PieceType.black ? pos.row : 7 - pos.row;
    return rank >= 5;
  }

  // Modified minimax that incorporates enhanced evaluation
  double _minimax(BitboardState board, int depth, double alpha, double beta, bool isMaximizingPlayer, PieceType aiPlayerType) {
    if (depth == 0) {
      return _quiescenceSearch(board, quiescenceSearchDepth, alpha, beta, isMaximizingPlayer, aiPlayerType);
    }

    final currentPlayer = isMaximizingPlayer
        ? aiPlayerType
        : (aiPlayerType == PieceType.black ? PieceType.red : PieceType.black);

    final childrenStates = _getSuccessorStates(board, currentPlayer, capturesOnly: false);

    if (childrenStates.isEmpty) {
      return isMaximizingPlayer ? -32000.0 + depth : 32000.0 - depth;
    }

    childrenStates.sort((a, b) => _compareMoves(a.key, b.key, board, currentPlayer));

    if (isMaximizingPlayer) {
      double maxEval = -double.infinity;
      for (final entry in childrenStates) {
        final eval = _minimax(entry.value, depth - 1, alpha, beta, false, aiPlayerType);
        maxEval = max(maxEval, eval);
        alpha = max(alpha, eval);
        if (beta <= alpha) break;
      }
      return maxEval;
    } else {
      double minEval = double.infinity;
      for (final entry in childrenStates) {
        final eval = _minimax(entry.value, depth - 1, alpha, beta, true, aiPlayerType);
        minEval = min(minEval, eval);
        beta = min(beta, eval);
        if (beta <= alpha) break;
      }
      return minEval;
    }
  }

  AIMove? findBestMove(BitboardState currentBoard, PieceType aiPlayerType) {
    AIMove? bestMoveFromOverallIterations;
    final currentDepth = _getSearchDepth(currentBoard);
    double bestScore = -double.infinity;
    const double scoreThreshold = 300.0;
    const int maxTimeMs = 1500;
    const int minDepth = 3; // Ensure at least depth 3 for opening
    final stopwatch = Stopwatch()..start();
    int finalDepth = 1;

    // DEBUG: Log initial board state
    final initialEval = rules.evaluateBoardForAI(currentBoard, aiPlayerType);
    final enhancedEval = _enhancedPositionalEvaluation(currentBoard, aiPlayerType);
    developer.log('🔍 Initial board eval: $initialEval + $enhancedEval = ${initialEval + enhancedEval} for $aiPlayerType', name: 'CheckersAI');

    for (int currentIterativeDepth = 1; currentIterativeDepth <= currentDepth; currentIterativeDepth++) {
      if (stopwatch.elapsedMilliseconds > maxTimeMs) {
        break;
      }

      List<AIMove> bestMovesAtThisDepth = [];
      double iterationMaxScore = -double.infinity;

      final possibleFirstMovesAndStates = _getSuccessorStates(currentBoard, aiPlayerType, capturesOnly: false);

      if (possibleFirstMovesAndStates.isEmpty) {
        return null;
      }

      // DEBUG: Log number of possible moves
      developer.log('📊 Depth $currentIterativeDepth: ${possibleFirstMovesAndStates.length} possible moves', name: 'CheckersAI');

      possibleFirstMovesAndStates.sort((a, b) => _compareMoves(a.key, b.key, currentBoard, aiPlayerType));

      // DEBUG: Log top 3 moves after sorting
      for (int i = 0; i < min(3, possibleFirstMovesAndStates.length); i++) {
        final move = possibleFirstMovesAndStates[i].key;
        final moveScore = _getMovePositionalValue(move, currentBoard, aiPlayerType, popCount(currentBoard.blackMen | currentBoard.blackKings | currentBoard.redMen | currentBoard.redKings));
        developer.log('  Top ${i+1}: ${move.from} → ${move.to}, ordering score: $moveScore', name: 'CheckersAI');
      }

      for (final entry in possibleFirstMovesAndStates) {
        final initialMove = entry.key;
        final boardAfterInitialMoveSequence = entry.value;

        // DEBUG: Log evaluation before minimax
        final preMinimaxEval = rules.evaluateBoardForAI(boardAfterInitialMoveSequence, aiPlayerType);
        final preMinimaxEnhanced = _enhancedPositionalEvaluation(boardAfterInitialMoveSequence, aiPlayerType);
        
        final score = _minimax(
          boardAfterInitialMoveSequence,
          currentIterativeDepth - 1,
          -double.infinity,
          double.infinity,
          false,
          aiPlayerType,
        );

        // DEBUG: Log each move's evaluation
        developer.log('  Move ${initialMove.from} → ${initialMove.to}: preEval=${preMinimaxEval + preMinimaxEnhanced}, minimax=$score', name: 'CheckersAI');

        final currentEvaluatedMove = AIMove(
          from: initialMove.from,
          to: initialMove.to,
          score: score.clamp(-10000, 10000),
          isJump: initialMove.isJump,
        );

        if (bestMovesAtThisDepth.isEmpty || score > iterationMaxScore) {
          iterationMaxScore = score;
          bestMovesAtThisDepth = [currentEvaluatedMove];
        } else if (score == iterationMaxScore) {
          bestMovesAtThisDepth.add(currentEvaluatedMove);
        }
      }

      if (bestMovesAtThisDepth.isNotEmpty) {
        bestMoveFromOverallIterations = bestMovesAtThisDepth[_random.nextInt(bestMovesAtThisDepth.length)];
        bestScore = iterationMaxScore;
        finalDepth = currentIterativeDepth;
        
        // DEBUG: Log best moves at this depth
        developer.log('✅ Depth $currentIterativeDepth best score: $bestScore, ${bestMovesAtThisDepth.length} tied moves', name: 'CheckersAI');
      } else if (possibleFirstMovesAndStates.isNotEmpty && bestMoveFromOverallIterations == null) {
        final firstAvailable = possibleFirstMovesAndStates.first.key;
        bestMoveFromOverallIterations = AIMove(
          from: firstAvailable.from,
          to: firstAvailable.to,
          score: iterationMaxScore.clamp(-10000, 10000),
          isJump: firstAvailable.isJump,
        );
        bestScore = iterationMaxScore;
        finalDepth = currentIterativeDepth;
      }

      // Only stop early if past minDepth and score is good
      if (currentIterativeDepth >= minDepth && bestMoveFromOverallIterations != null && bestScore > scoreThreshold) {
        break;
      }
    }

    // Enhanced final logging
    if (bestMoveFromOverallIterations != null) {
      final finalBoard = _getSuccessorStates(currentBoard, aiPlayerType)
          .firstWhere((entry) => entry.key.from == bestMoveFromOverallIterations!.from && entry.key.to == bestMoveFromOverallIterations!.to)
          .value;
      final rawEvalScore = rules.evaluateBoardForAI(finalBoard, aiPlayerType);
      final enhancedScore = _enhancedPositionalEvaluation(finalBoard, aiPlayerType);
      final initialRawEval = rules.evaluateBoardForAI(currentBoard, aiPlayerType);
      final initialEnhanced = _enhancedPositionalEvaluation(currentBoard, aiPlayerType);
      
      developer.log(
        '🏁 Final Move: ${bestMoveFromOverallIterations.from} to ${bestMoveFromOverallIterations.to}, '
        'Minimax Score: $bestScore, Raw Eval: ${rawEvalScore + enhancedScore} (was ${initialRawEval + initialEnhanced}), Depth: $finalDepth, '
        'Pieces: ${popCount(currentBoard.blackMen | currentBoard.blackKings | currentBoard.redMen | currentBoard.redKings)}, '
        'IsJump: ${bestMoveFromOverallIterations.isJump}',
        name: 'CheckersAI',
      );
    }

    stopwatch.stop();
    return bestMoveFromOverallIterations;
  }
}