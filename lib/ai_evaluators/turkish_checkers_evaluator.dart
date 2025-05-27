import 'dart:developer' as developer;
import 'dart:math';
import '../models/piece_model.dart';
import '../models/bitboard_state.dart' hide rcToIndex, indexToCol, indexToRow;
import '../utils/bit_utils.dart';
import '../game_rules/game_rules.dart';
import 'board_evaluator.dart';

/// Fast Turkish Checkers evaluator optimized for opening play
class TurkishCheckersEvaluator implements BoardEvaluator {
  // Piece values in centipawns
  static const int _manValue = 100;
  static const int _kingValue = 280;

  // Evaluation weights (optimized for speed)
  static const int _promotionThreatEg = 120;
  static const int _captureBonus = 20;
  static const int _advancementBonus = 6;
  static const int _mobilityBonus = 3;
  static const int _centerBonus = 8;

  // Bitboard masks (precomputed)
  static const int _blackPromotionRank = 0xFF00000000000000; // Rank 7
  static const int _redPromotionRank = 0x00000000000000FF;   // Rank 0
  static const int _centerSquares = 0x0000001818000000;      // Central 4 squares
  static const int _extendedCenter = 0x00003C3C3C0000;       // Extended center
  static const int _blackBackRank = 0x00000000000000FF;      // Black's back rank
  static const int _redBackRank = 0xFF00000000000000;        // Red's back rank

  // Precomputed rank values for advancement scoring
  static const List<int> _rankValues = [0, 2, 4, 6, 10, 15, 25, 40];

  // Debug flag
  static const bool _enableDebug = false;
  
  // Maximum iterations to prevent infinite loops
  static const int _maxIterations = 64;

  // Fast mobility evaluation
  int _fastMobility(int aiPieces, int oppPieces, int emptySquares) {
    var aiMobility = 0;
    var oppMobility = 0;
    
    // Count adjacent empty squares for each piece (simplified mobility)
    var pieces = aiPieces;
    var iterations = 0;
    while (pieces != 0 && iterations < _maxIterations) {
      final sq = lsbIndex(pieces);
      if (sq < 0) break;
      pieces = clearBit(pieces, sq);
      aiMobility += _countAdjacentEmpty(sq, emptySquares);
      iterations++;
    }
    
    pieces = oppPieces;
    iterations = 0;
    while (pieces != 0 && iterations < _maxIterations) {
      final sq = lsbIndex(pieces);
      if (sq < 0) break;
      pieces = clearBit(pieces, sq);
      oppMobility += _countAdjacentEmpty(sq, emptySquares);
      iterations++;
    }
    
    return aiMobility - oppMobility;
  }

  // Count empty adjacent squares
  int _countAdjacentEmpty(int sq, int emptySquares) {
    final r = sq ~/ 8, c = sq % 8;
    var count = 0;
    
    const dirs = [[-1, 0], [1, 0], [0, -1], [0, 1]];
    for (final dir in dirs) {
      final nr = r + dir[0], nc = c + dir[1];
      if (nr >= 0 && nr < 8 && nc >= 0 && nc < 8) {
        final adjSq = nr * 8 + nc;
        if (isSet(emptySquares, adjSq)) count++;
      }
    }
    
    return count;
  }

  // King activity evaluation
  int _evaluateKingActivity(int aiKings, int oppKings, bool isBlack) {
    var score = 0;
    
    // Centralization bonus
    score += popCount(aiKings & _centerSquares) * 20;
    score -= popCount(oppKings & _centerSquares) * 20;
    
    // Activity bonus (not on back rank)
    final aiBackRank = isBlack ? _blackBackRank : _redBackRank;
    final oppBackRank = isBlack ? _redBackRank : _blackBackRank;
    
    score += popCount(aiKings & ~aiBackRank) * 15;
    score -= popCount(oppKings & ~oppBackRank) * 15;
    
    return score;
  }
  

