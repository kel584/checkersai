// lib/ai_evaluators/turkish_checkers_evaluator.dart
import '../models/piece_model.dart';
import '../game_rules/game_rules.dart';
import 'board_evaluator.dart';

class TurkishCheckersEvaluator implements BoardEvaluator {
  // --- Cached piece-square tables for faster lookup ---
  static const double _manMaterialValue = 100.0;
  static const double _kingMaterialValue = 300.0;

  // Reduced weights for faster calculation while maintaining balance
  static const double _wMaterial = 1.0;
  static const double _wMobility = 2.5;      // Slightly reduced
  static const double _wKeySquares = 12.0;   // Slightly reduced
  static const double _wPromotion = 8.0;     // Slightly reduced
  static const double _wDefense = 3.0;       // Reduced for speed
  static const double _wClustering = 1.5;    // Reduced for speed

  // Pre-computed lookup tables for key squares
  static const Map<int, double> _centerSquareValues = {
    27: 1.0, 28: 1.0, 35: 1.0, 36: 1.0, // center squares (3,3), (3,4), (4,3), (4,4)
  };
  
  static const Map<int, double> _extendedCenterValues = {
    18: 0.5, 19: 0.5, 20: 0.5, 21: 0.5, // row 2
    26: 0.5, 29: 0.5, // row 3 edges
    34: 0.5, 37: 0.5, // row 4 edges
    42: 0.5, 43: 0.5, 44: 0.5, 45: 0.5, // row 5
  };

  // Pre-computed promotion bonuses (index = row for black, 7-row for red)
  static const List<double> _promotionBonuses = [
    0.0, 0.143, 0.286, 0.429, 0.571, 0.714, 0.857, 1.0
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
    final opponentPlayerType = (aiPlayerType == PieceType.red) ? PieceType.black : PieceType.red;

    // Single board scan to collect all data at once
    final boardData = _scanBoard(board, aiPlayerType, opponentPlayerType);
    
    double totalScore = 0;
    
    // Fast material calculation
    totalScore += boardData.materialScore * _wMaterial;
    
    // Simplified mobility (only if pieces > threshold for performance)
    if (boardData.totalPieces > 6) {
      final mobilityScore = _calculateFastMobility(board, aiPlayerType, opponentPlayerType, rules, boardData);
      totalScore += mobilityScore * _wMobility;
    }
    
    // Fast key square evaluation
    totalScore += boardData.keySquareScore * _wKeySquares;
    
    // Fast promotion evaluation
    totalScore += boardData.promotionScore * _wPromotion;
    
    // Simplified defense (only for non-endgame)
    if (boardData.totalPieces > 8) {
      final defenseScore = _calculateSimplifiedDefense(boardData);
      totalScore += defenseScore * _wDefense;
    }
    
    // Simple clustering
    totalScore += boardData.clusteringScore * _wClustering;
    
    return totalScore;
  }

  // Single board scan to collect all necessary data
  _BoardData _scanBoard(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType) {
    double materialScore = 0;
    double keySquareScore = 0;
    double promotionScore = 0;
    double clusteringScore = 0;
    
    final aiPieces = <BoardPosition>[];
    final opponentPieces = <BoardPosition>[];
    int totalPieces = 0;
    
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece == null) continue;
        
        totalPieces++;
        final pos = BoardPosition(r, c);
        final squareIndex = r * 8 + c;
        
