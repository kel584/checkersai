// lib/ai_evaluators/turkish_checkers_evaluator.dart
 // For min/max if needed, and .abs()
import '../models/piece_model.dart';
import '../game_rules/game_rules.dart'; // For GameRules type and its methods
import 'board_evaluator.dart';

class TurkishCheckersEvaluator implements BoardEvaluator {
  // --- Piece-Square Tables (PSTs) for Turkish Dama ---

  static const double _manMaterialValue = 100.0;
  static const double _kingMaterialValue = 300.0; 

  static const double _wMaterial = 1.0;
  static const double _wMobility = 3.0;      // Turkish Dama is very mobile
  static const double _wKeySquares = 15.0;
  static const double _wPromotion = 10.0;
  static const double _wDefense = 5.0;
  static const double _wClustering = 2.0;

  static const List<BoardPosition> _centerSquares = [
    BoardPosition(3, 3), BoardPosition(3, 4),
    BoardPosition(4, 3), BoardPosition(4, 4),
  ];
  static const List<BoardPosition> _extendedCenterSquares = [
    BoardPosition(2, 2), BoardPosition(2, 3), BoardPosition(2, 4), BoardPosition(2, 5),
    BoardPosition(3, 2), BoardPosition(3, 5),
    BoardPosition(4, 2), BoardPosition(4, 5),
    BoardPosition(5, 2), BoardPosition(5, 3), BoardPosition(5, 4), BoardPosition(5, 5),
  ];


  bool _isValidPosition(int r, int c) {
    return r >= 0 && r < 8 && c >= 0 && c < 8;
  }

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
    double clusteringScore = _calculatePieceClustering(board, aiPlayerType, opponentPlayerType);

    double totalScore = (materialScore * _wMaterial) +
                        (mobilityScore * _wMobility) +
                        (keySquaresScore * _wKeySquares) +
                        (promotionScore * _wPromotion) +
                        (defenseScore * _wDefense) +
                        (clusteringScore * _wClustering);
    
    return totalScore;
  }

  // --- START OF HELPER METHODS (MOVED FROM TURKISHCHECKERRULES) ---
  // Remember to make them private (_) and adapt them to use 'rules' parameter if needed

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
    // Get all moves (jumps prioritized, then regular)
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
    const double centerBonus = 1.0; // Per piece in center
    const double extCenterBonus = 0.5; // Per piece in extended center

    for (final pos in _centerSquares) {
      final piece = board[pos.row][pos.col];
      if (piece != null) {
        if (piece.type == aiPlayerType) score += centerBonus;
        else if (piece.type == opponentPlayerType) score -= centerBonus;
      }
    }
    for (final pos in _extendedCenterSquares) {
      final piece = board[pos.row][pos.col];
      if (piece != null) {
        if (piece.type == aiPlayerType) score += extCenterBonus;
        else if (piece.type == opponentPlayerType) score -= extCenterBonus;
      }
    }
    return score;
  }

double _calculatePromotionProximity(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType) {
    double score = 0;
    const double maxAdvancementBonus = 1.0; // Max bonus for being on kinging row

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null && !piece.isKing) {
          double bonus = 0;
          if (piece.type == PieceType.black) { // Promotes at row 7
            // Bonus increases as r approaches 7
            bonus = (r / 7.0) * maxAdvancementBonus; 
          } else { // Red promotes at row 0
            // Bonus increases as r approaches 0 (i.e., 7-r approaches 7)
            bonus = ((7 - r) / 7.0) * maxAdvancementBonus;
          }
          
          if (piece.type == aiPlayerType) {
            score += bonus;
          } else if (piece.type == opponentPlayerType) {
            score -= bonus;
          }
        }
      }
    }
    return score;
  }

