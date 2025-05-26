// lib/ai_evaluators/turkish_checkers_evaluator.dart
import 'dart:math';
import 'dart:developer' as developer;
import '../models/piece_model.dart';
import '../models/bitboard_state.dart' hide rcToIndex, indexToCol, indexToRow;
import '../utils/bit_utils.dart';
import '../game_rules/game_rules.dart';
import 'board_evaluator.dart';

/// Optimized Turkish Dama evaluator with reduced logging and improved performance
class TurkishCheckersEvaluator implements BoardEvaluator {
  // Piece values in centipawns
  static const int _manMg = 100, _manEg = 120;
  static const int _kingMg = 300, _kingEg = 350;
  
  // Evaluation weights with middlegame/endgame tapering
  static const int _mobilityMg = 4, _mobilityEg = 8;
  static const int _threatMg = 12, _threatEg = 15;
  static const int _defenseMg = 6, _defensEg = 4;
  
  // Precomputed tables
  static final List<int> _centerBonus = _initCenterTable();
  static final List<int> _promotionBonus = [0, 5, 12, 22, 35, 52, 72, 0];
  static final List<int> _kingCentralization = _initKingTable();
  
  // Bitboard masks for fast evaluation
  static const int _edgeMask = 0xFF818181818181FF;
  
  // Add debug flag to control logging
  static const bool _enableDebug = false;
  
  static List<int> _initCenterTable() {
    final table = List<int>.filled(64, 0);
    for (int sq = 0; sq < 64; sq++) {
      final r = sq ~/ 8, c = sq % 8;
      final centerDist = max((r - 3.5).abs(), (c - 3.5).abs());
      table[sq] = (20 - (centerDist * 4)).round().clamp(0, 20);
    }
    return table;
  }
  
  static List<int> _initKingTable() {
    final table = List<int>.filled(64, 0);
    for (int sq = 0; sq < 64; sq++) {
      final r = sq ~/ 8, c = sq % 8;
      table[sq] = ((7 - (r - 3.5).abs()) + (7 - (c - 3.5).abs())).round();
    }
    return table;
  }

  @override
  double evaluate({
    required BitboardState board,
    required PieceType aiPlayerType,
    required GameRules rules,
  }) {
    if (_enableDebug) {
      developer.log('🔍 Starting evaluation for ${aiPlayerType.toString()}');
    }
    
    final isBlack = aiPlayerType == PieceType.black;
    final aiMen = isBlack ? board.blackMen : board.redMen;
    final aiKings = isBlack ? board.blackKings : board.redKings;
    final oppMen = isBlack ? board.redMen : board.blackMen;
    final oppKings = isBlack ? board.redKings : board.blackKings;
    
    final aiPieces = aiMen | aiKings;
    final oppPieces = oppMen | oppKings;
    
    // Fast termination check
    if (aiPieces == 0) {
      return oppPieces == 0 ? 0 : -32000;
    }
    if (oppPieces == 0) {
      return 32000;
    }
    
    final pieceCount = popCount(aiPieces | oppPieces);
    final phase = _calculatePhase(pieceCount);
    
    var mgScore = 0, egScore = 0;
    
    // Material and positional evaluation
    final scores = _EvaluationScores();
    _evaluatePieces(aiMen, _manMg, _manEg, true, isBlack, scores);
    _evaluatePieces(aiKings, _kingMg, _kingEg, false, isBlack, scores);
    _evaluatePieces(oppMen, -_manMg, -_manEg, true, !isBlack, scores);
    _evaluatePieces(oppKings, -_kingMg, -_kingEg, false, !isBlack, scores);
    
    mgScore = scores.mg;
    egScore = scores.eg;
    
    // Lazy evaluation threshold
    final materialImbalance = (mgScore + egScore) ~/ 2;
    if (materialImbalance.abs() > 150 && pieceCount > 8) {
      final lazyScore = _taperScore(mgScore, egScore, phase);
      if (_enableDebug) {
        developer.log('⚡ Lazy evaluation: $lazyScore');
      }
      return lazyScore.toDouble();
    }
    
    // Mobility evaluation (simplified)
    final mobility = _evaluateMobilityFast(board, aiPlayerType, aiPieces, oppPieces);
    mgScore += mobility * _mobilityMg ~/ 10;
    egScore += mobility * _mobilityEg ~/ 10;
    
    // Threat evaluation (simplified)
    final threats = _evaluateThreatsFast(board, aiPlayerType, rules, aiPieces, oppPieces);
    mgScore += threats * _threatMg ~/ 10;
    egScore += threats * _threatEg ~/ 10;
    
    // King safety
    if (pieceCount <= 12) {
      final kingSafety = _evaluateKingSafety(aiKings, oppKings, aiPieces, oppPieces);
      mgScore += kingSafety * _defenseMg ~/ 10;
      egScore += kingSafety * _defensEg ~/ 10;
    }
    
    final finalScore = _taperScore(mgScore, egScore, phase);
    if (_enableDebug) {
      developer.log('✅ Final score: $finalScore');
    }
    return finalScore.toDouble();
  }
  
