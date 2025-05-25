// lib/ai_evaluators/standard_checkers_evaluator.dart
import '../models/piece_model.dart';
import '../game_rules/game_rules.dart'; // For GameRules type
import 'board_evaluator.dart';

class StandardCheckersEvaluator implements BoardEvaluator {
  // --- Constants for Evaluation ---
  static const double _manMaterialValue = 100.0;
  static const double _kingMaterialValue = 250.0; // Kings are strong, but maybe less dominant than Turkish Dama

  // Weights for different evaluation components (these need tuning!)
  static const double _wMaterial = 1.0;
  static const double _wMobility = 2.0; 
  static const double _wKeySquares = 10.0; // Center control
  static const double _wPromotion = 12.0; // Promotion is key
  static const double _wDefense = 6.0;
  static const double _wStructure = 3.0;  // For piece formations/clustering

  // Piece-Square Table for Men (Standard Checkers)
  // Values for dark squares. Assumes Black moves from top (row 0) to bottom (row 7)
  // and Red moves from bottom (row 7) to top (row 0).
  // Only dark squares are relevant for piece positions in standard checkers.
  // This table is structured for Black's perspective (advancing means increasing row index).
  // We will flip for Red.
  static const List<List<double>> _manPst = [
    [0.0, 0.5, 0.0, 0.5, 0.0, 0.5, 0.0, 0.5], // Row 0 (Red's king row)
    [0.5, 0.0, 0.6, 0.0, 0.6, 0.0, 0.6, 0.0], // Row 1
    [0.0, 0.6, 0.0, 0.7, 0.0, 0.7, 0.0, 0.5], // Row 2
    [0.5, 0.0, 0.7, 0.0, 0.8, 0.0, 0.6, 0.0], // Row 3
    [0.0, 0.6, 0.0, 0.8, 0.0, 0.7, 0.0, 0.5], // Row 4
    [0.5, 0.0, 0.7, 0.0, 0.7, 0.0, 0.6, 0.0], // Row 5
    [0.0, 0.6, 0.0, 0.6, 0.0, 0.5, 0.0, 0.5], // Row 6
    [2.0, 0.0, 2.0, 0.0, 2.0, 0.0, 2.0, 0.0], // Row 7 (Black's king row - high promotion bonus)
                                              // Example values, make more valuable towards kinging.
                                              // A value like 2.0 means (PST_bonus / W_PROMOTION) ~ 0.16 if W_PROMOTION is 12.
                                              // Let's make this more direct like the advanced men bonus.
  ];
  // A simpler PST for kings - generally good to be mobile and central, but less about 'advancing'
  static const List<List<double>> _kingPst = [
    [0.5, 0.0, 0.5, 0.0, 0.5, 0.0, 0.5, 0.0],
    [0.0, 0.6, 0.0, 0.6, 0.0, 0.6, 0.0, 0.5],
    [0.5, 0.0, 0.7, 0.0, 0.7, 0.0, 0.6, 0.0],
    [0.0, 0.6, 0.0, 0.8, 0.0, 0.8, 0.0, 0.5],
    [0.5, 0.0, 0.8, 0.0, 0.8, 0.0, 0.6, 0.0],
    [0.0, 0.6, 0.0, 0.7, 0.0, 0.7, 0.0, 0.5],
    [0.5, 0.0, 0.6, 0.0, 0.6, 0.0, 0.5, 0.0],
    [0.0, 0.5, 0.0, 0.5, 0.0, 0.5, 0.0, 0.5],
  ];


  bool _isValidPosition(int r, int c) {
    return r >= 0 && r < 8 && c >= 0 && c < 8;
  }

  // --- Main Evaluation Method ---
  @override
  double evaluate({
    required List<List<Piece?>> board,
    required PieceType aiPlayerType,
    required GameRules rules,
  }) {
    PieceType opponentPlayerType = (aiPlayerType == PieceType.red) ? PieceType.black : PieceType.red;

    double materialScore = _calculateMaterial(board, aiPlayerType, opponentPlayerType);
    double mobilityScore = _calculateMobility(board, aiPlayerType, opponentPlayerType, rules);
    double keySquaresScore = _calculateKeySquareControl(board, aiPlayerType, opponentPlayerType);
    double promotionScore = _calculatePromotionProximity(board, aiPlayerType, opponentPlayerType);
    double defenseScore = _calculateDefenseStructure(board, aiPlayerType, opponentPlayerType, rules);
    double structureScore = _calculatePieceStructure(board, aiPlayerType, opponentPlayerType); // Changed from clustering

    double totalScore = (materialScore * _wMaterial) +
                        (mobilityScore * _wMobility) +
                        (keySquaresScore * _wKeySquares) +
                        (promotionScore * _wPromotion) +
                        (defenseScore * _wDefense) +
                        (structureScore * _wStructure);
    
    return totalScore;
  }

