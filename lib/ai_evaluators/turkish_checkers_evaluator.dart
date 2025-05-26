// lib/ai_evaluators/turkish_checkers_evaluator.dart
import 'dart:math';
import 'dart:developer' as developer;
import '../models/piece_model.dart';
import '../models/bitboard_state.dart' hide rcToIndex, indexToCol, indexToRow;
import '../utils/bit_utils.dart';
import '../game_rules/game_rules.dart';
import 'board_evaluator.dart';

// Performance tracking class
class _PerformanceTracker {
  static final Map<String, int> _callCounts = {};
  static final Map<String, int> _totalTimes = {};
  static final Map<String, Stopwatch> _activeTimers = {};
  
  static void startTimer(String operation) {
    final stopwatch = Stopwatch()..start();
    _activeTimers[operation] = stopwatch;
    _callCounts[operation] = (_callCounts[operation] ?? 0) + 1;
  }
  
  static void endTimer(String operation) {
    final stopwatch = _activeTimers[operation];
    if (stopwatch != null) {
      stopwatch.stop();
      _totalTimes[operation] = (_totalTimes[operation] ?? 0) + stopwatch.elapsedMicroseconds;
      _activeTimers.remove(operation);
    }
  }
  
  static void logStats() {
    print('\n=== PERFORMANCE STATS ===');
    final sortedEntries = _totalTimes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    for (final entry in sortedEntries) {
      final operation = entry.key;
      final totalTime = entry.value;
      final callCount = _callCounts[operation] ?? 0;
      final avgTime = callCount > 0 ? (totalTime / callCount).round() : 0;
      
      print('$operation: ${totalTime}μs total, $callCount calls, ${avgTime}μs avg');
    }
    print('========================\n');
  }
  
  static void reset() {
    _callCounts.clear();
    _totalTimes.clear();
    _activeTimers.clear();
  }
}

// Data structure to hold board analysis results from _scanBoard
class _BoardData {
  final double materialScore;
  final double keySquareScore;
  final double promotionScore;
  final double clusteringScore;
  final List<BoardPosition> aiPieces;
  final List<BoardPosition> opponentPieces;
  final int totalPieces;
  final int aiMen;
  final int aiKings;
  final int opponentMen;
  final int opponentKings;
  
  // Bitboard references for fast operations
  final int aiMenBB;
  final int aiKingsBB;
  final int opponentMenBB;
  final int opponentKingsBB;
  final int allAiPiecesBB;
  final int allOpponentPiecesBB;

  _BoardData({
    required this.materialScore,
    required this.keySquareScore,
    required this.promotionScore,
    required this.clusteringScore,
    required this.aiPieces,
    required this.opponentPieces,
    required this.totalPieces,
    required this.aiMen,
    required this.aiKings,
    required this.opponentMen,
    required this.opponentKings,
    required this.aiMenBB,
    required this.aiKingsBB,
    required this.opponentMenBB,
    required this.opponentKingsBB,
    required this.allAiPiecesBB,
    required this.allOpponentPiecesBB,
  });
}

class TurkishCheckersEvaluator implements BoardEvaluator {
  // Static counters for method call tracking
  static int _evaluateCallCount = 0;
  static int _scanBoardCallCount = 0;
  static int _mobilityCallCount = 0;
  static int _threatCallCount = 0;
  
  // --- Material Values ---
  static const double _manMaterialBaseValue = 100.0;
  static const double _kingMaterialBaseValue = 300.0;

  // --- Evaluation Weights (Optimized for Turkish Checkers) ---
  static const double _wMaterial = 1.0;
  static const double _wMobility = 0.4;
  static const double _wKeySquares = 0.15;
  static const double _wPromotion = 0.25;
  static const double _wDefense = 0.2;
  static const double _wClustering = 0.1;
  static const double _wThreatDetection = 1.2;
  static const double _wKingActivityAndCentralization = 0.3;
  static const double _wEndgameKingAdvantage = 50.0;

  // Precomputed lookup tables for key squares (0-63 indexed)
  static const Map<int, double> _centerSquareValues = {
    27: 1.0, 28: 1.0, 35: 1.0, 36: 1.0, // Center squares
  };
  
  static const Map<int, double> _extendedCenterValues = {
    18: 0.5, 19: 0.5, 20: 0.5, 21: 0.5, // Extended center
    26: 0.5, 29: 0.5,
    34: 0.5, 37: 0.5,
    42: 0.5, 43: 0.5, 44: 0.5, 45: 0.5,
  };

