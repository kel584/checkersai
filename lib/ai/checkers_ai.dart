import 'dart:developer' as developer;
import 'dart:math';
import '../models/piece_model.dart';
import '../models/bitboard_state.dart';
import '../game_rules/game_rules.dart';
import '../utils/bit_utils.dart';
import '../ai_evaluators/turkish_checkers_evaluator.dart';

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
  final TurkishCheckersEvaluator evaluator;
  final int maxSearchDepth;
  final int quiescenceSearchDepth;
  final Random _random = Random();
  
  // Transposition table for memoization
  final Map<String, double> _transpositionTable = {};
  static const int _maxTableSize = 10000;
  
  // Move ordering history
  final Map<String, int> _historyTable = {};

  CheckersAI({
    required this.rules,
    TurkishCheckersEvaluator? evaluator,
    this.maxSearchDepth = 10,
    this.quiescenceSearchDepth = 6,
  }) : evaluator = evaluator ?? TurkishCheckersEvaluator();

  // Clear tables periodically to prevent memory issues
  void _clearTablesIfNeeded() {
    if (_transpositionTable.length > _maxTableSize) {
      _transpositionTable.clear();
    }
    if (_historyTable.length > _maxTableSize) {
      _historyTable.clear();
    }
  }

  // Generate hash key for transposition table
  String _getBoardHash(BitboardState board, PieceType player, int depth) {
    return '${board.blackMen}_${board.blackKings}_${board.redMen}_${board.redKings}_${player.index}_$depth';
  }

  // Dynamic depth adjustment based on game phase
  int _getSearchDepth(BitboardState board) {
    final pieceCount = popCount(board.blackMen | board.blackKings | board.redMen | board.redKings);
    
    if (pieceCount <= 8) {
      return maxSearchDepth + 6; // Deep endgame search
    } else if (pieceCount <= 16) {
      return maxSearchDepth + 2; // Extended endgame search
    } else if (pieceCount >= 20) {
      return max(6, maxSearchDepth - 2); // Faster opening search
    }
    return maxSearchDepth; // Standard middlegame search
  }

  // Use the Turkish Checkers evaluator for board evaluation
  double _evaluateBoard(BitboardState board, PieceType player) {
    return evaluator.evaluate(
      board: board,
      aiPlayerType: player,
      rules: rules,
    );
  }

  // Enhanced move ordering using multiple heuristics
  int _compareMoves(AIMove a, AIMove b, BitboardState board, PieceType player) {
    // 1. Captures first
    if (a.isJump && !b.isJump) return -1;
    if (b.isJump && !a.isJump) return 1;
    
    double aScore = 0, bScore = 0;
    
    // 2. For captures, prioritize by capture value
    if (a.isJump && b.isJump) {
      aScore += _getCaptureValue(a, board, player);
      bScore += _getCaptureValue(b, board, player);
      
      // Prefer safer captures
      if (_wouldBeInDanger(board, a, player)) aScore -= 50.0;
      if (_wouldBeInDanger(board, b, player)) bScore -= 50.0;
    }
    
    // 3. History heuristic (moves that caused cutoffs before)
    final aKey = '${a.from.row},${a.from.col}-${a.to.row},${a.to.col}';
    final bKey = '${b.from.row},${b.from.col}-${b.to.row},${b.to.col}';
    aScore += (_historyTable[aKey] ?? 0) * 0.1;
    bScore += (_historyTable[bKey] ?? 0) * 0.1;
    
    // 4. Positional value
    aScore += _getPositionalMoveValue(a, board, player);
    bScore += _getPositionalMoveValue(b, board, player);
    
    // 5. Small random factor to break ties
    aScore += (_random.nextDouble() - 0.5) * 0.01;
    bScore += (_random.nextDouble() - 0.5) * 0.01;
    
    return bScore.compareTo(aScore);
  }

  // Calculate capture value considering piece types and positions
  double _getCaptureValue(AIMove move, BitboardState board, PieceType player) {
    double value = 0.0;
    final opponent = player == PieceType.black ? PieceType.red : PieceType.black;
    
    // Simulate the move to see what gets captured
    final tempBoard = board.copy();
    final result = rules.applyMoveAndGetResult(
      currentBoard: tempBoard,
      from: move.from,
      to: move.to,
      currentPlayer: player,
    );
    
    // Count material difference
    final originalOppPieces = opponent == PieceType.black 
        ? popCount(board.blackMen) + popCount(board.blackKings) * 2.8
        : popCount(board.redMen) + popCount(board.redKings) * 2.8;
    final newOppPieces = opponent == PieceType.black 
        ? popCount(result.board.blackMen) + popCount(result.board.blackKings) * 2.8
        : popCount(result.board.redMen) + popCount(result.board.redKings) * 2.8;
    
    value += (originalOppPieces - newOppPieces) * 100.0;
    
    // Bonus for capturing advanced pieces
    final capturedRow = move.to.row;
    final advancement = opponent == PieceType.black ? capturedRow : 7 - capturedRow;
    value += advancement * 5.0;
    
    return value;
  }

  // Get positional value of a move
  double _getPositionalMoveValue(AIMove move, BitboardState board, PieceType player) {
    double score = 0.0;
    final totalPieces = popCount(board.blackMen | board.blackKings | board.redMen | board.redKings);
    
    // Center control bonus
    const centerSquares = 0x0000001818000000; // Central 4 squares
    const extendedCenter = 0x00003C3C3C0000;   // Extended center
    final toSquare = move.to.row * 8 + move.to.col;
    
    if (isSet(centerSquares, toSquare)) {
      score += totalPieces > 20 ? 15.0 : 10.0;
    } else if (isSet(extendedCenter, toSquare)) {
      score += totalPieces > 20 ? 8.0 : 5.0;
    }
    
    // Advancement bonus
    final advancement = player == PieceType.black 
        ? move.to.row - move.from.row 
        : move.from.row - move.to.row;
    if (advancement > 0) {
      score += advancement * (totalPieces > 20 ? 5.0 : 8.0);
    }
    
    // Promotion proximity
    final promotionRow = player == PieceType.black ? 7 : 0;
    final distanceToPromotion = (move.to.row - promotionRow).abs();
    if (distanceToPromotion <= 2) {
      score += (3 - distanceToPromotion) * (totalPieces <= 16 ? 20.0 : 10.0);
    }
    
    // Edge penalty in opening
    if (totalPieces > 20) {
      final col = move.to.col;
      final row = move.to.row;
      if (col == 0 || col == 7 || row == 0 || row == 7) {
        score -= 5.0;
      }
    }
    
    return score;
  }

  // Check if move would put piece in danger
  bool _wouldBeInDanger(BitboardState board, AIMove move, PieceType player) {
    final tempBoard = board.copy();
    final result = rules.applyMoveAndGetResult(
      currentBoard: tempBoard,
      from: move.from,
      to: move.to,
      currentPlayer: player,
    );
    
    final opponent = player == PieceType.black ? PieceType.red : PieceType.black;
    final opponentCaptures = rules.getAllMovesForPlayer(result.board, opponent, true);
    
    // Check if the destination square can be captured
    return opponentCaptures.entries.any((entry) => 
      entry.value.any((dest) => dest.row == move.to.row && dest.col == move.to.col));
  }

  // Generate all successor states with proper multi-jump handling
  List<MapEntry<AIMove, BitboardState>> _getSuccessorStates(
    BitboardState board,
    PieceType playerToMove,
    {bool capturesOnly = false}
  ) {
    List<MapEntry<AIMove, BitboardState>> successors = [];
    
    final moveOpportunities = capturesOnly 
        ? rules.getAllMovesForPlayer(board, playerToMove, true)
        : rules.getAllMovesForPlayer(board, playerToMove, false);

    for (final entry in moveOpportunities.entries) {
      final fromPos = entry.key;
      final destinations = entry.value;
      
      for (final toPos in destinations) {
        final isJumpMove = (toPos.row - fromPos.row).abs() >= 2 || 
                          (toPos.col - fromPos.col).abs() >= 2;

        if (capturesOnly && !isJumpMove) continue;

        // Execute the complete move sequence (including multi-jumps)
        final finalBoard = _executeCompleteMove(board, fromPos, toPos, playerToMove);
        
        successors.add(MapEntry(
          AIMove(from: fromPos, to: toPos, score: 0, isJump: isJumpMove),
          finalBoard,
        ));
      }
    }
    
    return successors;
  }

  // Execute a complete move including all mandatory multi-jumps
  BitboardState _executeCompleteMove(BitboardState board, BoardPosition from, BoardPosition to, PieceType player) {
    var currentBoard = board.copy();
    var currentPos = from;
    var targetPos = to;
    
    while (true) {
      final result = rules.applyMoveAndGetResult(
        currentBoard: currentBoard,
        from: currentPos,
        to: targetPos,
        currentPlayer: player,
      );
      
      currentBoard = result.board;
      currentPos = targetPos;
      
      // If turn changed, no more jumps available
      if (result.turnChanged) break;
      
      // Check for further jumps
      final piece = currentBoard.getPieceAt(currentPos.row, currentPos.col);
      if (piece != null) {
        final furtherJumps = rules.getFurtherJumps(currentPos, piece, currentBoard);
        if (furtherJumps.isNotEmpty) {
          targetPos = furtherJumps.first; // Take first available jump
        } else {
          break;
        }
      } else {
        break;
      }
    }
    
    return currentBoard;
  }

  // Quiescence search to handle tactical sequences
  double _quiescenceSearch(BitboardState board, int depth, double alpha, double beta, 
                          bool isMaximizingPlayer, PieceType aiPlayerType) {
    final standPatScore = _evaluateBoard(board, aiPlayerType);
    
    if (isMaximizingPlayer) {
      if (standPatScore >= beta) return standPatScore;
      alpha = max(alpha, standPatScore);
    } else {
      if (standPatScore <= alpha) return standPatScore;
      beta = min(beta, standPatScore);
    }
    
    if (depth <= 0) return standPatScore;
    
    final currentPlayer = isMaximizingPlayer ? aiPlayerType 
        : (aiPlayerType == PieceType.black ? PieceType.red : PieceType.black);
    
    // Only search captures in quiescence
    final captureStates = _getSuccessorStates(board, currentPlayer, capturesOnly: true);
    if (captureStates.isEmpty) return standPatScore;
    
    // Sort captures by value
    captureStates.sort((a, b) => _compareMoves(a.key, b.key, board, currentPlayer));
    
    if (isMaximizingPlayer) {
      double maxEval = standPatScore;
      for (final entry in captureStates.take(5)) { // Limit search width
        final eval = _quiescenceSearch(entry.value, depth - 1, alpha, beta, false, aiPlayerType);
        maxEval = max(maxEval, eval);
        alpha = max(alpha, eval);
        if (beta <= alpha) break; // Alpha-beta cutoff
      }
      return maxEval;
    } else {
      double minEval = standPatScore;
      for (final entry in captureStates.take(5)) { // Limit search width
        final eval = _quiescenceSearch(entry.value, depth - 1, alpha, beta, true, aiPlayerType);
        minEval = min(minEval, eval);
        beta = min(beta, eval);
        if (beta <= alpha) break; // Alpha-beta cutoff
      }
      return minEval;
    }
  }

  // Main minimax search with alpha-beta pruning
  double _minimax(BitboardState board, int depth, double alpha, double beta, 
                 bool isMaximizingPlayer, PieceType aiPlayerType) {
    
    // Check transposition table
    final boardHash = _getBoardHash(board, aiPlayerType, depth);
    if (_transpositionTable.containsKey(boardHash)) {
      return _transpositionTable[boardHash]!;
    }

    // Base case: leaf node
    if (depth == 0) {
      final score = _quiescenceSearch(board, quiescenceSearchDepth, alpha, beta, isMaximizingPlayer, aiPlayerType);
      _transpositionTable[boardHash] = score;
      return score;
    }

    final currentPlayer = isMaximizingPlayer ? aiPlayerType 
        : (aiPlayerType == PieceType.black ? PieceType.red : PieceType.black);

    final childStates = _getSuccessorStates(board, currentPlayer);
    
    // Terminal position check
    if (childStates.isEmpty) {
      final score = isMaximizingPlayer ? -30000.0 + depth : 30000.0 - depth;
      _transpositionTable[boardHash] = score;
      return score;
    }

    // Sort moves for better alpha-beta pruning
    childStates.sort((a, b) => _compareMoves(a.key, b.key, board, currentPlayer));

    double bestScore;
    if (isMaximizingPlayer) {
      bestScore = -double.infinity;
      for (final entry in childStates) {
        final eval = _minimax(entry.value, depth - 1, alpha, beta, false, aiPlayerType);
        bestScore = max(bestScore, eval);
        alpha = max(alpha, eval);
        
        if (beta <= alpha) {
          // Update history table for move that caused cutoff
          final moveKey = '${entry.key.from.row},${entry.key.from.col}-${entry.key.to.row},${entry.key.to.col}';
          _historyTable[moveKey] = (_historyTable[moveKey] ?? 0) + depth;
          break; // Alpha-beta cutoff
        }
      }
    } else {
      bestScore = double.infinity;
      for (final entry in childStates) {
        final eval = _minimax(entry.value, depth - 1, alpha, beta, true, aiPlayerType);
        bestScore = min(bestScore, eval);
        beta = min(beta, eval);
        
        if (beta <= alpha) {
          // Update history table for move that caused cutoff
          final moveKey = '${entry.key.from.row},${entry.key.from.col}-${entry.key.to.row},${entry.key.to.col}';
          _historyTable[moveKey] = (_historyTable[moveKey] ?? 0) + depth;
          break; // Alpha-beta cutoff
        }
      }
    }

    // Store in transposition table
    _transpositionTable[boardHash] = bestScore;
    return bestScore;
  }

  // Main entry point for finding the best move
  AIMove? findBestMove(BitboardState currentBoard, PieceType aiPlayerType) {
    _clearTablesIfNeeded();
    
    AIMove? bestMove;
    final searchDepth = _getSearchDepth(currentBoard);
    double bestScore = -double.infinity;
    
    final stopwatch = Stopwatch()..start();
    const int maxTimeMs = 2000; // 2 second time limit
    const int minDepth = 4;
    
    final initialEval = _evaluateBoard(currentBoard, aiPlayerType);
    developer.log('🔍 Initial board evaluation: $initialEval for $aiPlayerType', name: 'CheckersAI');
    
    // Iterative deepening search
    for (int depth = 1; depth <= searchDepth; depth++) {
      if (stopwatch.elapsedMilliseconds > maxTimeMs && depth > minDepth) {
        developer.log('⏰ Time limit reached at depth $depth', name: 'CheckersAI');
        break;
      }
      
      final moves = _getSuccessorStates(currentBoard, aiPlayerType);
      if (moves.isEmpty) {
        developer.log('❌ No moves available', name: 'CheckersAI');
        return null;
      }
      
      // Sort moves for better search order
      moves.sort((a, b) => _compareMoves(a.key, b.key, currentBoard, aiPlayerType));
      
      double iterBestScore = -double.infinity;
      AIMove? iterBestMove;
      
      developer.log('📊 Depth $depth: Evaluating ${moves.length} moves', name: 'CheckersAI');
      
      for (final entry in moves) {
        final score = _minimax(entry.value, depth - 1, -double.infinity, double.infinity, false, aiPlayerType);
        
        if (score > iterBestScore) {
          iterBestScore = score;
          iterBestMove = entry.key;
        }
      }
      
      if (iterBestMove != null) {
        bestMove = AIMove(
          from: iterBestMove.from,
          to: iterBestMove.to,
          score: iterBestScore.clamp(-10000, 10000),
          isJump: iterBestMove.isJump,
        );
        bestScore = iterBestScore;
        
        developer.log('✅ Depth $depth best: ${bestMove.from} → ${bestMove.to}, score: $bestScore', name: 'CheckersAI');
        
        // If we found a winning move, no need to search deeper
        if (bestScore > 25000) {
          developer.log('🏆 Winning move found, stopping search', name: 'CheckersAI');
          break;
        }
      }
    }
    
    stopwatch.stop();
    
    if (bestMove != null) {
      final pieceCount = popCount(currentBoard.blackMen | currentBoard.blackKings | 
                                 currentBoard.redMen | currentBoard.redKings);
      developer.log(
        '🎯 Final Decision: ${bestMove.from} → ${bestMove.to}, '
        'Score: $bestScore, Pieces: $pieceCount, Time: ${stopwatch.elapsedMilliseconds}ms, '
        'IsJump: ${bestMove.isJump}',
        name: 'CheckersAI',
      );
    }
    
    return bestMove;
  }
}