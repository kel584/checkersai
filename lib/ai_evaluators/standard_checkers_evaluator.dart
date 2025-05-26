// lib/ai_evaluators/standard_checkers_evaluator.dart
import 'dart:math';
import '../models/piece_model.dart';
import '../models/bitboard_state.dart';
import '../utils/bit_utils.dart'; // For isSet, rcToIndex, indexToRow, indexToCol
import '../game_rules/game_rules.dart';
import 'board_evaluator.dart';

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

    double materialScore = _calculateMaterial(board, aiPlayerType, opponentPlayerType);
    double pstAndPromotionScore = _calculatePstAndPromotion(board, aiPlayerType, opponentPlayerType);
    double mobilityScore = _calculateMobility(board, aiPlayerType, opponentPlayerType, rules);
    double keySquaresScore = _calculateKeySquareControl(board, aiPlayerType, opponentPlayerType);
    double defenseScore = _calculateDefenseStructure(board, aiPlayerType, opponentPlayerType, rules);
    double structureScore = _calculatePieceStructure(board, aiPlayerType, opponentPlayerType);

    double totalScore = 0;
    totalScore += materialScore * _wMaterial;
    totalScore += pstAndPromotionScore * _wPstAndPromotion;
    totalScore += mobilityScore * _wMobility;
    totalScore += keySquaresScore * _wKeySquareControl;
    totalScore += defenseScore * _wDefense;
    totalScore += structureScore * _wStructure;
    
    return totalScore;
  }

  // --- Helper Evaluation Functions ---

  double _calculateMaterial(BitboardState board, PieceType aiPlayerType, PieceType opponentPlayerType) {
    double score = 0;
    // Count pieces using bit population count (popcount) if available, or iterate.
    // For simplicity, iterating here. A popcount utility would be faster.
    int aiMen = 0, aiKings = 0, opponentMen = 0, opponentKings = 0;

    for (int i = 0; i < 64; i++) {
      if (isSet(board.blackMen, i)) (aiPlayerType == PieceType.black ? aiMen++ : opponentMen++);
      else if (isSet(board.blackKings, i)) (aiPlayerType == PieceType.black ? aiKings++ : opponentKings++);
      else if (isSet(board.redMen, i)) (aiPlayerType == PieceType.red ? aiMen++ : opponentMen++);
      else if (isSet(board.redKings, i)) (aiPlayerType == PieceType.red ? aiKings++ : opponentKings++);
    }
    score = (aiMen * _manMaterialValue + aiKings * _kingMaterialValue) -
            (opponentMen * _manMaterialValue + opponentKings * _kingMaterialValue);
    return score;
  }

  double _calculatePstAndPromotion(BitboardState board, PieceType aiPlayerType, PieceType opponentPlayerType) {
    double score = 0;
    for (int i = 0; i < 64; i++) {
      int r = indexToRow(i);
      int c = indexToCol(i);

      if ((r + c) % 2 == 0) continue; // Skip light squares for standard checkers PST

      Piece? piece = board.getPieceAt(r,c); // Uses the helper from BitboardState

      if (piece != null) {
        double pstValue;
        if (piece.isKing) {
          pstValue = _kingPst[r][c];
        } else { // Man
          // PST is from Black's perspective (advancing 0->7)
          // If current piece is Black, use r directly.
          // If current piece is Red, flip r for PST lookup (Red advances 7->0)
          pstValue = (piece.type == PieceType.black) ? _manPst[r][c] : _manPst[7 - r][c];
        }
        
        if (piece.type == aiPlayerType) {
          score += pstValue;
        } else if (piece.type == opponentPlayerType) {
          score -= pstValue;
        }
      }
    }
    return score;
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

  double _calculateKeySquareControl(BitboardState board, PieceType aiPlayerType, PieceType opponentPlayerType) {
    double score = 0;
    // Center dark squares for standard 8x8 board
    // (2,3), (2,5), (3,2), (3,4), (4,3), (4,5), (5,2), (5,4) using 0-indexed.
    // Simplified to just 4 main center squares for now:
    final List<BoardPosition> keyCenterDarkSquares = [
      BoardPosition(3, 2), BoardPosition(3, 4), // Assuming (0,0) is top-left
      BoardPosition(4, 3), BoardPosition(4, 5),
    ];
    const double centerBonusFactor = 1.0; // Scaled by _wKeySquares

    for (final pos in keyCenterDarkSquares) {
      final piece = board.getPieceAt(pos.row, pos.col);
      if (piece != null) {
        double value = piece.isKing ? 1.5 : 1.0; // Kings control center better
        if (piece.type == aiPlayerType) score += value * centerBonusFactor;
        else if (piece.type == opponentPlayerType) score -= value * centerBonusFactor;
      }
    }
    return score;
  }

double _calculateDefenseStructure(
    BitboardState board,
    PieceType aiPlayerType,
    PieceType opponentPlayerType,
    GameRules rules, // Passed in case helpers need it (e.g., _isPieceAttackedByOpponentStd)
  ) {
    double totalDefenseScore = 0;

    // Iterate through all squares to find pieces
    for (int i = 0; i < 64; i++) {
      int r = indexToRow(i);
      int c = indexToCol(i);

      // For standard checkers, only evaluate pieces on dark squares
      if (rules.piecesOnDarkSquaresOnly && (r + c) % 2 == 0) {
        continue; // Skip light squares
      }

      Piece? piece = board.getPieceAt(r, c); // Uses BitboardState.getPieceAt

      if (piece != null) {
        BoardPosition currentPos = BoardPosition(r, c);
        double pieceScoreContribution = 0;

        bool isDefended = _isPieceDefendedByFriendlyStd(board, currentPos, piece);
        bool isAttacked = _isPieceAttackedByOpponentStd(
            board, currentPos, (piece.type == aiPlayerType ? opponentPlayerType : aiPlayerType), rules);

        if (piece.type == aiPlayerType) {
          // AI's piece
          if (isDefended) {
            pieceScoreContribution += piece.isKing ? _kingDefendedBonus : _manDefendedBonus;
          }
          if (isAttacked) {
            // If AI's piece is attacked
            pieceScoreContribution += isDefended ? _attackedButDefendedPenalty : _attackedAndUndefendedPenalty;
          }
        } else {
          // Opponent's piece (scoring from AI's perspective)
          if (isDefended) {
            // If opponent's piece is defended, it's slightly worse for AI
            pieceScoreContribution -= piece.isKing ? _kingDefendedBonus * 0.8 : _manDefendedBonus * 0.8; // Factor < 1
          }
          if (isAttacked) {
            // If AI is attacking an opponent's piece (good for AI)
            // The penalties are negative, so subtracting a negative becomes positive
            pieceScoreContribution -= isDefended ? _attackedButDefendedPenalty * 0.8 : _attackedAndUndefendedPenalty;
          }
        }
        totalDefenseScore += pieceScoreContribution;
      }
    }
    return totalDefenseScore; // This score will then be multiplied by _wDefense in the main evaluate method
  }
  
  // Helper for _calculateDefenseStructure
  bool _isPieceDefendedByFriendlyStd(BitboardState board, BoardPosition piecePos, Piece piece) {
    int r = piecePos.row;
    int c = piecePos.col;
    // For men, check two diagonal squares behind it. Kings, any adjacent friendly.
    if (!piece.isKing) {
      int behindRow = r - piece.moveDirection; // piece.moveDirection is +1 for Black, -1 for Red
      if ((_isValidPosition(behindRow, c - 1) && board.getPieceAt(behindRow, c - 1)?.type == piece.type) ||
          (_isValidPosition(behindRow, c + 1) && board.getPieceAt(behindRow, c + 1)?.type == piece.type)) {
        return true;
      }
    } else { // King
      const List<List<int>> DIRS = [[-1,-1],[-1,1],[1,-1],[1,1]];
      for(var d in DIRS){
          if(_isValidPosition(r+d[0], c+d[1]) && board.getPieceAt(r+d[0], c+d[1])?.type == piece.type) {
              return true;
          }
      }
    }
    return false;
  }

  // Helper for _calculateDefenseStructure
bool _isPieceAttackedByOpponentStd(
    BitboardState board,
    BoardPosition targetPos, // The position of the piece we are checking
    // Piece targetPiece, // Details of targetPiece are not strictly needed if we only care about its position and type for validation
    PieceType attackerType, // The type of the opponent (e.g., if target is Red, attackerType is Black)
    GameRules rules // The GameRules object to call getJumpMoves
  ) {
    // Iterate over all squares to find potential attackers of 'attackerType'
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        // For standard checkers, attackers will be on dark squares
        if (rules.piecesOnDarkSquaresOnly && (r + c) % 2 == 0) {
          continue; // Skip light squares
        }

        Piece? attacker = board.getPieceAt(r, c); // Use BitboardState.getPieceAt

        if (attacker != null && attacker.type == attackerType) {
          BoardPosition attackerPos = BoardPosition(r, c);
          
          // Get all *single-step* jump moves for this specific opponent piece
          // The 'rules.getJumpMoves' should be the bitboard-aware version from StandardCheckersRules
          Set<BoardPosition> jumps = rules.getJumpMoves(attackerPos, attacker, board); 
          
          for (final landingPos in jumps) {
            // For a standard checkers jump, the captured piece is at the midpoint.
            // A jump always changes row and col by 2.
            if ((attackerPos.row - landingPos.row).abs() == 2 && 
                (attackerPos.col - landingPos.col).abs() == 2) {
              
              int jumpedR = (attackerPos.row + landingPos.row) ~/ 2;
              int jumpedC = (attackerPos.col + landingPos.col) ~/ 2;

              if (jumpedR == targetPos.row && jumpedC == targetPos.col) {
                // The piece at targetPos is the one being jumped by this attacker's move
                return true; 
              }
            }
          }
        }
      }
    }
    return false; // No opponent piece found that can immediately jump the target piece
  }

