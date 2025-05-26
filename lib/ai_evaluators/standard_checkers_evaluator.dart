// lib/ai_evaluators/standard_checkers_evaluator.dart
import 'dart:math';
import '../models/piece_model.dart';
import '../models/bitboard_state.dart' hide indexToRow, indexToCol, rcToIndex;
import '../utils/bit_utils.dart'; // For isSet, rcToIndex, indexToRow, indexToCol
import '../game_rules/game_rules.dart';
import 'board_evaluator.dart';

  // Data class to hold results from single board pass
  class _BoardAnalysisData {
    double materialScore = 0;
    double pstScore = 0;
    double keySquaresScore = 0;
    double defenseScore = 0;
    double structureScore = 0;
  }

class StandardCheckersEvaluator implements BoardEvaluator {
  // --- Material Values ---
  static const double _manMaterialValue = 100.0;
  static const double _kingMaterialValue = 280.0; // Kings are strong

  // --- Evaluation Weights (CRITICAL - Needs Tuning!) ---
  static const double _wMaterial = 1.0;
  static const double _wPstAndPromotion = 0.15; // PSTs inherently include promotion proximity
  static const double _wMobility = 0.3;
  static const double _wKeySquareControl = 0.2;
  static const double _wDefense = 0.25;
  static const double _wStructure = 0.1; // e.g., edge penalties, formations

  static const double _manDefendedBonus = 0.5;
  static const double _kingDefendedBonus = 0.7;
  static const double _attackedButDefendedPenalty = -1.0; // e.g., if piece is attacked but has a supporter
  static const double _attackedAndUndefendedPenalty = -2.5; // More severe if attacked and no support

  // --- Piece-Square Tables (PSTs) for Standard Checkers ---
  // Values for dark squares. Assumes Black moves from top (row 0) towards bottom (row 7).
  // Red moves from bottom (row 7) towards top (row 0).
  // Table is defined from Black's perspective (advancing means increasing row index).
  // We will flip for Red's perspective when accessing.
  static const List<List<double>> _manPst = [
    // Row 0 (Red's king row / Black's start relative)
    [0.0, 4.0, 0.0, 3.0, 0.0, 3.0, 0.0, 4.0],
    // Row 1
    [3.0, 0.0, 2.0, 0.0, 2.0, 0.0, 2.0, 0.0],
    // Row 2
    [0.0, 2.0, 0.0, 1.0, 0.0, 1.0, 0.0, 3.0],
    // Row 3
    [1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0],
    // Row 4
    [0.0, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5],
    // Row 5
    [0.5, 0.0, 0.3, 0.0, 0.3, 0.0, 0.5, 0.0],
    // Row 6 (Penultimate for Black)
    [0.0, 1.0, 0.0, 1.5, 0.0, 1.5, 0.0, 0.0],
    // Row 7 (Black's king row - high promotion bonus incorporated here)
    [15.0, 0.0, 15.0, 0.0, 15.0, 0.0, 15.0, 0.0], // Bonus for being on king row
  ];

  

  static const List<List<double>> _kingPst = [ // Kings value central dark squares
    [0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0],
    [1.0, 0.0, 1.5, 0.0, 1.5, 0.0, 1.0, 0.0],
    [0.0, 1.5, 0.0, 2.0, 0.0, 2.0, 0.0, 1.0],
    [1.0, 0.0, 2.0, 0.0, 2.5, 0.0, 1.5, 0.0], // Central dark squares
    [0.0, 1.5, 0.0, 2.5, 0.0, 2.0, 0.0, 1.0],
    [1.0, 0.0, 2.0, 0.0, 2.0, 0.0, 1.5, 0.0],
    [0.0, 1.0, 0.0, 1.5, 0.0, 1.5, 0.0, 1.0],
    [1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0],
  ];

  // Pre-computed center squares for key square control
  static const List<BoardPosition> _keyCenterDarkSquares = [
    BoardPosition(3, 2), BoardPosition(3, 4),
    BoardPosition(4, 3), BoardPosition(4, 5),
  ];

  // Pre-computed diagonal directions for optimization
  static const List<List<int>> _diagonalDirs = [[-1,-1],[-1,1],[1,-1],[1,1]];