  void _evaluatePieces(int pieceBB, int mgVal, int egVal, bool isMan, bool isBlackPiece, 
                      _EvaluationScores scores) {
    if (pieceBB == 0) return;
    
    var pieces = pieceBB;
    var safetyCounter = 0; // Prevent infinite loops
    
    while (pieces != 0 && safetyCounter < 32) {
      final sq = lsbIndex(pieces);
      if (sq < 0 || sq >= 64) break;
      
      pieces = clearBit(pieces, sq);
      safetyCounter++;
      
      scores.mg += mgVal;
      scores.eg += egVal;
      
      if (isMan) {
        // Promotion incentive
        final rank = isBlackPiece ? sq ~/ 8 : 7 - (sq ~/ 8);
        if (rank >= 0 && rank < _promotionBonus.length) {
          scores.mg += _promotionBonus[rank];
          scores.eg += _promotionBonus[rank];
        }
      } else {
        // King centralization
        if (sq < _kingCentralization.length) {
          scores.mg += _kingCentralization[sq];
          scores.eg += _kingCentralization[sq] * 2;
        }
      }
      
      // Center control bonus
      if (sq < _centerBonus.length) {
        scores.mg += _centerBonus[sq];
        scores.eg += _centerBonus[sq] ~/ 2;
      }
    }
  }
  
  // Simplified mobility evaluation for performance
  int _evaluateMobilityFast(BitboardState board, PieceType aiType, int aiPieces, int oppPieces) {
    var mobility = 0;
    final empty = board.allEmptySquares;
    
    // Count AI mobility
    mobility += _countPieceMobility(aiPieces, aiType, empty, board);
    
    // Subtract opponent mobility
    final oppType = aiType == PieceType.black ? PieceType.red : PieceType.black;
    mobility -= _countPieceMobility(oppPieces, oppType, empty, board);
    
    return mobility;
  }
  
  int _countPieceMobility(int pieces, PieceType type, int empty, BitboardState board) {
    var mobility = 0;
    var pieceBB = pieces;
    var safetyCounter = 0;
    
    while (pieceBB != 0 && safetyCounter < 32) {
      final sq = lsbIndex(pieceBB);
      if (sq < 0 || sq >= 64) break;
      
      pieceBB = clearBit(pieceBB, sq);
      safetyCounter++;
      
      mobility += _countMovesSimple(sq, type, empty, board);
    }
    
    return mobility;
  }
  
  int _countMovesSimple(int sq, PieceType type, int empty, BitboardState board) {
    if (sq < 0 || sq >= 64) return 0;
    
    final r = sq ~/ 8, c = sq % 8;
    var moves = 0;
    
    final isKing = (type == PieceType.black) 
        ? isSet(board.blackKings, sq) 
        : isSet(board.redKings, sq);
    
    if (isKing) {
      // King moves like rook - simplified check
      const dirs = [[-1,0], [1,0], [0,-1], [0,1]];
      for (final dir in dirs) {
        for (int i = 1; i < 8; i++) {
          final nr = r + dir[0] * i, nc = c + dir[1] * i;
          if (nr < 0 || nr > 7 || nc < 0 || nc > 7) break;
          final targetSq = nr * 8 + nc;
          if (targetSq < 0 || targetSq >= 64 || !isSet(empty, targetSq)) break;
          moves++;
        }
      }
    } else {
      // Man moves - simplified
      final forward = type == PieceType.black ? 1 : -1;
      final dirs = [[forward, 0], [0, -1], [0, 1]];
      for (final dir in dirs) {
        final nr = r + dir[0], nc = c + dir[1];
        if (nr >= 0 && nr < 8 && nc >= 0 && nc < 8) {
          final targetSq = nr * 8 + nc;
          if (targetSq >= 0 && targetSq < 64 && isSet(empty, targetSq)) {
            moves++;
          }
        }
      }
    }
    
    return moves;
  }
  