double _calculateDefenseStructure(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType, GameRules rules) {
    double score = 0;
    const double defendedBonus = 0.2; // Small bonus per piece defended
    const double attackedPenalty = -0.5; // Penalty if a piece is attacked

    List<BoardPosition> aiPieces = [];
    List<BoardPosition> opponentPieces = [];

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null) {
          if (piece.type == aiPlayerType) aiPieces.add(BoardPosition(r,c));
          else opponentPieces.add(BoardPosition(r,c));
        }
      }
    }

    // Check how many AI pieces are attacked / defended
    for(final aiPiecePos in aiPieces) {
      final piece = board[aiPiecePos.row][aiPiecePos.col]!;
      bool isDefended = _isPieceDefended(board, aiPiecePos, piece, rules);
      bool isAttacked = _isPieceAttacked(board, aiPiecePos, piece, opponentPlayerType, rules);
      if (isDefended) score += defendedBonus;
      if (isAttacked && !isDefended) score += attackedPenalty; // More penalty if attacked and undefended
      else if (isAttacked) score += attackedPenalty * 0.5; // Less penalty if attacked but defended
    }

    // Check how many opponent pieces are attacked / defended (from AI's perspective this is good if they are attacked)
     for(final oppPiecePos in opponentPieces) {
      final piece = board[oppPiecePos.row][oppPiecePos.col]!;
      bool isDefended = _isPieceDefended(board, oppPiecePos, piece, rules);
      bool isAttacked = _isPieceAttacked(board, oppPiecePos, piece, aiPlayerType, rules); // Attacked by AI
      if (isAttacked && !isDefended) score -= attackedPenalty; // Good for AI (opponent attacked and undefended)
      else if (isAttacked) score -= attackedPenalty * 0.5; // Still good
      if (isDefended) score -= defendedBonus * 0.5; // Opponent defended is slightly bad for AI
    }
    return score;
  }
  
   bool _isPieceDefended(List<List<Piece?>> board, BoardPosition piecePos, Piece piece, GameRules rules) {
    // Check if any friendly piece can move to this square (simplified: check adjacent friendly pieces)
    // This is a very basic check. A true "defended" check would see if attackers are outnumbered by defenders.
    // For Turkish Dama, adjacent orthogonal pieces support.
    const List<List<int>> directions = [[-1,0],[1,0],[0,-1],[0,1]];
    for(var dir in directions) {
        int r = piecePos.row + dir[0];
        int c = piecePos.col + dir[1];
        if(_isValidPosition(r,c) && board[r][c] != null && board[r][c]!.type == piece.type) {
            return true; // Supported by adjacent friendly piece
        }
    }
    return false;
  }

bool _isPieceAttacked(List<List<Piece?>> board, BoardPosition pieceToAttackPos, Piece pieceToAttack, PieceType attackerType, GameRules rules) {
    // Check if any piece of 'attackerType' can capture 'pieceToAttack'
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final attacker = board[r][c];
        if (attacker != null && attacker.type == attackerType) {
          Set<BoardPosition> jumps = rules.getJumpMoves(BoardPosition(r,c), attacker, board);
          for (final landingPos in jumps) {
            // Determine if this jump captures the piece at pieceToAttackPos
            int jumpedR, jumpedC;
            if (attacker.isKing) { // King jump - pieceToAttackPos must be between attacker and landingPos
                int dr = (landingPos.row - r).sign;
                int dc = (landingPos.col - c).sign;
                int scanR = r + dr;
                int scanC = c + dc;
                //int intermediateOpponents = 0; unused for now
                BoardPosition? capturedByKing;

                while(scanR != landingPos.row || scanC != landingPos.col) {
                    if (scanR == pieceToAttackPos.row && scanC == pieceToAttackPos.col) {
                        capturedByKing = pieceToAttackPos; // This is the piece jumped
                    } else if (board[scanR][scanC] != null) {
                         capturedByKing = null; // Path not clear or multiple pieces
                         break;
                    }
                    scanR += dr;
                    scanC += dc;
                }
                if (capturedByKing != null) return true;

            } else { // Man jump
              jumpedR = r + (landingPos.row - r) ~/ 2;
              jumpedC = c + (landingPos.col - c) ~/ 2;
              if (jumpedR == pieceToAttackPos.row && jumpedC == pieceToAttackPos.col) {
                return true;
              }
            }
          }
        }
      }
    }
    return false;
  }

  double _calculatePieceClustering(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType) {
    double score = 0;
    List<BoardPosition> aiPieces = [];
    // List<BoardPosition> opponentPieces = []; // Can add opponent clustering later

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null && piece.type == aiPlayerType) {
          aiPieces.add(BoardPosition(r, c));
        }
      }
    }

    if (aiPieces.length <= 1) return 0;

    // Simple clustering: bonus for pieces being close to their average position (less spread)
    // Or bonus for pieces having other friendly pieces nearby (within 1 or 2 squares)
    int nearbyAllyBonus = 0;
    for (final pos in aiPieces) {
        for (int dr = -1; dr <= 1; dr++) { // Check 3x3 area around piece
            for (int dc = -1; dc <= 1; dc++) {
                if (dr == 0 && dc == 0) continue;
                int nr = pos.row + dr;
                int nc = pos.col + dc;
                if (_isValidPosition(nr, nc) && board[nr][nc] != null && board[nr][nc]!.type == aiPlayerType) {
                    nearbyAllyBonus++;
                }
            }
        }
    }
    // Each pair is counted twice, so divide by 2. Give a small bonus.
    score += (nearbyAllyBonus / 2.0) * 0.1; 

    return score; // Positive score for AI's clustering
  }
  // Placeholder for other complex helpers you listed, adapt them similarly:
  // double _evaluateEndgameKingCentralization(...) { return 0; }
  // double _evaluateEndgamePieceCoordination(...) { return 0; }
  // double _evaluateEndgameOpposition(...) { return 0; }
  // double _evaluatePieceDevelopment(...) { return 0; }
  // double _evaluateKeySquareControl(...) { return 0; }
  // double _evaluateTacticalPatterns(...) { return 0; }
}