  bool _isValidPosition(int r, int c) { // Local helper, or use a shared one
    return r >= 0 && r < 8 && c >= 0 && c < 8;
  }

  // --- Main Evaluation Method ---
  @override
  double evaluate({
    required BitboardState board,
    required PieceType aiPlayerType,
    required GameRules rules, // rules object passed for context if helpers need it
  }) {
    PieceType opponentPlayerType = (aiPlayerType == PieceType.red) ? PieceType.black : PieceType.red;

    // Single pass through board for most calculations
    final boardData = _analyzeBoardInSinglePass(board, aiPlayerType, opponentPlayerType, rules);
    
    double materialScore = boardData.materialScore;
    double pstAndPromotionScore = boardData.pstScore;
    double keySquaresScore = boardData.keySquaresScore;
    double defenseScore = boardData.defenseScore;
    double structureScore = boardData.structureScore;
    
    // Only calculate mobility if weight is significant (expensive operation)
    double mobilityScore = 0;
    if (_wMobility > 0.01) {
      mobilityScore = _calculateMobility(board, aiPlayerType, opponentPlayerType, rules);
    }

    double totalScore = 0;
    totalScore += materialScore * _wMaterial;
    totalScore += pstAndPromotionScore * _wPstAndPromotion;
    totalScore += mobilityScore * _wMobility;
    totalScore += keySquaresScore * _wKeySquareControl;
    totalScore += defenseScore * _wDefense;
    totalScore += structureScore * _wStructure;
    
    return totalScore;
  }