  // Promotion bonuses based on advancement
  static const List<double> _promotionBonuses = [
    0.0, 4.0, 8.0, 15.0, 25.0, 40.0, 65.0, 0.0
  ];

  // Precomputed centralization values for each square
  static final List<double> _centralizationValues = _precomputeCentralization();

  static List<double> _precomputeCentralization() {
    _PerformanceTracker.startTimer('precompute_centralization');
    final values = List<double>.filled(64, 0.0);
    for (int i = 0; i < 64; i++) {
      final r = i ~/ 8;
      final c = i % 8;
      values[i] = (3.5 - (r - 3.5).abs()) + (3.5 - (c - 3.5).abs());
    }
    _PerformanceTracker.endTimer('precompute_centralization');
    return values;
  }

  // Fast bit operations
  bool _isValidPosition(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;

  // Use the optimized functions from bit_utils.dart
  int _popCount(int n) {
    _PerformanceTracker.startTimer('popcount');
    final result = popCount(n);
    _PerformanceTracker.endTimer('popcount');
    return result;
  }
  
  int _lsbIndex(int bitboard) {
    _PerformanceTracker.startTimer('lsb_index');
    final result = lsbIndexFast(bitboard);
    _PerformanceTracker.endTimer('lsb_index');
    return result;
  }

  _BoardData _scanBoard(BitboardState board, PieceType aiPlayerType, PieceType opponentPlayerType) {
    _PerformanceTracker.startTimer('scan_board_total');
    _scanBoardCallCount++;
    
    print('🔍 SCAN_BOARD #$_scanBoardCallCount - Starting board analysis');
    
    _PerformanceTracker.startTimer('scan_board_init');
    double materialScore = 0;
    double keySquareScore = 0;
    double promotionScore = 0;
    double aiClustering = 0;
    double opponentClustering = 0;

    int currentAiMen = 0, currentAiKings = 0;
    int currentOpponentMen = 0, currentOpponentKings = 0;

    final int aiMenBB = (aiPlayerType == PieceType.black) ? board.blackMen : board.redMen;
    final int aiKingsBB = (aiPlayerType == PieceType.black) ? board.blackKings : board.redKings;
    final int opponentMenBB = (opponentPlayerType == PieceType.black) ? board.blackMen : board.redMen;
    final int opponentKingsBB = (opponentPlayerType == PieceType.black) ? board.blackKings : board.redKings;

    final int allAiPiecesBB = aiMenBB | aiKingsBB;
    final int allOpponentPiecesBB = opponentMenBB | opponentKingsBB;

    final List<BoardPosition> aiPieces = [];
    final List<BoardPosition> opponentPieces = [];
    _PerformanceTracker.endTimer('scan_board_init');

    print('  📊 Bitboards - AI: men=$aiMenBB, kings=$aiKingsBB | Opp: men=$opponentMenBB, kings=$opponentKingsBB');

    // Process AI Men
    _PerformanceTracker.startTimer('scan_ai_men');
    int tempAIMen = aiMenBB;
    int aiMenCount = 0;
    while (tempAIMen != 0) {
      aiMenCount++;
      final int index = _lsbIndex(tempAIMen);
      currentAiMen++;
      materialScore += _manMaterialBaseValue;
      keySquareScore += (_centerSquareValues[index] ?? 0.0) + (_extendedCenterValues[index] ?? 0.0);
      
      final int r = indexToRow(index);
      final int advancement = (aiPlayerType == PieceType.black) ? r : (7 - r);
      if (advancement < _promotionBonuses.length) {
        promotionScore += _promotionBonuses[advancement];
      }
      
      aiClustering += _countAdjacentFriendlyFromBitboard(index, allAiPiecesBB);
      aiPieces.add(BoardPosition(indexToRow(index), indexToCol(index)));
      tempAIMen = clearBit(tempAIMen, index);
    }
    _PerformanceTracker.endTimer('scan_ai_men');
    print('  ♟️ AI Men processed: $aiMenCount pieces');

    // Process AI Kings
    _PerformanceTracker.startTimer('scan_ai_kings');
    int tempAIKings = aiKingsBB;
    int aiKingsCount = 0;
    while (tempAIKings != 0) {
      aiKingsCount++;
      final int index = _lsbIndex(tempAIKings);
      currentAiKings++;
      materialScore += _kingMaterialBaseValue;
      keySquareScore += (_centerSquareValues[index] ?? 0.0) + (_extendedCenterValues[index] ?? 0.0);
      aiClustering += _countAdjacentFriendlyFromBitboard(index, allAiPiecesBB);
      aiPieces.add(BoardPosition(indexToRow(index), indexToCol(index)));
      tempAIKings = clearBit(tempAIKings, index);
    }
    _PerformanceTracker.endTimer('scan_ai_kings');
    print('  ♛ AI Kings processed: $aiKingsCount pieces');

    // Process Opponent Men
    _PerformanceTracker.startTimer('scan_opponent_men');
    int tempOpponentMen = opponentMenBB;
    int oppMenCount = 0;
    while (tempOpponentMen != 0) {
      oppMenCount++;
      final int index = _lsbIndex(tempOpponentMen);
      currentOpponentMen++;
      materialScore -= _manMaterialBaseValue;
      keySquareScore -= (_centerSquareValues[index] ?? 0.0) + (_extendedCenterValues[index] ?? 0.0);
      
      final int r = indexToRow(index);
      final int advancement = (opponentPlayerType == PieceType.black) ? r : (7 - r);
      if (advancement < _promotionBonuses.length) {
        promotionScore -= _promotionBonuses[advancement];
      }
      
      opponentClustering += _countAdjacentFriendlyFromBitboard(index, allOpponentPiecesBB);
      opponentPieces.add(BoardPosition(indexToRow(index), indexToCol(index)));
      tempOpponentMen = clearBit(tempOpponentMen, index);
    }
    _PerformanceTracker.endTimer('scan_opponent_men');
    print('  ♙ Opponent Men processed: $oppMenCount pieces');

    // Process Opponent Kings
    _PerformanceTracker.startTimer('scan_opponent_kings');
    int tempOpponentKings = opponentKingsBB;
    int oppKingsCount = 0;
    while (tempOpponentKings != 0) {
      oppKingsCount++;
      final int index = _lsbIndex(tempOpponentKings);
      currentOpponentKings++;
      materialScore -= _kingMaterialBaseValue;
      keySquareScore -= (_centerSquareValues[index] ?? 0.0) + (_extendedCenterValues[index] ?? 0.0);
      opponentClustering += _countAdjacentFriendlyFromBitboard(index, allOpponentPiecesBB);
      opponentPieces.add(BoardPosition(indexToRow(index), indexToCol(index)));
      tempOpponentKings = clearBit(tempOpponentKings, index);
    }
    _PerformanceTracker.endTimer('scan_opponent_kings');
    print('  ♕ Opponent Kings processed: $oppKingsCount pieces');

    final int totalPieces = currentAiMen + currentAiKings + currentOpponentMen + currentOpponentKings;
    final double clusteringScore = aiClustering - opponentClustering;

    print('  📈 Scores - Material: ${materialScore.toStringAsFixed(1)}, KeySquare: ${keySquareScore.toStringAsFixed(1)}, Promotion: ${promotionScore.toStringAsFixed(1)}, Clustering: ${clusteringScore.toStringAsFixed(1)}');
    print('  🎯 Total pieces: $totalPieces (AI: ${currentAiMen}m+${currentAiKings}k, Opp: ${currentOpponentMen}m+${currentOpponentKings}k)');

    _PerformanceTracker.endTimer('scan_board_total');

    return _BoardData(
      materialScore: materialScore,
      keySquareScore: keySquareScore,
      promotionScore: promotionScore,
      clusteringScore: clusteringScore,
      aiPieces: aiPieces,
      opponentPieces: opponentPieces,
      totalPieces: totalPieces,
      aiMen: currentAiMen,
      aiKings: currentAiKings,
      opponentMen: currentOpponentMen,
      opponentKings: currentOpponentKings,
      aiMenBB: aiMenBB,
      aiKingsBB: aiKingsBB,
      opponentMenBB: opponentMenBB,
      opponentKingsBB: opponentKingsBB,
      allAiPiecesBB: allAiPiecesBB,
      allOpponentPiecesBB: allOpponentPiecesBB,
    );
  }

  @override
  double evaluate({
    required BitboardState board,
    required PieceType aiPlayerType,
    required GameRules rules,
  }) {
    _PerformanceTracker.startTimer('evaluate_total');
    _evaluateCallCount++;
    
    print('\n🤖 EVALUATE #$_evaluateCallCount - Starting evaluation for ${aiPlayerType.name}');
    
    final opponentPlayerType = (aiPlayerType == PieceType.red) ? PieceType.black : PieceType.red;
    final boardData = _scanBoard(board, aiPlayerType, opponentPlayerType);

    // Handle game over states
    if (boardData.allAiPiecesBB == 0 && boardData.allOpponentPiecesBB != 0) {
      print('  💀 AI LOSES - No pieces left');
      _PerformanceTracker.endTimer('evaluate_total');
      return -99999.0;
    }
    if (boardData.allOpponentPiecesBB == 0 && boardData.allAiPiecesBB != 0) {
      print('  🏆 AI WINS - Opponent has no pieces');
      _PerformanceTracker.endTimer('evaluate_total');
      return 99999.0;
    }

    double totalScore = 0;
    
    // Core evaluation components
    _PerformanceTracker.startTimer('core_evaluation');
    final double materialComponent = boardData.materialScore * _wMaterial;
    final double keySquareComponent = boardData.keySquareScore * _wKeySquares;
    final double promotionComponent = boardData.promotionScore * _wPromotion;
    final double clusteringComponent = boardData.clusteringScore * _wClustering;
    
    totalScore += materialComponent;
    totalScore += keySquareComponent;
    totalScore += promotionComponent;
    totalScore += clusteringComponent;
    _PerformanceTracker.endTimer('core_evaluation');
    
    print('  💰 Core components: Material=${materialComponent.toStringAsFixed(1)}, KeySq=${keySquareComponent.toStringAsFixed(1)}, Promo=${promotionComponent.toStringAsFixed(1)}, Cluster=${clusteringComponent.toStringAsFixed(1)}');
    
    final bool isEndgame = boardData.totalPieces <= 10;
    print('  🎮 Game phase: ${isEndgame ? "ENDGAME" : "MIDGAME"} (${boardData.totalPieces} pieces)');

    // Mobility calculation (only when beneficial)
    double mobilityScore = 0;
    if (boardData.totalPieces > 4) {
      _PerformanceTracker.startTimer('mobility_evaluation');
      mobilityScore = _calculateFastMobility(board, aiPlayerType, opponentPlayerType, rules, boardData);
      totalScore += mobilityScore * _wMobility;
      _PerformanceTracker.endTimer('mobility_evaluation');
      print('  🏃 Mobility: ${mobilityScore.toStringAsFixed(1)} (weighted: ${(mobilityScore * _wMobility).toStringAsFixed(1)})');
    } else {
      print('  🏃 Mobility: SKIPPED (too few pieces)');
    }
    
    // Defense calculation (lighter in endgame)
    double defenseScore = 0;
    if (boardData.totalPieces > 6) {
      _PerformanceTracker.startTimer('defense_evaluation');
      defenseScore = _calculateSimplifiedDefense(boardData);
      totalScore += defenseScore * _wDefense;
      _PerformanceTracker.endTimer('defense_evaluation');
      print('  🛡️ Defense: ${defenseScore.toStringAsFixed(1)} (weighted: ${(defenseScore * _wDefense).toStringAsFixed(1)})');
    } else {
      print('  🛡️ Defense: SKIPPED (too few pieces)');
    }
    
    // Threat detection
    _PerformanceTracker.startTimer('threat_evaluation');
    final threatScore = _detectImmediateThreats(board, aiPlayerType, opponentPlayerType, rules);
    totalScore += threatScore * _wThreatDetection;
    _PerformanceTracker.endTimer('threat_evaluation');
    print('  ⚔️ Threats: ${threatScore.toStringAsFixed(1)} (weighted: ${(threatScore * _wThreatDetection).toStringAsFixed(1)})');
    
    // King-specific evaluations
    _PerformanceTracker.startTimer('king_evaluation');
    final kingAdvantage = (boardData.aiKings - boardData.opponentKings) * (isEndgame ? _wEndgameKingAdvantage : _wEndgameKingAdvantage * 0.3);
    final kingCentralization = _calculateKingCentralization(boardData.aiKingsBB, boardData.opponentKingsBB) * _wKingActivityAndCentralization * (isEndgame ? 1.0 : 0.5);
    
    totalScore += kingAdvantage;
    totalScore += kingCentralization;
    _PerformanceTracker.endTimer('king_evaluation');
    
    print('  👑 Kings: Advantage=${kingAdvantage.toStringAsFixed(1)}, Centralization=${kingCentralization.toStringAsFixed(1)}');
    print('  🎯 FINAL SCORE: ${totalScore.toStringAsFixed(2)}');
    
    _PerformanceTracker.endTimer('evaluate_total');
    
    // Log performance stats every 100 evaluations
    if (_evaluateCallCount % 100 == 0) {
      _PerformanceTracker.logStats();
    }
    
    return totalScore;
  }

  double _calculateFastMobility(BitboardState board, PieceType aiPlayerType, 
      PieceType opponentPlayerType, GameRules rules, _BoardData boardData) {
    
    _PerformanceTracker.startTimer('mobility_total');
    _mobilityCallCount++;
    
    print('    🏃 MOBILITY #$_mobilityCallCount - Calculating piece mobility');
    
    int aiTotalMoves = 0;
    int opponentTotalMoves = 0;

    // Count AI moves
    _PerformanceTracker.startTimer('mobility_ai_men');
    int tempAiMen = boardData.aiMenBB;
    int aiMenMoves = 0;
    while (tempAiMen != 0) {
      final int index = _lsbIndex(tempAiMen);
      final moves = _countQuickMovesForPiece(index, Piece(type: aiPlayerType, isKing: false), board, rules);
      aiTotalMoves += moves;
      aiMenMoves += moves;
      tempAiMen = clearBit(tempAiMen, index);
    }
    _PerformanceTracker.endTimer('mobility_ai_men');
    
    _PerformanceTracker.startTimer('mobility_ai_kings');
    int tempAiKings = boardData.aiKingsBB;
    int aiKingsMoves = 0;
    while (tempAiKings != 0) {
      final int index = _lsbIndex(tempAiKings);
      final moves = _countQuickMovesForPiece(index, Piece(type: aiPlayerType, isKing: true), board, rules);
      aiTotalMoves += moves;
      aiKingsMoves += moves;
      tempAiKings = clearBit(tempAiKings, index);
    }
    _PerformanceTracker.endTimer('mobility_ai_kings');
    
    // Count opponent moves
    _PerformanceTracker.startTimer('mobility_opponent_men');
    int tempOpponentMen = boardData.opponentMenBB;
    int oppMenMoves = 0;
    while (tempOpponentMen != 0) {
      final int index = _lsbIndex(tempOpponentMen);
      final moves = _countQuickMovesForPiece(index, Piece(type: opponentPlayerType, isKing: false), board, rules);
      opponentTotalMoves += moves;
      oppMenMoves += moves;
      tempOpponentMen = clearBit(tempOpponentMen, index);
    }
    _PerformanceTracker.endTimer('mobility_opponent_men');
    
    _PerformanceTracker.startTimer('mobility_opponent_kings');
    int tempOpponentKings = boardData.opponentKingsBB;
    int oppKingsMoves = 0;
    while (tempOpponentKings != 0) {
      final int index = _lsbIndex(tempOpponentKings);
      final moves = _countQuickMovesForPiece(index, Piece(type: opponentPlayerType, isKing: true), board, rules);
      opponentTotalMoves += moves;
      oppKingsMoves += moves;
      tempOpponentKings = clearBit(tempOpponentKings, index);
    }
    _PerformanceTracker.endTimer('mobility_opponent_kings');
    
    print('    📊 AI moves: ${aiMenMoves}(men) + ${aiKingsMoves}(kings) = $aiTotalMoves');
    print('    📊 Opponent moves: ${oppMenMoves}(men) + ${oppKingsMoves}(kings) = $opponentTotalMoves');
    print('    📊 Mobility difference: ${aiTotalMoves - opponentTotalMoves}');
    
    _PerformanceTracker.endTimer('mobility_total');
    return (aiTotalMoves - opponentTotalMoves).toDouble();
  }

  int _countQuickMovesForPiece(int pieceIndex, Piece piece, BitboardState board, GameRules rules) {
    _PerformanceTracker.startTimer('count_moves_for_piece');
    
    int moveCount = 0;
    final int r = indexToRow(pieceIndex);
    final int c = indexToCol(pieceIndex);
    final int emptySquares = board.allEmptySquares;

    if (piece.isKing) {
      // Turkish Dama King - moves like a rook
      const directions = [[-1, 0], [1, 0], [0, -1], [0, 1]];
      for (final dir in directions) {
        for (int i = 1; i < 8; i++) {
          final int nr = r + dir[0] * i;
          final int nc = c + dir[1] * i;
          if (!_isValidPosition(nr, nc)) break;
          if (!isSet(emptySquares, rcToIndex(nr, nc))) break;
          moveCount++;
        }
      }
    } else {
      // Man - forward and sideways moves
      final int forwardDir = (piece.type == PieceType.black) ? 1 : -1;
      final manMoveDeltas = [[forwardDir, 0], [0, -1], [0, 1]];
      for (final delta in manMoveDeltas) {
        final int nr = r + delta[0];
        final int nc = c + delta[1];
        if (_isValidPosition(nr, nc) && isSet(emptySquares, rcToIndex(nr, nc))) {
          moveCount++;
        }
      }
    }

    // Add jump possibilities
    _PerformanceTracker.startTimer('get_jump_moves');
    final Set<BoardPosition> jumps = rules.getJumpMoves(BoardPosition(r, c), piece, board);
    moveCount += jumps.length;
    _PerformanceTracker.endTimer('get_jump_moves');

    _PerformanceTracker.endTimer('count_moves_for_piece');
    return moveCount;
  }

  double _calculateSimplifiedDefense(_BoardData boardData) {
    _PerformanceTracker.startTimer('defense_calculation');
    
    double score = 0;
    const double supportBonus = 0.3;
    const double undefendedPenalty = -0.5;
    
    int aiSupported = 0, aiIsolated = 0;
    int oppSupported = 0, oppIsolated = 0;

    // Check AI pieces
    int tempAiPieces = boardData.allAiPiecesBB;
    while (tempAiPieces != 0) {
      final int index = _lsbIndex(tempAiPieces);
      if (_hasAdjacentAllyBitboard(index, boardData.allAiPiecesBB)) {
        score += supportBonus;
        aiSupported++;
      } else {
        score += undefendedPenalty;
        aiIsolated++;
      }
      tempAiPieces = clearBit(tempAiPieces, index);
    }

    // Check Opponent pieces
    int tempOpponentPieces = boardData.allOpponentPiecesBB;
    while (tempOpponentPieces != 0) {
      final int index = _lsbIndex(tempOpponentPieces);
      if (_hasAdjacentAllyBitboard(index, boardData.allOpponentPiecesBB)) {
        score -= supportBonus;
        oppSupported++;
      } else {
        score -= undefendedPenalty;
        oppIsolated++;
      }
      tempOpponentPieces = clearBit(tempOpponentPieces, index);
    }
    
    print('    🛡️ Defense: AI(${aiSupported}sup+${aiIsolated}iso) vs Opp(${oppSupported}sup+${oppIsolated}iso)');
    
    _PerformanceTracker.endTimer('defense_calculation');
    return score;
  }

  bool _hasAdjacentAllyBitboard(int pieceIndex, int friendlyPiecesBB) {
    final int r = indexToRow(pieceIndex);
    final int c = indexToCol(pieceIndex);
    const directions = [[-1, 0], [1, 0], [0, -1], [0, 1]];
    
    for (final d in directions) {
      final int nr = r + d[0];
      final int nc = c + d[1];
      if (_isValidPosition(nr, nc) && isSet(friendlyPiecesBB, rcToIndex(nr, nc))) {
        return true;
      }
    }
    return false;
  }

  double _countAdjacentFriendlyFromBitboard(int pieceIndex, int friendlyPiecesBB) {
    int count = 0;
    final int r = indexToRow(pieceIndex);
    final int c = indexToCol(pieceIndex);
    const directions = [[-1, 0], [1, 0], [0, -1], [0, 1]];
    
    for (final d in directions) {
      final int nr = r + d[0];
      final int nc = c + d[1];
      if (_isValidPosition(nr, nc) && isSet(friendlyPiecesBB, rcToIndex(nr, nc))) {
        count++;
      }
    }
    return count * 0.25;
  }

  double _detectImmediateThreats(BitboardState board, PieceType aiPlayerType, 
      PieceType opponentPlayerType, GameRules rules) {
    _PerformanceTracker.startTimer('threat_detection_total');
    _threatCallCount++;
    
    print('    ⚔️ THREAT_DETECTION #$_threatCallCount - Analyzing immediate threats');
    
    double threatScore = 0;
    int aiThreats = 0;
    int opponentThreats = 0;
    int aiDefended = 0;
    int opponentDefended = 0;

    // Get bitboards for fast lookups
    final int aiMenBB = (aiPlayerType == PieceType.black) ? board.blackMen : board.redMen;
    final int aiKingsBB = (aiPlayerType == PieceType.black) ? board.blackKings : board.redKings;
    final int opponentMenBB = (opponentPlayerType == PieceType.black) ? board.blackMen : board.redMen;
    final int opponentKingsBB = (opponentPlayerType == PieceType.black) ? board.blackKings : board.redKings;
    
    final int allAiPiecesBB = aiMenBB | aiKingsBB;
    final int allOpponentPiecesBB = opponentMenBB | opponentKingsBB;

    _PerformanceTracker.startTimer('analyze_ai_threats');
    // Analyze AI pieces that can capture opponent pieces
    int tempAiPieces = allAiPiecesBB;
    while (tempAiPieces != 0) {
      final int pieceIndex = _lsbIndex(tempAiPieces);
      final int r = indexToRow(pieceIndex);
      final int c = indexToCol(pieceIndex);
      final bool isKing = isSet(aiKingsBB, pieceIndex);
      
      final Piece piece = Piece(type: aiPlayerType, isKing: isKing);
      final Set<BoardPosition> jumpMoves = rules.getJumpMoves(BoardPosition(r, c), piece, board);
      
      if (jumpMoves.isNotEmpty) {
        // This AI piece can capture - count as threat
        aiThreats += jumpMoves.length;
        threatScore += jumpMoves.length * (isKing ? 15.0 : 10.0); // Kings create stronger threats
        
        // Check if the threatening piece is defended
        if (_hasAdjacentAllyBitboard(pieceIndex, allAiPiecesBB)) {
          aiDefended++;
          threatScore += 3.0; // Bonus for defended threatening piece
        }
      }
      
      tempAiPieces = clearBit(tempAiPieces, pieceIndex);
    }
    _PerformanceTracker.endTimer('analyze_ai_threats');

    _PerformanceTracker.startTimer('analyze_opponent_threats');
    // Analyze opponent pieces that threaten AI pieces
    int tempOpponentPieces = allOpponentPiecesBB;
    while (tempOpponentPieces != 0) {
      final int pieceIndex = _lsbIndex(tempOpponentPieces);
      final int r = indexToRow(pieceIndex);
      final int c = indexToCol(pieceIndex);
      final bool isKing = isSet(opponentKingsBB, pieceIndex);
      
      final Piece piece = Piece(type: opponentPlayerType, isKing: isKing);
      final Set<BoardPosition> jumpMoves = rules.getJumpMoves(BoardPosition(r, c), piece, board);
      
      if (jumpMoves.isNotEmpty) {
        // This opponent piece threatens AI - count as negative threat
        opponentThreats += jumpMoves.length;
        threatScore -= jumpMoves.length * (isKing ? 15.0 : 10.0);
        
        // Check if the threatening opponent piece is defended
        if (_hasAdjacentAllyBitboard(pieceIndex, allOpponentPiecesBB)) {
          opponentDefended++;
          threatScore -= 3.0; // Penalty for defended opponent threatening piece
        }
      }
      
      tempOpponentPieces = clearBit(tempOpponentPieces, pieceIndex);
    }
    _PerformanceTracker.endTimer('analyze_opponent_threats');

    _PerformanceTracker.startTimer('analyze_vulnerable_pieces');
    // Additional analysis: Check for undefended valuable pieces
    int aiVulnerable = 0;
    int opponentVulnerable = 0;
    
    // Check AI vulnerable pieces
    int tempAiVulnerable = allAiPiecesBB;
    while (tempAiVulnerable != 0) {
      final int pieceIndex = _lsbIndex(tempAiVulnerable);
      if (!_hasAdjacentAllyBitboard(pieceIndex, allAiPiecesBB)) {
        final bool isKing = isSet(aiKingsBB, pieceIndex);
        if (_canBeAttackedBy(pieceIndex, allOpponentPiecesBB, opponentKingsBB, board)) {
          aiVulnerable++;
          threatScore -= (isKing ? 8.0 : 4.0); // Penalty for vulnerable pieces
        }
      }
      tempAiVulnerable = clearBit(tempAiVulnerable, pieceIndex);
    }
    
    // Check opponent vulnerable pieces
    int tempOpponentVulnerable = allOpponentPiecesBB;
    while (tempOpponentVulnerable != 0) {
      final int pieceIndex = _lsbIndex(tempOpponentVulnerable);
      if (!_hasAdjacentAllyBitboard(pieceIndex, allOpponentPiecesBB)) {
        final bool isKing = isSet(opponentKingsBB, pieceIndex);
        if (_canBeAttackedBy(pieceIndex, allAiPiecesBB, aiKingsBB, board)) {
          opponentVulnerable++;
          threatScore += (isKing ? 8.0 : 4.0); // Bonus for opponent vulnerable pieces
        }
      }
      tempOpponentVulnerable = clearBit(tempOpponentVulnerable, pieceIndex);
    }
    _PerformanceTracker.endTimer('analyze_vulnerable_pieces');

    print('    📊 AI threats: $aiThreats (${aiDefended}def), Opponent threats: $opponentThreats (${opponentDefended}def)');
    print('    🎯 Vulnerable pieces: AI($aiVulnerable), Opponent($opponentVulnerable)');
    print('    ⚡ Total threat score: ${threatScore.toStringAsFixed(1)}');

    _PerformanceTracker.endTimer('threat_detection_total');
    return threatScore;
  }

  bool _canBeAttackedBy(int targetIndex, int attackerPiecesBB, int attackerKingsBB, BitboardState board) {
    final int r = indexToRow(targetIndex);
    final int c = indexToCol(targetIndex);
    
    // Check if any attacker piece can potentially capture this target
    int tempAttackers = attackerPiecesBB;
    while (tempAttackers != 0) {
      final int attackerIndex = _lsbIndex(tempAttackers);
      final int ar = indexToRow(attackerIndex);
      final int ac = indexToCol(attackerIndex);
      final bool isKing = isSet(attackerKingsBB, attackerIndex);
      
      if (isKing) {
        // King can attack in 4 directions
        const directions = [[-1, 0], [1, 0], [0, -1], [0, 1]];
        for (final dir in directions) {
          if (_isInDirection(ar, ac, r, c, dir[0], dir[1]) && 
              _hasDirectPath(ar, ac, r, c, dir[0], dir[1], board)) {
            return true;
          }
        }
      } else {
        // Man can only attack diagonally forward (in Turkish Checkers, men capture forward)
        if ((r - ar).abs() == 1 && (c - ac).abs() == 1) {
          return true;
        }
      }
      
      tempAttackers = clearBit(tempAttackers, attackerIndex);
    }
    
    return false;
  }

  bool _isInDirection(int fromR, int fromC, int toR, int toC, int dirR, int dirC) {
    if (dirR == 0 && dirC == 0) return false;
    
    final int deltaR = toR - fromR;
    final int deltaC = toC - fromC;
    
    if (dirR == 0) {
      return deltaR == 0 && deltaC.sign == dirC;
    } else if (dirC == 0) {
      return deltaC == 0 && deltaR.sign == dirR;
    } else {
      return deltaR.sign == dirR && deltaC.sign == dirC;
    }
  }

  bool _hasDirectPath(int fromR, int fromC, int toR, int toC, int dirR, int dirC, BitboardState board) {
    int checkR = fromR + dirR;
    int checkC = fromC + dirC;
    
    while (checkR != toR || checkC != toC) {
      if (!_isValidPosition(checkR, checkC)) return false;
      if (!isSet(board.allEmptySquares, rcToIndex(checkR, checkC))) return false;
      
      checkR += dirR;
      checkC += dirC;
    }
    
    return true;
  }

  double _calculateKingCentralization(int aiKingsBB, int opponentKingsBB) {
    _PerformanceTracker.startTimer('king_centralization');
    
    double score = 0;
    
    // Calculate AI king centralization
    int tempAiKings = aiKingsBB;
    while (tempAiKings != 0) {
      final int index = _lsbIndex(tempAiKings);
      score += _centralizationValues[index];
      tempAiKings = clearBit(tempAiKings, index);
    }
    
    // Subtract opponent king centralization
    int tempOpponentKings = opponentKingsBB;
    while (tempOpponentKings != 0) {
      final int index = _lsbIndex(tempOpponentKings);
      score -= _centralizationValues[index];
      tempOpponentKings = clearBit(tempOpponentKings, index);
    }
    
    _PerformanceTracker.endTimer('king_centralization');
    return score;
  }

  // Static method to get performance stats
  static void logPerformanceStats() {
    _PerformanceTracker.logStats();
  }

  // Static method to reset performance tracking
  static void resetPerformanceTracking() {
    _PerformanceTracker.reset();
    _evaluateCallCount = 0;
    _scanBoardCallCount = 0;
    _mobilityCallCount = 0;
    _threatCallCount = 0;
  }

  // Static method to get call counts for debugging
  static Map<String, int> getCallCounts() {
    return {
      'evaluate': _evaluateCallCount,
      'scanBoard': _scanBoardCallCount,
      'mobility': _mobilityCallCount,
      'threat': _threatCallCount,
    };
  }
}