double _calculatePieceStructure(BitboardState board, PieceType aiPlayerType, PieceType opponentPlayerType) {
    double score = 0;
    const double edgeManPenalty = -0.5;   // Men on edges are less good (increased penalty slightly)
    const double backRankManBonus = 0.3; 

    for (int i = 0; i < 64; i++) { // Iterate all squares
        int r = indexToRow(i);
        int c = indexToCol(i);
        Piece? piece = board.getPieceAt(r,c);

        if(piece != null) {
            double pieceScore = 0;
            if (!piece.isKing) { // For men
                if (c == 0 || c == 7) { // Men on side edges
                    pieceScore += edgeManPenalty;
                }
                // Back rank defense (Black on row 0/1, Red on row 7/6 - from their starting side)
                // This definition of "back rank" should be relative to their own side, not kinging side.
                if (piece.type == PieceType.black && (r == 0 || r == 1)) pieceScore += backRankManBonus;
                if (piece.type == PieceType.red && (r == 7 || r == 6)) pieceScore += backRankManBonus;
            } else {
                // You could add king-specific structure bonuses/penalties here if desired
            }

            if (piece.type == aiPlayerType) score += pieceScore;
            else score -= pieceScore; // If opponent has bad structure, it's good for AI
        }
    }
    return score;
  }
}