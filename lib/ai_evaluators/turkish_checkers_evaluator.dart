// lib/ai_evaluators/turkish_checkers_evaluator.dart
import 'dart:math';
import 'dart:developer' as developer;
import '../models/piece_model.dart';
import '../models/bitboard_state.dart' hide rcToIndex, indexToCol, indexToRow;
import '../utils/bit_utils.dart';
import '../game_rules/game_rules.dart';
import 'board_evaluator.dart';

// Lightweight performance tracking - only for critical operations
class _PerformanceTracker {
  static int _totalEvaluations = 0;
  static int _totalScanTime = 0;
  static int _totalMobilityTime = 0;
  static final Stopwatch _globalTimer = Stopwatch();
  
  static void startEvaluation() {
    _totalEvaluations++;
    _globalTimer.start();
  }
  
  static void endEvaluation() {
    _globalTimer.stop();
    if (_totalEvaluations % 1000 == 0) {
      print('Evaluations: $_totalEvaluations, Avg time: ${_globalTimer.elapsedMicroseconds ~/ _totalEvaluations}μs');
    }
  }
  
  static void reset() {
    _totalEvaluations = 0;
    _totalScanTime = 0;
    _totalMobilityTime = 0;
    _globalTimer.reset();
  }
}

// Compact board analysis data
class _BoardData {
  final double materialScore;
  final double keySquareScore;
  final double promotionScore;
  final double clusteringScore;
  final int totalPieces;
  final int aiMen;
  final int aiKings;
  final int opponentMen;
  final int opponentKings;
  final int aiMenBB;
  final int aiKingsBB;
  final int opponentMenBB;
  final int opponentKingsBB;
  final int allAiPiecesBB;
  final int allOpponentPiecesBB;

