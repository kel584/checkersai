// lib/ai_evaluators/turkish_checkers_evaluator.dart
import 'dart:math';
import '../models/piece_model.dart';
import '../game_rules/game_rules.dart';
import 'board_evaluator.dart';

// Data structure to hold board analysis results from _scanBoard
class _BoardData {
  final double materialScoreValue; // Raw material difference
  final double pstScoreValue;      // Raw PST difference
  final List<BoardPosition> aiPieces;
  final List<BoardPosition> opponentPieces;
  final int totalPieces;
  final int aiMen;
  final int aiKings;
  final int opponentMen;
  final int opponentKings;
  final double clusteringScoreValue;

  _BoardData({
    required this.materialScoreValue,
    required this.pstScoreValue,
    required this.aiPieces,
    required this.opponentPieces,
    required this.totalPieces,
    required this.aiMen,
    required this.aiKings,
    required this.opponentMen,
    required this.opponentKings,
    required this.clusteringScoreValue
  });
}

class TurkishCheckersEvaluator implements BoardEvaluator {
  // --- Material Values ---
  static const double _manMaterialBaseValue = 100.0;
  static const double _kingMaterialBaseValue = 350.0;

  // --- Evaluation Weights (These require careful tuning!) ---
  static const double _wMaterial = 1.0;
  static const double _wPst = 0.15; // Adjusted from 0.2
  static const double _wAdvancedMen = 0.6; 
  static const double _wMobility = 0.7; // Turkish Dama mobility is key
  static const double _wKingActivityAndCentralization = 0.4; // Combined weight
  static const double _wDefenseAndThreats = 0.8; // Combined
  static const double _wImmediateCaptureOpportunities = 1.2; // High impact
  static const double _wClustering = 0.1;
  static const double _wEndgameKingAdvantage = 60.0; // Flat bonus per king difference in endgame


  // --- Piece-Square Tables (PSTs) for Turkish Dama ---
  static const List<List<double>> _turkishManPstForBlack = [
    [0, 1, 1, 1, 1, 1, 1, 0], [1, 2, 2, 2, 2, 2, 2, 1],
    [1, 2, 3, 3, 3, 3, 2, 1], [2, 3, 4, 4, 4, 4, 3, 2],
    [3, 4, 5, 5, 5, 5, 4, 3], [4, 5, 6, 6, 6, 6, 5, 4],
    [6, 7, 8, 8, 8, 8, 7, 6], [20, 20, 20, 20, 20, 20, 20, 20], // Promotion row bonus (relative to piece value)
  ];
  // For Red, we'll flip the row index: _turkishManPstForBlack[7 - r][c]

  static const List<List<double>> _turkishKingPst = [
    [1, 2, 2, 2, 2, 2, 2, 1], [2, 3, 3, 4, 4, 3, 3, 2],
    [2, 3, 4, 5, 5, 4, 3, 2], [2, 4, 5, 6, 6, 5, 4, 2],
    [2, 4, 5, 6, 6, 5, 4, 2], [2, 3, 4, 5, 5, 4, 3, 2],
    [2, 3, 3, 4, 4, 3, 3, 2], [1, 2, 2, 2, 2, 2, 2, 1],
  ];

  bool _isValidPosition(int r, int c) {
    return r >= 0 && r < 8 && c >= 0 && c < 8;
  }

  _BoardData _scanBoard(List<List<Piece?>> board, PieceType aiPlayerType) {
    double materialScore = 0;
    double pstScoreTotal = 0;
    
    List<BoardPosition> aiPiecesPos = [];
    List<BoardPosition> opponentPiecesPos = [];
    int currentTotalPieces = 0;
    int currentAiMen = 0, currentAiKings = 0;
    int currentOpponentMen = 0, currentOpponentKings = 0;

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece == null) continue;

        currentTotalPieces++;
        final currentPos = BoardPosition(r, c);
        bool isAiPiece = (piece.type == aiPlayerType);
        double piecePstValue = 0;