  // Single pass through board to calculate most metrics
  _BoardAnalysisData _analyzeBoardInSinglePass(
    BitboardState board, 
    PieceType aiPlayerType, 
    PieceType opponentPlayerType,
    GameRules rules
  ) {
    final data = _BoardAnalysisData();
    
    // Pre-cache key center positions for faster lookup
    final Set<int> keyCenterIndices = _keyCenterDarkSquares
        .map((pos) => pos.row * 8 + pos.col)
        .toSet();
    
    // Iterate only through dark squares (more efficient for standard checkers)
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        // Skip light squares for standard checkers
        if ((r + c) % 2 == 0) continue;
        
        Piece? piece = board.getPieceAt(r, c);
        if (piece == null) continue;
        
        final isAiPiece = piece.type == aiPlayerType;
        final multiplier = isAiPiece ? 1.0 : -1.0;
        final currentPos = BoardPosition(r, c);
        final squareIndex = r * 8 + c;
        
        // Material calculation
        if (piece.isKing) {
          data.materialScore += _kingMaterialValue * multiplier;
        } else {
          data.materialScore += _manMaterialValue * multiplier;
        }
        
        // PST calculation
        double pstValue;
        if (piece.isKing) {
          pstValue = _kingPst[r][c];
        } else {
          pstValue = (piece.type == PieceType.black) ? _manPst[r][c] : _manPst[7 - r][c];
        }
        data.pstScore += pstValue * multiplier;
        
        // Key square control (only check pre-computed center squares)
        if (keyCenterIndices.contains(squareIndex)) {
          double centerValue = piece.isKing ? 1.5 : 1.0;
          data.keySquaresScore += centerValue * multiplier;
        }
        
        // Defense structure calculation (inline for efficiency)
        double defenseContribution = 0;
        bool isDefended = _isPieceDefendedByFriendlyStd(board, currentPos, piece);
        bool isAttacked = _isPieceAttackedByOpponentStd(
            board, currentPos, isAiPiece ? opponentPlayerType : aiPlayerType, rules);
        
        if (isAiPiece) {
          if (isDefended) {
            defenseContribution += piece.isKing ? _kingDefendedBonus : _manDefendedBonus;
          }
          if (isAttacked) {
            defenseContribution += isDefended ? _attackedButDefendedPenalty : _attackedAndUndefendedPenalty;
          }
        } else {
          if (isDefended) {
            defenseContribution -= piece.isKing ? _kingDefendedBonus * 0.8 : _manDefendedBonus * 0.8;
          }
          if (isAttacked) {
            defenseContribution -= isDefended ? _attackedButDefendedPenalty * 0.8 : _attackedAndUndefendedPenalty;
          }
        }
        data.defenseScore += defenseContribution;
        
        // Structure calculation (inline for efficiency)
        if (!piece.isKing) {
          double structureContribution = 0;
          
          // Edge penalty for men
          if (c == 0 || c == 7) {
            structureContribution -= 0.5;
          }
          
          // Back rank bonus
          if ((piece.type == PieceType.black && (r == 0 || r == 1)) ||
              (piece.type == PieceType.red && (r == 7 || r == 6))) {
            structureContribution += 0.3;
          }
          
          data.structureScore += structureContribution * multiplier;
        }
      }
    }
    
    return data;
  }

  double _calculateMobility(BitboardState board, PieceType aiPlayerType, PieceType opponentPlayerType, GameRules rules) {
    // For an accurate score, this would call rules.getAllMovesForPlayer for both players.
    // This can be expensive. A "quick move count" is faster if getAllMovesForPlayer is slow.
    // Let's assume rules.getAllMovesForPlayer is efficient enough or we accept the cost.
    
    Map<BoardPosition, Set<BoardPosition>> aiMovesMap = rules.getAllMovesForPlayer(board, aiPlayerType, false);
    Map<BoardPosition, Set<BoardPosition>> opponentMovesMap = rules.getAllMovesForPlayer(board, opponentPlayerType, false);

    int aiTotalMoves = 0;
    aiMovesMap.forEach((_, moves) => aiTotalMoves += moves.length);

    int opponentTotalMoves = 0;
    opponentMovesMap.forEach((_, moves) => opponentTotalMoves += moves.length);

    return (aiTotalMoves - opponentTotalMoves).toDouble();
  }

  // Helper for defense calculation - optimized with early returns
  bool _isPieceDefendedByFriendlyStd(BitboardState board, BoardPosition piecePos, Piece piece) {
    int r = piecePos.row;
    int c = piecePos.col;
    
    if (!piece.isKing) {
      // For men, check two diagonal squares behind it
      int behindRow = r - piece.moveDirection;
      return ((_isValidPosition(behindRow, c - 1) && board.getPieceAt(behindRow, c - 1)?.type == piece.type) ||
              (_isValidPosition(behindRow, c + 1) && board.getPieceAt(behindRow, c + 1)?.type == piece.type));
    } else {
      // King - check all four diagonal directions
      for (final dir in _diagonalDirs) {
        int newR = r + dir[0];
        int newC = c + dir[1];
        if (_isValidPosition(newR, newC) && board.getPieceAt(newR, newC)?.type == piece.type) {
          return true;
        }
      }
      return false;
    }
  }

  // Helper for defense calculation - optimized with reduced scope
  bool _isPieceAttackedByOpponentStd(
    BitboardState board,
    BoardPosition targetPos,
    PieceType attackerType,
    GameRules rules
  ) {
    // Only check squares that could potentially attack the target
    // For checkers, attackers must be within 2 squares diagonally
    final targetR = targetPos.row;
    final targetC = targetPos.col;
    
    // Check potential attacker positions (within 2 diagonal squares)
    for (final dir in _diagonalDirs) {
      int attackerR = targetR + (dir[0] * 2);
      int attackerC = targetC + (dir[1] * 2);
      
      if (!_isValidPosition(attackerR, attackerC)) continue;
      if ((attackerR + attackerC) % 2 == 0) continue; // Skip light squares
      
      Piece? attacker = board.getPieceAt(attackerR, attackerC);
      if (attacker == null || attacker.type != attackerType) continue;
      
      BoardPosition attackerPos = BoardPosition(attackerR, attackerC);
      Set<BoardPosition> jumps = rules.getJumpMoves(attackerPos, attacker, board);
      
      // Check if any jump lands such that it captures the target
      for (final landingPos in jumps) {
        if ((attackerPos.row - landingPos.row).abs() == 2 && 
            (attackerPos.col - landingPos.col).abs() == 2) {
          
          int jumpedR = (attackerPos.row + landingPos.row) ~/ 2;
          int jumpedC = (attackerPos.col + landingPos.col) ~/ 2;

          if (jumpedR == targetR && jumpedC == targetC) {
            return true;
          }
        }
      }
    }
    return false;
  }
}