  // Simplified threat evaluation
  int _evaluateThreatsFast(BitboardState board, PieceType aiType, GameRules rules,
                          int aiPieces, int oppPieces) {
    var threats = 0;
    
    // Simple heuristic: count pieces that can potentially capture
    // This avoids expensive move generation
    threats += _countThreateningPieces(aiPieces, aiType, board, true);
    threats -= _countThreateningPieces(oppPieces, 
        aiType == PieceType.black ? PieceType.red : PieceType.black, board, false);
    
    return threats;
  }
  
  int _countThreateningPieces(int pieces, PieceType type, BitboardState board, bool isAI) {
    var threats = 0;
    var pieceBB = pieces;
    var safetyCounter = 0;
    
    while (pieceBB != 0 && safetyCounter < 32) {
      final sq = lsbIndex(pieceBB);
      if (sq < 0 || sq >= 64) break;
      
      pieceBB = clearBit(pieceBB, sq);
      safetyCounter++;
      
      final isKing = (type == PieceType.black) 
          ? isSet(board.blackKings, sq) 
          : isSet(board.redKings, sq);
      
      // Simple threat estimation based on position
      final r = sq ~/ 8, c = sq % 8;
      if (isKing) {
        threats += 15; // Kings are generally more threatening
      } else {
        threats += 10; // Regular pieces
        // Bonus for advanced pieces
        final advancedRank = type == PieceType.black ? r : 7 - r;
        if (advancedRank > 4) threats += 5;
      }
    }
    
    return threats;
  }
  
  int _evaluateKingSafety(int aiKings, int oppKings, int aiPieces, int oppPieces) {
    var safety = 0;
    
    // AI king safety
    var kings = aiKings;
    var safetyCounter = 0;
    while (kings != 0 && safetyCounter < 32) {
      final sq = lsbIndex(kings);
      if (sq < 0 || sq >= 64) break;
      
      kings = clearBit(kings, sq);
      safetyCounter++;
      
      safety += _countAdjacentAllies(sq, aiPieces) * 5;
      if (isSet(_edgeMask, sq)) safety += 3;
    }
    
    // Opponent king safety
    kings = oppKings;
    safetyCounter = 0;
    while (kings != 0 && safetyCounter < 32) {
      final sq = lsbIndex(kings);
      if (sq < 0 || sq >= 64) break;
      
      kings = clearBit(kings, sq);
      safetyCounter++;
      
      safety -= _countAdjacentAllies(sq, oppPieces) * 5;
      if (isSet(_edgeMask, sq)) safety -= 3;
    }
    
    return safety;
  }
  
  int _countAdjacentAllies(int sq, int allies) {
    final r = sq ~/ 8, c = sq % 8;
    var count = 0;
    
    const dirs = [[-1,0], [1,0], [0,-1], [0,1]];
    for (final dir in dirs) {
      final nr = r + dir[0], nc = c + dir[1];
      if (nr >= 0 && nr < 8 && nc >= 0 && nc < 8 && isSet(allies, nr * 8 + nc)) {
        count++;
      }
    }
    return count;
  }
  
  int _calculatePhase(int pieceCount) {
    const maxPieces = 24;
    final phase = (pieceCount * 256) ~/ maxPieces;
    return phase.clamp(0, 256);
  }
  
  int _taperScore(int mg, int eg, int phase) {
    return ((mg * phase) + (eg * (256 - phase))) ~/ 256;
  }
}

// Helper class for passing scores by reference
class _EvaluationScores {
  int mg = 0;
  int eg = 0;
}