  @override
  double evaluate({
    required BitboardState board,
    required PieceType aiPlayerType,
    required GameRules rules,
  }) {
    final isBlack = aiPlayerType == PieceType.black;
    final aiMen = isBlack ? board.blackMen : board.redMen;
    final aiKings = isBlack ? board.blackKings : board.redKings;
    final oppMen = isBlack ? board.redMen : board.blackMen;
    final oppKings = isBlack ? board.redKings : board.blackKings;

    final aiPieces = aiMen | aiKings;
    final oppPieces = oppMen | oppKings;

    // Quick termination check
    if (aiPieces == 0) return oppPieces == 0 ? 0 : -32000;
    if (oppPieces == 0) return 32000;

    final totalPieces = popCount(aiPieces | oppPieces);
    
    // Fast evaluation for opening positions (> 24 pieces)
    if (totalPieces > 24) {
      return _fastOpeningEval(aiMen, aiKings, oppMen, oppKings, isBlack);
    }
    
    // Detailed evaluation for middlegame/endgame
    return _detailedEval(board, aiMen, aiKings, oppMen, oppKings, isBlack, totalPieces, rules);
  }

  // Ultra-fast evaluation for opening positions
  double _fastOpeningEval(int aiMen, int aiKings, int oppMen, int oppKings, bool isBlack) {
    // Material count
    final aiMenCount = popCount(aiMen);
    final aiKingCount = popCount(aiKings);
    final oppMenCount = popCount(oppMen);
    final oppKingCount = popCount(oppKings);
    
    var score = (aiMenCount - oppMenCount) * _manValue + 
                (aiKingCount - oppKingCount) * _kingValue;

    // Quick positional bonuses
    // Center control
    final aiCenter = popCount((aiMen | aiKings) & _centerSquares);
    final oppCenter = popCount((oppMen | oppKings) & _centerSquares);
    score += (aiCenter - oppCenter) * _centerBonus;

    // Development bonus (pieces off back rank)
    final aiBackRank = isBlack ? _blackBackRank : _redBackRank;
    final aiDeveloped = aiMenCount - popCount(aiMen & aiBackRank);
    final oppBackRank = isBlack ? _redBackRank : _blackBackRank;
    final oppDeveloped = oppMenCount - popCount(oppMen & oppBackRank);
    score += (aiDeveloped - oppDeveloped) * 8;

    // Simple advancement scoring
    score += _fastAdvancement(aiMen, isBlack) - _fastAdvancement(oppMen, !isBlack);

    return score.toDouble().clamp(-500.0, 500.0);
  }

  // Fast advancement calculation using bitboard operations
  int _fastAdvancement(int men, bool isBlack) {
    var score = 0;
    var pieces = men;
    
    for (int rank = 0; rank < 8 && pieces != 0; rank++) {
      final rankMask = isBlack ? 
          (0xFF << (rank * 8)) : 
          (0xFF << ((7 - rank) * 8));
      final rankPieces = popCount(pieces & rankMask);
      score += rankPieces * _rankValues[rank];
      pieces &= ~rankMask; // Remove processed rank
    }
    
    return score;
  }

  // Detailed evaluation for middlegame/endgame
  double _detailedEval(BitboardState board, int aiMen, int aiKings, int oppMen, int oppKings, 
                      bool isBlack, int totalPieces, GameRules rules) {
    final aiPieces = aiMen | aiKings;
    final oppPieces = oppMen | oppKings;
    
    // Material evaluation
    var score = (popCount(aiMen) - popCount(oppMen)) * _manValue + 
                (popCount(aiKings) - popCount(oppKings)) * _kingValue;

    final isEndgame = totalPieces <= 12;

    // Promotion threats (important in endgame)
    if (isEndgame || totalPieces <= 20) {
      final promotionThreat = _evaluatePromotionThreats(oppMen, isBlack);
      score -= promotionThreat * _promotionThreatEg ~/ 100;
    }

    // Captures (always important but computed efficiently)
    final captureScore = _evaluateCaptures(aiPieces, oppPieces, board, isBlack ? PieceType.black : PieceType.red, rules);
    score += captureScore * _captureBonus ~/ 10;

    // Position evaluation
    final advancementScore = _fastAdvancement(aiMen, isBlack) - _fastAdvancement(oppMen, !isBlack);
    score += advancementScore * _advancementBonus ~/ 10;

    // Center control
    final centerScore = popCount(aiPieces & _extendedCenter) - popCount(oppPieces & _extendedCenter);
    score += centerScore * _centerBonus;

    // King activity (endgame)
    if (isEndgame && (popCount(aiKings) > 0 || popCount(oppKings) > 0)) {
      final kingActivity = _evaluateKingActivity(aiKings, oppKings, isBlack);
      score += kingActivity;
    }

    // Mobility (simplified)
    if (totalPieces <= 16) {
      final mobilityScore = _fastMobility(aiPieces, oppPieces, board.allEmptySquares);
      score += mobilityScore * _mobilityBonus;
    }

    final maxScore = isEndgame ? 5000 : 1000;
    return score.toDouble().clamp(-maxScore.toDouble(), maxScore.toDouble());
  }