        if (piece.type == aiPlayerType) {
          aiPieces.add(pos);
          
          // Material
          materialScore += piece.isKing ? _kingMaterialValue : _manMaterialValue;
          
          // Key squares
          keySquareScore += _centerSquareValues[squareIndex] ?? 0;
          keySquareScore += _extendedCenterValues[squareIndex] ?? 0;
          
          // Promotion (only for non-kings)
          if (!piece.isKing) {
            if (piece.type == PieceType.black) {
              promotionScore += _promotionBonuses[r];
            } else {
              promotionScore += _promotionBonuses[7 - r];
            }
          }
          
        } else if (piece.type == opponentPlayerType) {
          opponentPieces.add(pos);
          
          // Material
          materialScore -= piece.isKing ? _kingMaterialValue : _manMaterialValue;
          
          // Key squares
          keySquareScore -= _centerSquareValues[squareIndex] ?? 0;
          keySquareScore -= _extendedCenterValues[squareIndex] ?? 0;
          
          // Promotion (only for non-kings)
          if (!piece.isKing) {
            if (piece.type == PieceType.black) {
              promotionScore -= _promotionBonuses[r];
            } else {
              promotionScore -= _promotionBonuses[7 - r];
            }
          }
        }
      }
    }
    
    // Fast clustering calculation
    clusteringScore = _calculateFastClustering(board, aiPieces, aiPlayerType);
    
    return _BoardData(
      materialScore: materialScore,
      keySquareScore: keySquareScore,
      promotionScore: promotionScore,
      clusteringScore: clusteringScore,
      aiPieces: aiPieces,
      opponentPieces: opponentPieces,
      totalPieces: totalPieces,
    );
  }

  // Simplified mobility calculation with early termination
  double _calculateFastMobility(List<List<Piece?>> board, PieceType aiPlayerType, 
      PieceType opponentPlayerType, GameRules rules, _BoardData boardData) {
    
    // Quick mobility estimate: count immediate moves for each piece (limited depth)
    int aiMoves = 0;
    int opponentMoves = 0;
    
    // Only check mobility for a subset of pieces if too many
    final aiPiecesToCheck = boardData.aiPieces.length > 6 
        ? boardData.aiPieces.take(6).toList()
        : boardData.aiPieces;
    final oppPiecesToCheck = boardData.opponentPieces.length > 6
        ? boardData.opponentPieces.take(6).toList()
        : boardData.opponentPieces;
    
    // AI mobility
    for (final pos in aiPiecesToCheck) {
      final piece = board[pos.row][pos.col]!;
      aiMoves += _countQuickMoves(pos, piece, board);
    }
    
    // Opponent mobility
    for (final pos in oppPiecesToCheck) {
      final piece = board[pos.row][pos.col]!;
      opponentMoves += _countQuickMoves(pos, piece, board);
    }
    
    return (aiMoves - opponentMoves).toDouble();
  }

  // Quick move counting without full rule validation
  int _countQuickMoves(BoardPosition pos, Piece piece, List<List<Piece?>> board) {
    int moveCount = 0;
    const directions = [[-1, 0], [1, 0], [0, -1], [0, 1]];
    
    if (piece.isKing) {
      // King can move/jump in all directions
      for (final dir in directions) {
        int r = pos.row + dir[0];
        int c = pos.col + dir[1];
        
        while (_isValidPosition(r, c)) {
          if (board[r][c] == null) {
            moveCount++; // Regular move
            r += dir[0];
            c += dir[1];
          } else if (board[r][c]!.type != piece.type) {
            // Potential jump
            int jumpR = r + dir[0];
            int jumpC = c + dir[1];
            if (_isValidPosition(jumpR, jumpC) && board[jumpR][jumpC] == null) {
              moveCount += 2; // Jump is worth more
            }
            break;
          } else {
            break; // Blocked by own piece
          }
        }
      }
    } else {
      // Man moves
      for (final dir in directions) {
        int newR = pos.row + dir[0];
        int newC = pos.col + dir[1];
        
        if (_isValidPosition(newR, newC)) {
          if (board[newR][newC] == null) {
            moveCount++; // Regular move
          } else if (board[newR][newC]!.type != piece.type) {
            // Potential jump
            int jumpR = newR + dir[0];
            int jumpC = newC + dir[1];
            if (_isValidPosition(jumpR, jumpC) && board[jumpR][jumpC] == null) {
              moveCount += 2; // Jump is worth more
            }
          }
        }
      }
    }
    
    return moveCount;
  }

  // Simplified defense calculation
  double _calculateSimplifiedDefense(_BoardData boardData) {
    double score = 0;
    const double supportBonus = 0.1;
    
    // Simple support calculation: pieces with adjacent friendlies get bonus
    int aiSupported = 0;
    int oppSupported = 0;
    
    // This is a simplified version - just count adjacent pieces
    for (final pos in boardData.aiPieces) {
      if (_hasAdjacentAlly(pos, boardData.aiPieces)) {
        aiSupported++;
      }
    }
    
    for (final pos in boardData.opponentPieces) {
      if (_hasAdjacentAlly(pos, boardData.opponentPieces)) {
        oppSupported++;
      }
    }
    
    score += (aiSupported - oppSupported) * supportBonus;
    return score;
  }

  bool _hasAdjacentAlly(BoardPosition pos, List<BoardPosition> allies) {
    for (final ally in allies) {
      if (ally == pos) continue;
      int dr = (ally.row - pos.row).abs();
      int dc = (ally.col - pos.col).abs();
      if (dr <= 1 && dc <= 1 && (dr + dc) > 0) {
        return true;
      }
    }
    return false;
  }

  // Fast clustering calculation
  double _calculateFastClustering(List<List<Piece?>> board, List<BoardPosition> aiPieces, PieceType aiPlayerType) {
    if (aiPieces.length <= 1) return 0;
    
    double score = 0;
    int nearbyPairs = 0;
    
    // Count adjacent pairs (simplified clustering)
    for (int i = 0; i < aiPieces.length; i++) {
      for (int j = i + 1; j < aiPieces.length; j++) {
        final pos1 = aiPieces[i];
        final pos2 = aiPieces[j];
        int dr = (pos1.row - pos2.row).abs();
        int dc = (pos1.col - pos2.col).abs();
        
        if (dr <= 1 && dc <= 1) {
          nearbyPairs++;
        }
      }
    }
    
    score += nearbyPairs * 0.1;
    return score;
  }
}

// Data structure to hold board analysis results
class _BoardData {
  final double materialScore;
  final double keySquareScore;
  final double promotionScore;
  final double clusteringScore;
  final List<BoardPosition> aiPieces;
  final List<BoardPosition> opponentPieces;
  final int totalPieces;
  
  _BoardData({
    required this.materialScore,
    required this.keySquareScore,
    required this.promotionScore,
    required this.clusteringScore,
    required this.aiPieces,
    required this.opponentPieces,
    required this.totalPieces,
  });
}