  // --- Helper Evaluation Functions ---

  double _calculateMaterial(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType) {
    double score = 0;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null) {
          double value = piece.isKing ? _kingMaterialValue : _manMaterialValue;
          if (piece.type == aiPlayerType) {
            score += value;
          } else if (piece.type == opponentPlayerType) {
            score -= value;
          }
        }
      }
    }
    return score;
  }

  double _calculateMobility(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType, GameRules rules) {
    Map<BoardPosition, Set<BoardPosition>> aiMovesMap = rules.getAllMovesForPlayer(board, aiPlayerType, false);
    Map<BoardPosition, Set<BoardPosition>> opponentMovesMap = rules.getAllMovesForPlayer(board, opponentPlayerType, false);

    int aiTotalMoves = 0;
    aiMovesMap.forEach((_, moves) => aiTotalMoves += moves.length);

    int opponentTotalMoves = 0;
    opponentMovesMap.forEach((_, moves) => opponentTotalMoves += moves.length);

    return (aiTotalMoves - opponentTotalMoves).toDouble();
  }

  double _calculateKeySquareControl(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType) {
    double score = 0;
    // Key dark squares in standard checkers (center)
    const List<BoardPosition> keyCenterSquares = [
      BoardPosition(3, 2), BoardPosition(3, 4), // (row, col) for dark squares
      BoardPosition(4, 3), BoardPosition(4, 5)
    ];
    // double bonus for king, single for man
    const double kingControlBonus = 1.0;
    const double manControlBonus = 0.5;

    for (final pos in keyCenterSquares) {
      final piece = board[pos.row][pos.col];
      if (piece != null) {
        double bonus = piece.isKing ? kingControlBonus : manControlBonus;
        if (piece.type == aiPlayerType) score += bonus;
        else if (piece.type == opponentPlayerType) score -= bonus;
      }
    }
    // One could also add "double corner" control if pieces are there (0,1), (0,3), (0,5), (0,7) for black if kinging
    return score;
  }

  double _calculatePromotionProximity(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType) {
    double score = 0;
    // Using the _manPst which should have higher values for rows closer to promotion.
    // The weight _wPromotion will scale this.
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        // Only consider dark squares for standard checkers piece positions
        if ((r + c) % 2 != 0) { 
          if (piece != null && !piece.isKing) {
            double pstValue;
            if (piece.type == PieceType.black) { // Black moves 0 -> 7 (advancing)
              pstValue = _manPst[r][c];
            } else { // Red moves 7 -> 0 (advancing means 7-r for PST index)
              pstValue = _manPst[7 - r][c];
            }
            
            if (piece.type == aiPlayerType) {
              score += pstValue;
            } else if (piece.type == opponentPlayerType) {
              score -= pstValue;
            }
          } else if (piece != null && piece.isKing) { // Kings also have positional value
            double kingPstValue = _kingPst[r][c]; // Kings PST is symmetrical usually
             if (piece.type == aiPlayerType) {
              score += kingPstValue * 0.5; // Kings contribute to general position too
            } else if (piece.type == opponentPlayerType) {
              score -= kingPstValue * 0.5;
            }
          }
        }
      }
    }
    return score;
  }

  double _calculateDefenseStructure(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType, GameRules rules) {
    double score = 0;
    const double defendedManBonus = 0.3;
    const double defendedKingBonus = 0.5;
    const double attackedPenalty = -0.7; // If a piece is attacked and not well defended

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null) {
          BoardPosition currentPos = BoardPosition(r,c);
          if (piece.type == aiPlayerType) {
            if (_isPieceDefendedByFriendly(board, currentPos, piece)) {
              score += piece.isKing ? defendedKingBonus : defendedManBonus;
            }
            if (_isPieceAttackedByOpponent(board, currentPos, piece, opponentPlayerType, rules)) {
              // More sophisticated: check if defenders >= attackers
              if (!_isPieceDefendedByFriendly(board, currentPos, piece)) { // Undefended and attacked
                 score += attackedPenalty * 1.5; // Higher penalty
              } else {
                 score += attackedPenalty;
              }
            }
          } else { // Opponent piece
             if (_isPieceDefendedByFriendly(board, currentPos, piece)) { // Opponent piece is defended
              score -= piece.isKing ? defendedKingBonus * 0.8 : defendedManBonus * 0.8; // Slightly less penalty
            }
            if (_isPieceAttackedByOpponent(board, currentPos, piece, aiPlayerType, rules)) { // AI attacks opponent piece
              if (!_isPieceDefendedByFriendly(board, currentPos, piece)) {
                 score -= attackedPenalty * 1.5; // Good for AI
              } else {
                 score -= attackedPenalty;
              }
            }
          }
        }
      }
    }
    return score;
  }

 bool _isPieceDefendedByFriendly(List<List<Piece?>> board, BoardPosition piecePos, Piece piece) {
    int r = piecePos.row;
    int c = piecePos.col;
    // For standard checkers, men are defended by pieces diagonally behind them.
    // Kings are defended by any adjacent friendly piece.
    
    // Define relative positions of adjacent diagonal squares
    const List<List<int>> diagonalDeltas = [
      [-1, -1], [-1, 1], // Up-left, Up-right
      [1, -1], [1, 1]   // Down-left, Down-right
    ];

    if (piece.isKing) {
      // A king is defended by any adjacent friendly piece on a diagonal
      for (var delta in diagonalDeltas) {
        int supporterR = r + delta[0];
        int supporterC = c + delta[1];
        if (_isValidPosition(supporterR, supporterC) &&
            board[supporterR][supporterC] != null &&
            board[supporterR][supporterC]!.type == piece.type) {
          return true; // Defended by an adjacent friendly piece
        }
      }
    } else {
      // A man is defended if there's a friendly piece diagonally *behind* it.
      // 'piece.moveDirection' is +1 for Black (moving r 0->7), -1 for Red (moving r 7->0).
      // So, 'behindDirRow' is the row delta from which support comes.
      int behindRowDelta = -piece.moveDirection; 

      const List<int> colDeltas = [-1, 1]; // Left and Right for column

      for (var colDelta in colDeltas) {
        int supporterR = r + behindRowDelta;
        int supporterC = c + colDelta;
        if (_isValidPosition(supporterR, supporterC) &&
            board[supporterR][supporterC] != null &&
            board[supporterR][supporterC]!.type == piece.type) {
          return true; // Defended by a friendly piece diagonally behind
        }
      }
    }
    return false;
  }

  bool _isPieceAttackedByOpponent(List<List<Piece?>> board, BoardPosition targetPos, Piece targetPiece, PieceType attackerType, GameRules rules) {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final attacker = board[r][c];
        if (attacker != null && attacker.type == attackerType) {
          Set<BoardPosition> jumps = rules.getJumpMoves(BoardPosition(r,c), attacker, board);
          for (final landingPos in jumps) {
            // Check if this jump captures the piece at targetPos
            int jumpedR = r + (landingPos.row - r) ~/ 2;
            int jumpedC = c + (landingPos.col - c) ~/ 2;
            if (jumpedR == targetPos.row && jumpedC == targetPos.col) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  double _calculatePieceStructure(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType) {
    // Evaluates formations like bridges, or penalizes isolated pieces.
    // This is a simplified version focusing on men not on edge and kings' safety.
    double score = 0;
    const double edgePenaltyMan = -0.2;
    const double isolatedKingPenalty = -0.3;

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null) {
          double pieceScore = 0;
          if (!piece.isKing) { // For men
            if (c == 0 || c == 7) { // Men on side edges are less flexible
              pieceScore += edgePenaltyMan;
            }
          } else { // For kings
            // Check if king is isolated (no friendly pieces nearby)
            bool hasNearbyFriend = false;
            for (int dr = -1; dr <= 1; dr++) {
              for (int dc = -1; dc <= 1; dc++) {
                if (dr == 0 && dc == 0) continue;
                if (_isValidPosition(r + dr, c + dc) && 
                    board[r+dr][c+dc] != null && 
                    board[r+dr][c+dc]!.type == piece.type) {
                  hasNearbyFriend = true;
                  break;
                }
              }
              if (hasNearbyFriend) break;
            }
            if (!hasNearbyFriend) {
              pieceScore += isolatedKingPenalty;
            }
          }
          if (piece.type == aiPlayerType) score += pieceScore;
          else score -= pieceScore;
        }
      }
    }
    return score;
  }
}