  // Fast promotion threat evaluation
  int _evaluatePromotionThreats(int oppMen, bool isBlack) {
    var threat = 0;
    
    // Check pieces close to promotion
    for (int rank = 5; rank < 8; rank++) {
      final rankMask = isBlack ? 
          (0xFF << (rank * 8)) : 
          (0xFF << ((7 - rank) * 8));
      final threateningPieces = popCount(oppMen & rankMask);
      threat += threateningPieces * (rank == 7 ? 80 : rank == 6 ? 40 : 20);
    }
    
    return threat;
  }

  // FIXED: Added proper loop termination and error handling
  int _evaluateCaptures(int aiPieces, int oppPieces, BitboardState board, PieceType aiType, GameRules rules) {
    var score = 0;
    
    // Quick capture threat assessment for AI pieces
    var pieces = aiPieces;
    var iterations = 0;
    while (pieces != 0 && iterations < _maxIterations) {
      final sq = lsbIndex(pieces);
      if (sq < 0 || sq >= 64) break; // Additional bounds check
      
      pieces = clearBit(pieces, sq);
      score += _countQuickCaptures(sq, board.allEmptySquares, oppPieces);
      iterations++;
    }
    
    // Subtract opponent captures
    pieces = oppPieces;
    iterations = 0;
    while (pieces != 0 && iterations < _maxIterations) {
      final sq = lsbIndex(pieces);
      if (sq < 0 || sq >= 64) break; // Additional bounds check
      
      pieces = clearBit(pieces, sq);
      score -= _countQuickCaptures(sq, board.allEmptySquares, aiPieces);
      iterations++;
    }
    
    // Bonus for multi-jump potential (with safe error handling)
    try {
      final aiCaptures = rules.getAllMovesForPlayer(board, aiType, true);
      for (final entry in aiCaptures.entries) {
        final destinations = entry.value;
        if (destinations.length > 1) {
          score += 10 * (destinations.length - 1);
        }
      }
    } catch (e) {
      // Log error but don't crash the evaluation
      if (_enableDebug) {
        developer.log('Error in capture evaluation: $e');
      }
    }
    
    return score;
  }

  // Very fast capture counting
  int _countQuickCaptures(int sq, int emptySquares, int targets) {
    // Bounds check
    if (sq < 0 || sq >= 64) return 0;
    
    final r = sq ~/ 8, c = sq % 8;
    var captures = 0;
    
    // Check 4 directions for captures
    const dirs = [[-1, 0], [1, 0], [0, -1], [0, 1]];
    for (final dir in dirs) {
      final tr = r + dir[0], tc = c + dir[1];
      if (tr >= 0 && tr < 8 && tc >= 0 && tc < 8) {
        final targetSq = tr * 8 + tc;
        if (isSet(targets, targetSq)) {
          final jr = tr + dir[0], jc = tc + dir[1];
          if (jr >= 0 && jr < 8 && jc >= 0 && jc < 8) {
            final jumpSq = jr * 8 + jc;
            if (isSet(emptySquares, jumpSq)) {
              captures++;
            }
          }
        }
      }
    }
    
    return captures;  
  }
}