        if (piece.isKing) {
          piecePstValue = _turkishKingPst[r][c];
          if (isAiPiece) {
            currentAiKings++;
            materialScore += _kingMaterialBaseValue;
            aiPiecesPos.add(currentPos);
          } else {
            currentOpponentKings++;
            materialScore -= _kingMaterialBaseValue;
            opponentPiecesPos.add(currentPos);
          }
        } else { // Man
          piecePstValue = (piece.type == PieceType.black)
              ? _turkishManPstForBlack[r][c]
              : _turkishManPstForBlack[7 - r][c]; // Flip for Red
          if (isAiPiece) {
            currentAiMen++;
            materialScore += _manMaterialBaseValue;
            aiPiecesPos.add(currentPos);
          } else {
            currentOpponentMen++;
            materialScore -= _manMaterialBaseValue;
            opponentPiecesPos.add(currentPos);
          }
        }
        if (isAiPiece) {
            pstScoreTotal += piecePstValue;
        } else {
            pstScoreTotal -= piecePstValue; // Subtract opponent's PST
        }
      }
    }
    
    // Clustering is calculated outside as it needs the full lists of pieces
    double clusteringScoreVal = _calculateFastClustering(aiPiecesPos, board) - 
                               _calculateFastClustering(opponentPiecesPos, board);


    return _BoardData(
      materialScoreValue: materialScore,
      pstScoreValue: pstScoreTotal,
      clusteringScoreValue: clusteringScoreVal,
      aiPieces: aiPiecesPos,
      opponentPieces: opponentPiecesPos,
      totalPieces: currentTotalPieces,
      aiMen: currentAiMen,
      aiKings: currentAiKings,
      opponentMen: currentOpponentMen,
      opponentKings: currentOpponentKings,
    );
  }

  @override
  double evaluate({
    required List<List<Piece?>> board,
    required PieceType aiPlayerType,
    required GameRules rules,
  }) {
    final opponentPlayerType = (aiPlayerType == PieceType.red) ? PieceType.black : PieceType.red;
    final boardData = _scanBoard(board, aiPlayerType);

    double totalScore = 0;

    totalScore += boardData.materialScoreValue * _wMaterial;
    totalScore += boardData.pstScoreValue * _wPst;
    totalScore += boardData.clusteringScoreValue * _wClustering;
    
    bool isEndgame = boardData.totalPieces <= 10;

    totalScore += _calculateAdvancedMen(board, aiPlayerType, opponentPlayerType) * _wAdvancedMen;
    totalScore += _calculateMobility(board, aiPlayerType, opponentPlayerType, rules, boardData.aiPieces, boardData.opponentPieces) * _wMobility;
    totalScore += _calculateKingActivityAndCentralization(board, aiPlayerType, opponentPlayerType, boardData.aiPieces, boardData.opponentPieces, rules) * _wKingActivityAndCentralization;
    totalScore += _calculateDefenseAndThreats(board, aiPlayerType, opponentPlayerType, rules, boardData.aiPieces, boardData.opponentPieces) * _wDefenseAndThreats;
    totalScore += _evaluateImmediateCaptureOpportunities(board, aiPlayerType, opponentPlayerType, rules) * _wImmediateCaptureOpportunities;
    
    if (isEndgame) {
        totalScore += (boardData.aiKings - boardData.opponentKings) * _wEndgameKingAdvantage;
    }

    return totalScore;
  }

  // --- HELPER EVALUATION METHODS ---

  double _calculateAdvancedMen(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType) {
    double score = 0;
    const double advancementMultiplier = 1.0; // Scaled by _wAdvancedMen later
    const double nearPromotionBonusAbsolute = 15.0; // Direct bonus, not further scaled by weight

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null && !piece.isKing) {
          int distanceToPromotion;
          // Black advances from low row index (e.g. 1,2 where they start) to 7
          // Red advances from high row index (e.g. 5,6 where they start) to 0
          if (piece.type == PieceType.black) { 
            distanceToPromotion = 7 - r;
          } else { 
            distanceToPromotion = r;
          }
          
          double currentPieceAdvancementBonus = (7 - distanceToPromotion) * advancementMultiplier;
          if (distanceToPromotion <= 1) { 
            currentPieceAdvancementBonus += nearPromotionBonusAbsolute; // Correct variable name
          }
          
          if (piece.type == aiPlayerType) {
            score += currentPieceAdvancementBonus;
          } else {
            score -= currentPieceAdvancementBonus; 
          }
        }
      }
    }
    return score;
  }

  double _calculateMobility(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType, GameRules rules, List<BoardPosition> aiPieces, List<BoardPosition> opponentPieces) {
    int aiTotalMoves = 0;
    for (final pos in aiPieces) {
      final piece = board[pos.row][pos.col]!;
      aiTotalMoves += _countQuickMovesForPiece(pos, piece, board, rules);
    }

    int opponentTotalMoves = 0;
    for (final pos in opponentPieces) {
      final piece = board[pos.row][pos.col]!;
      opponentTotalMoves += _countQuickMovesForPiece(pos, piece, board, rules);
    }
    return (aiTotalMoves - opponentTotalMoves).toDouble();
  }

  int _countQuickMovesForPiece(BoardPosition pos, Piece piece, List<List<Piece?>> board, GameRules rules) {
    // This should ideally use rules.getRegularMoves and rules.getJumpMoves for accuracy,
    // but that's slow. This is a fast approximation for Turkish Dama.
    int moveCount = 0;
    if (piece.isKing) {
      const directions = [[-1, 0], [1, 0], [0, -1], [0, 1]];
      for (final dir in directions) {
        for (int i = 1; i < 8; i++) {
          int r = pos.row + dir[0] * i;
          int c = pos.col + dir[1] * i;
          if (!_isValidPosition(r, c) || board[r][c] != null) break;
          moveCount++;
        }
      }
    } else { // Man (Turkish Dama: forward or sideways non-capturing)
      int forwardDir = (piece.type == PieceType.black) ? 1 : -1;
      final manMoveDirs = [[forwardDir, 0], [0, -1], [0, 1]];
      for (final dir in manMoveDirs) {
        int r = pos.row + dir[0];
        int c = pos.col + dir[1];
        if (_isValidPosition(r, c) && board[r][c] == null) {
          moveCount++;
        }
      }
    }
    // Add a small bonus for potential jumps if not too slow
    Set<BoardPosition> jumps = rules.getJumpMoves(pos, piece, board);
    moveCount += jumps.length; // Each jump destination counts as mobility

    return moveCount;
  }
  
  double _calculateKingActivityAndCentralization(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType, List<BoardPosition> aiPieces, List<BoardPosition> opponentPieces, GameRules rules) {
      double score = 0;
      for (final pos in aiPieces) {
          final piece = board[pos.row][pos.col];
          if (piece != null && piece.isKing) {
              double r = pos.row.toDouble();
              double c = pos.col.toDouble();
              score += (3.5 - (r - 3.5).abs()) + (3.5 - (c - 3.5).abs()); 
          }
      }
      for (final pos in opponentPieces) {
          final piece = board[pos.row][pos.col];
           if (piece != null && piece.isKing) {
              double r = pos.row.toDouble();
              double c = pos.col.toDouble();
              score -= (3.5 - (r - 3.5).abs()) + (3.5 - (c - 3.5).abs());
          }
      }
      return score;
  }

  double _evaluateImmediateCaptureOpportunities(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType, GameRules rules) {
      double score = 0;
      const double captureSequenceBonus = 10.0; // Bonus per piece that can start a capture
      const double underThreatBySequencePenalty = -12.0;

      Map<BoardPosition, Set<BoardPosition>> aiJumps = rules.getAllMovesForPlayer(board, aiPlayerType, true);
      if (aiJumps.isNotEmpty) {
          score += aiJumps.keys.length * captureSequenceBonus;
      }

      Map<BoardPosition, Set<BoardPosition>> opponentJumps = rules.getAllMovesForPlayer(board, opponentPlayerType, true);
      if (opponentJumps.isNotEmpty) {
          score += opponentJumps.keys.length * underThreatBySequencePenalty; 
      }
      return score;
  }
  
  double _calculateDefenseAndThreats(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType, GameRules rules, List<BoardPosition> aiPieces, List<BoardPosition> opponentPieces) {
      double score = 0;
      const double supportedPieceBonus = 2.0; // Increased from 0.5
      const double attackedAndUndefendedPenalty = -60.0; // More severe

      for (final pos in aiPieces) {
          final piece = board[pos.row][pos.col]!;
          bool isDefended = _isPieceSupported(board, pos, piece.type);
          bool isAttacked = _isPieceUnderImmediateJumpThreat(board, pos, piece, opponentPlayerType, rules);

          if (isDefended) score += supportedPieceBonus;
          if (isAttacked) {
              score += (isDefended ? attackedAndUndefendedPenalty * 0.6 : attackedAndUndefendedPenalty); // Mitigate if defended
          }
      }
      for (final pos in opponentPieces) {
          final piece = board[pos.row][pos.col]!;
          bool isDefended = _isPieceSupported(board, pos, piece.type);
          bool isAttacked = _isPieceUnderImmediateJumpThreat(board, pos, piece, aiPlayerType, rules);

          if (isDefended) score -= supportedPieceBonus * 0.6; 
          if (isAttacked) {
              score -= (isDefended ? (attackedAndUndefendedPenalty * 0.6) : attackedAndUndefendedPenalty); 
          }
      }
      return score;
  }

  bool _isPieceSupported(List<List<Piece?>> board, BoardPosition piecePos, PieceType friendlyType) {
    const List<List<int>> DIRS = [[-1,0],[1,0],[0,-1],[0,1]]; // Orthogonal support for Turkish
    for(var d in DIRS) {
        int r = piecePos.row + d[0];
        int c = piecePos.col + d[1];
        if(_isValidPosition(r,c) && board[r][c]?.type == friendlyType) return true;
    }
    return false;
  }

  bool _isPieceUnderImmediateJumpThreat(List<List<Piece?>> board, BoardPosition targetPos, Piece targetPiece, PieceType attackerType, GameRules rules ) {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final attacker = board[r][c];
        if (attacker != null && attacker.type == attackerType) {
          Set<BoardPosition> jumps = rules.getJumpMoves(BoardPosition(r,c), attacker, board);
          for (final landingPos in jumps) {
            int jumpedR, jumpedC;
            if (attacker.isKing) { 
                int dr = (landingPos.row - r).sign;
                int dc = (landingPos.col - c).sign;
                int scanR = r + dr;
                int scanC = c + dc;
                bool pieceFoundOnPath = false;
                while(scanR != landingPos.row || scanC != landingPos.col) {
                    if (!_isValidPosition(scanR, scanC)) {pieceFoundOnPath=false; break;} // Path blocked or off-board
                    if (scanR == targetPos.row && scanC == targetPos.col) { 
                        if(board[scanR][scanC]?.type == targetPiece.type) { // Ensure it's the correct target
                           pieceFoundOnPath = true; 
                        } else {
                           pieceFoundOnPath = false; // Found a piece, but not the target
                        }
                        break;
                    }
                    if (board[scanR][scanC] != null) {pieceFoundOnPath=false; break;} // Path blocked before target
                    scanR += dr;
                    scanC += dc;
                }
                if(pieceFoundOnPath) return true;
            } else { // Man jump
              jumpedR = r + (landingPos.row - r) ~/ 2;
              jumpedC = c + (landingPos.col - c) ~/ 2;
              if (jumpedR == targetPos.row && jumpedC == targetPos.col) {
                return true;
              }
            }
          }
        }
      }
    }
    return false;
  }

  double _calculateFastClustering(List<BoardPosition> pieces, List<List<Piece?>> board) {
    if (pieces.length <= 1) return 0;
    double score = 0;
    int adjacentFriendlyOrthogonal = 0;

    for (final pos in pieces) {
      const List<List<int>> DIRS = [[-1,0],[1,0],[0,-1],[0,1]];
      for(var d in DIRS) {
        int nr = pos.row + d[0];
        int nc = pos.col + d[1];
        if (_isValidPosition(nr, nc) && board[nr][nc] != null && board[nr][nc]!.type == board[pos.row][pos.col]!.type) {
          adjacentFriendlyOrthogonal++;
        }
      }
    }
    // Each pair is counted twice if we iterate through all pieces.
    // Divide by 2 and apply a small bonus for each supporting piece.
    score += (adjacentFriendlyOrthogonal / 2.0) * 0.5; 
    return score;
  }
}