  const _BoardData({
    required this.materialScore,
    required this.keySquareScore,
    required this.promotionScore,
    required this.clusteringScore,
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
  // Material values
  static const double _manValue = 100.0;
  static const double _kingValue = 300.0;

  // Evaluation weights - simplified and optimized
  static const double _wMaterial = 1.0;
  static const double _wMobility = 0.4;
  static const double _wKeySquares = 0.15;
  static const double _wPromotion = 0.25;
  static const double _wDefense = 0.2;
  static const double _wClustering = 0.1;
  static const double _wThreatDetection = 1.2;
  static const double _wKingCentralization = 0.3;
  static const double _wEndgameKingAdvantage = 50.0;

  // Precomputed lookup tables for fast evaluation
  static final List<double> _centerSquareValues = _precomputeCenterValues();
  static final List<double> _promotionBonuses = [0.0, 4.0, 8.0, 15.0, 25.0, 40.0, 65.0, 0.0];
  static final List<double> _centralizationValues = _precomputeCentralization();

  // Precompute center square values
  static List<double> _precomputeCenterValues() {
    final values = List<double>.filled(64, 0.0);
    // Center squares (3,3), (3,4), (4,3), (4,4)
    const centerIndices = [27, 28, 35, 36];
    const extendedCenter = [18, 19, 20, 21, 26, 29, 34, 37, 42, 43, 44, 45];
    
    for (final idx in centerIndices) {
      values[idx] = 1.0;
    }
    for (final idx in extendedCenter) {
      values[idx] = 0.5;
    }
    return values;
  }

  // Precompute centralization values
  static List<double> _precomputeCentralization() {
    final values = List<double>.filled(64, 0.0);
    for (int i = 0; i < 64; i++) {
      final r = i ~/ 8;
      final c = i % 8;
      values[i] = (3.5 - (r - 3.5).abs()) + (3.5 - (c - 3.5).abs());
    }
    return values;
  }

  // Fast inline checks
  static bool _isValidPosition(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;

  // Optimized board scanning with minimal allocations
  _BoardData _scanBoard(BitboardState board, PieceType aiPlayerType, PieceType opponentPlayerType) {
    double materialScore = 0;
    double keySquareScore = 0;
    double promotionScore = 0;
    double clusteringScore = 0;

    final bool aiIsBlack = aiPlayerType == PieceType.black;
    
    final int aiMenBB = aiIsBlack ? board.blackMen : board.redMen;
    final int aiKingsBB = aiIsBlack ? board.blackKings : board.redKings;
    final int opponentMenBB = aiIsBlack ? board.redMen : board.blackMen;
    final int opponentKingsBB = aiIsBlack ? board.redKings : board.blackKings;

    final int allAiPiecesBB = aiMenBB | aiKingsBB;
    final int allOpponentPiecesBB = opponentMenBB | opponentKingsBB;

    // Count pieces and calculate scores in single pass
    int aiMen = 0, aiKings = 0, opponentMen = 0, opponentKings = 0;

    // Process AI Men - safe loop with counter
    int tempAiMen = aiMenBB;
    int counter = 0;
    while (tempAiMen != 0 && counter < 32) { // Safety counter
      counter++;
      final int index = lsbIndex(tempAiMen);
      if (index < 0 || index >= 64) break; // Safety check
      
      aiMen++;
      materialScore += _manValue;
      keySquareScore += _centerSquareValues[index];
      
      final int r = indexToRow(index);
      final int advancement = aiIsBlack ? r : (7 - r);
      if (advancement >= 0 && advancement < _promotionBonuses.length) {
        promotionScore += _promotionBonuses[advancement];
      }
      
      clusteringScore += _countAdjacentFriendly(index, allAiPiecesBB);
      tempAiMen = clearBit(tempAiMen, index);
    }

    // Process AI Kings - safe loop
    int tempAiKings = aiKingsBB;
    counter = 0;
    while (tempAiKings != 0 && counter < 32) {
      counter++;
      final int index = lsbIndex(tempAiKings);
      if (index < 0 || index >= 64) break;
      
      aiKings++;
      materialScore += _kingValue;
      keySquareScore += _centerSquareValues[index];
      clusteringScore += _countAdjacentFriendly(index, allAiPiecesBB);
      tempAiKings = clearBit(tempAiKings, index);
    }

    // Process Opponent Men - safe loop
    int tempOpponentMen = opponentMenBB;
    counter = 0;
    while (tempOpponentMen != 0 && counter < 32) {
      counter++;
      final int index = lsbIndex(tempOpponentMen);
      if (index < 0 || index >= 64) break;
      
      opponentMen++;
      materialScore -= _manValue;
      keySquareScore -= _centerSquareValues[index];
      
      final int r = indexToRow(index);
      final int advancement = aiIsBlack ? (7 - r) : r;
      if (advancement >= 0 && advancement < _promotionBonuses.length) {
        promotionScore -= _promotionBonuses[advancement];
      }
      
      clusteringScore -= _countAdjacentFriendly(index, allOpponentPiecesBB);
      tempOpponentMen = clearBit(tempOpponentMen, index);
    }

    // Process Opponent Kings - safe loop
    int tempOpponentKings = opponentKingsBB;
    counter = 0;
    while (tempOpponentKings != 0 && counter < 32) {
      counter++;
      final int index = lsbIndex(tempOpponentKings);
      if (index < 0 || index >= 64) break;
      
      opponentKings++;
      materialScore -= _kingValue;
      keySquareScore -= _centerSquareValues[index];
      clusteringScore -= _countAdjacentFriendly(index, allOpponentPiecesBB);
      tempOpponentKings = clearBit(tempOpponentKings, index);
    }

    final int totalPieces = aiMen + aiKings + opponentMen + opponentKings;

    return _BoardData(
      materialScore: materialScore,
      keySquareScore: keySquareScore,
      promotionScore: promotionScore,
      clusteringScore: clusteringScore,
      totalPieces: totalPieces,
      aiMen: aiMen,
      aiKings: aiKings,
      opponentMen: opponentMen,
      opponentKings: opponentKings,
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
    _PerformanceTracker.startEvaluation();
    
    final opponentPlayerType = (aiPlayerType == PieceType.red) ? PieceType.black : PieceType.red;
    final boardData = _scanBoard(board, aiPlayerType, opponentPlayerType);

    // Early termination for game over states
    if (boardData.allAiPiecesBB == 0 && boardData.allOpponentPiecesBB != 0) {
      _PerformanceTracker.endEvaluation();
      return -99999.0;
    }
    if (boardData.allOpponentPiecesBB == 0 && boardData.allAiPiecesBB != 0) {
      _PerformanceTracker.endEvaluation();
      return 99999.0;
    }

    double totalScore = 0;
    final bool isEndgame = boardData.totalPieces <= 10;

    // Core evaluation components
    totalScore += boardData.materialScore * _wMaterial;
    totalScore += boardData.keySquareScore * _wKeySquares;
    totalScore += boardData.promotionScore * _wPromotion;
    totalScore += boardData.clusteringScore * _wClustering;

    // Conditional evaluations based on game state
    if (boardData.totalPieces > 4) {
      final mobilityScore = _calculateFastMobility(board, aiPlayerType, opponentPlayerType, rules, boardData);
      totalScore += mobilityScore * _wMobility;
    }
    
    if (boardData.totalPieces > 6) {
      final defenseScore = _calculateDefense(boardData);
      totalScore += defenseScore * _wDefense;
    }
    
    // Threat detection - always important
    final threatScore = _detectThreats(board, aiPlayerType, opponentPlayerType, rules, boardData);
    totalScore += threatScore * _wThreatDetection;
    
    // King evaluations
    final kingAdvantage = (boardData.aiKings - boardData.opponentKings) * 
        (isEndgame ? _wEndgameKingAdvantage : _wEndgameKingAdvantage * 0.3);
    final kingCentralization = _calculateKingCentralization(boardData.aiKingsBB, boardData.opponentKingsBB) * 
        _wKingCentralization * (isEndgame ? 1.0 : 0.5);
    
    totalScore += kingAdvantage + kingCentralization;

    _PerformanceTracker.endEvaluation();
    return totalScore;
  }

  // Optimized mobility calculation
  double _calculateFastMobility(BitboardState board, PieceType aiPlayerType, 
      PieceType opponentPlayerType, GameRules rules, _BoardData boardData) {
    
    int aiMoves = 0;
    int opponentMoves = 0;
    final int emptySquares = board.allEmptySquares;

    // Count AI moves - optimized loops with safety counters
    int tempAiMen = boardData.aiMenBB;
    int counter = 0;
    while (tempAiMen != 0 && counter < 32) {
      counter++;
      final int index = lsbIndex(tempAiMen);
      if (index < 0 || index >= 64) break;
      
      aiMoves += _countMovesForMan(index, aiPlayerType, emptySquares, board, rules);
      tempAiMen = clearBit(tempAiMen, index);
    }

    int tempAiKings = boardData.aiKingsBB;
    counter = 0;
    while (tempAiKings != 0 && counter < 32) {
      counter++;
      final int index = lsbIndex(tempAiKings);
      if (index < 0 || index >= 64) break;
      
      aiMoves += _countMovesForKing(index, emptySquares, board, rules, aiPlayerType);
      tempAiKings = clearBit(tempAiKings, index);
    }

    // Count opponent moves
    int tempOpponentMen = boardData.opponentMenBB;
    counter = 0;
    while (tempOpponentMen != 0 && counter < 32) {
      counter++;
      final int index = lsbIndex(tempOpponentMen);
      if (index < 0 || index >= 64) break;
      
      opponentMoves += _countMovesForMan(index, opponentPlayerType, emptySquares, board, rules);
      tempOpponentMen = clearBit(tempOpponentMen, index);
    }

    int tempOpponentKings = boardData.opponentKingsBB;
    counter = 0;
    while (tempOpponentKings != 0 && counter < 32) {
      counter++;
      final int index = lsbIndex(tempOpponentKings);
      if (index < 0 || index >= 64) break;
      
      opponentMoves += _countMovesForKing(index, emptySquares, board, rules, opponentPlayerType);
      tempOpponentKings = clearBit(tempOpponentKings, index);
    }

    return (aiMoves - opponentMoves).toDouble();
  }

  // Fast move counting for men
  int _countMovesForMan(int pieceIndex, PieceType pieceType, int emptySquares, BitboardState board, GameRules rules) {
    int moveCount = 0;
    final int r = indexToRow(pieceIndex);
    final int c = indexToCol(pieceIndex);
    
    // Turkish checkers: men move forward and sideways
    final int forwardDir = (pieceType == PieceType.black) ? 1 : -1;
    final List<List<int>> moves = [[forwardDir, 0], [0, -1], [0, 1]];
    
    for (final move in moves) {
      final int nr = r + move[0];
      final int nc = c + move[1];
      if (_isValidPosition(nr, nc) && isSet(emptySquares, rcToIndex(nr, nc))) {
        moveCount++;
      }
    }

    // Add jumps
    try {
      final jumps = rules.getJumpMoves(BoardPosition(r, c), Piece(type: pieceType, isKing: false), board);
      moveCount += jumps.length;
    } catch (e) {
      // Handle potential errors from rules engine
    }

    return moveCount;
  }

  // Fast move counting for kings
  int _countMovesForKing(int pieceIndex, int emptySquares, BitboardState board, GameRules rules, PieceType pieceType) {
    int moveCount = 0;
    final int r = indexToRow(pieceIndex);
    final int c = indexToCol(pieceIndex);
    
    // Turkish Dama King moves like a rook
    const directions = [[-1, 0], [1, 0], [0, -1], [0, 1]];
    for (final dir in directions) {
      for (int i = 1; i < 8; i++) {
        final int nr = r + dir[0] * i;
        final int nc = c + dir[1] * i;
        if (!_isValidPosition(nr, nc)) break;
        
        final int targetIndex = rcToIndex(nr, nc);
        if (!isSet(emptySquares, targetIndex)) break;
        moveCount++;
      }
    }

    // Add jumps
    try {
      final jumps = rules.getJumpMoves(BoardPosition(r, c), Piece(type: pieceType, isKing: true), board);
      moveCount += jumps.length;
    } catch (e) {
      // Handle potential errors from rules engine
    }

    return moveCount;
  }

  // Simplified defense calculation
  double _calculateDefense(_BoardData boardData) {
    double score = 0;
    const double supportBonus = 0.3;

    // AI defense
    int tempAi = boardData.allAiPiecesBB;
    int counter = 0;
    while (tempAi != 0 && counter < 32) {
      counter++;
      final int index = lsbIndex(tempAi);
      if (index < 0 || index >= 64) break;
      
      if (_hasAdjacentAlly(index, boardData.allAiPiecesBB)) {
        score += supportBonus;
      }
      tempAi = clearBit(tempAi, index);
    }

    // Opponent defense
    int tempOpp = boardData.allOpponentPiecesBB;
    counter = 0;
    while (tempOpp != 0 && counter < 32) {
      counter++;
      final int index = lsbIndex(tempOpp);
      if (index < 0 || index >= 64) break;
      
      if (_hasAdjacentAlly(index, boardData.allOpponentPiecesBB)) {
        score -= supportBonus;
      }
      tempOpp = clearBit(tempOpp, index);
    }

    return score;
  }

  // Simplified threat detection
  double _detectThreats(BitboardState board, PieceType aiPlayerType, 
      PieceType opponentPlayerType, GameRules rules, _BoardData boardData) {
    double threatScore = 0;

    // Quick threat analysis using bitboard positions
    int tempAi = boardData.allAiPiecesBB;
    int counter = 0;
    while (tempAi != 0 && counter < 32) {
      counter++;
      final int index = lsbIndex(tempAi);
      if (index < 0 || index >= 64) break;
      
      final int r = indexToRow(index);
      final int c = indexToCol(index);
      final bool isKing = isSet(boardData.aiKingsBB, index);
      
      try {
        final jumps = rules.getJumpMoves(BoardPosition(r, c), Piece(type: aiPlayerType, isKing: isKing), board);
        if (jumps.isNotEmpty) {
          threatScore += jumps.length * (isKing ? 15.0 : 10.0);
        }
      } catch (e) {
        // Handle errors gracefully
      }
      
      tempAi = clearBit(tempAi, index);
    }

    // Opponent threats
    int tempOpp = boardData.allOpponentPiecesBB;
    counter = 0;
    while (tempOpp != 0 && counter < 32) {
      counter++;
      final int index = lsbIndex(tempOpp);
      if (index < 0 || index >= 64) break;
      
      final int r = indexToRow(index);
      final int c = indexToCol(index);
      final bool isKing = isSet(boardData.opponentKingsBB, index);
      
      try {
        final jumps = rules.getJumpMoves(BoardPosition(r, c), Piece(type: opponentPlayerType, isKing: isKing), board);
        if (jumps.isNotEmpty) {
          threatScore -= jumps.length * (isKing ? 15.0 : 10.0);
        }
      } catch (e) {
        // Handle errors gracefully
      }
      
      tempOpp = clearBit(tempOpp, index);
    }

    return threatScore;
  }

  // Fast adjacent ally check
  bool _hasAdjacentAlly(int pieceIndex, int friendlyPiecesBB) {
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

  // Count adjacent friendly pieces
  double _countAdjacentFriendly(int pieceIndex, int friendlyPiecesBB) {
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

  // King centralization calculation
  double _calculateKingCentralization(int aiKingsBB, int opponentKingsBB) {
    double score = 0;
    
    int tempAi = aiKingsBB;
    int counter = 0;
    while (tempAi != 0 && counter < 32) {
      counter++;
      final int index = lsbIndex(tempAi);
      if (index < 0 || index >= 64) break;
      
      score += _centralizationValues[index];
      tempAi = clearBit(tempAi, index);
    }
    
    int tempOpp = opponentKingsBB;
    counter = 0;
    while (tempOpp != 0 && counter < 32) {
      counter++;
      final int index = lsbIndex(tempOpp);
      if (index < 0 || index >= 64) break;
      
      score -= _centralizationValues[index];
      tempOpp = clearBit(tempOpp, index);
    }
    
    return score;
  }

  // Static methods for performance monitoring
  static void logPerformanceStats() {
    print('Total evaluations: ${_PerformanceTracker._totalEvaluations}');
    if (_PerformanceTracker._totalEvaluations > 0) {
      print('Average time per evaluation: ${_PerformanceTracker._globalTimer.elapsedMicroseconds ~/ _PerformanceTracker._totalEvaluations}μs');
    }
  }

  static void resetPerformanceTracking() {
    _PerformanceTracker.reset();
  }

  static Map<String, int> getCallCounts() {
    return {
      'evaluations': _PerformanceTracker._totalEvaluations,
    };
  }
}