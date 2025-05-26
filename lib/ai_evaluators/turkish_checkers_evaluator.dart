// lib/ai_evaluators/turkish_checkers_evaluator.dart
import 'dart:math';
import '../models/piece_model.dart';
import '../models/bitboard_state.dart';
import '../utils/bit_utils.dart';
import '../game_rules/game_rules.dart';
import 'board_evaluator.dart';

class FullCaptureSequence {
  final BoardPosition initialFromPos;
  final BoardPosition firstStepToPos;
  final List<BoardPosition> fullPath;
  final int numCaptures;
  final BitboardState finalBoardState;

  FullCaptureSequence({
    required this.initialFromPos,
    required this.firstStepToPos,
    required this.fullPath,
    required this.numCaptures,
    required this.finalBoardState,
  });
}

class _BoardData {
  final double materialScore;
  final double keySquareScore;
  final double promotionScore;
  final double clusteringScore;
  final int aiMenBB;
  final int aiKingsBB;
  final int opponentMenBB;
  final int opponentKingsBB;
  final int totalPieces;

  _BoardData({
    required this.materialScore,
    required this.keySquareScore,
    required this.promotionScore,
    required this.clusteringScore,
    required this.aiMenBB,
    required this.aiKingsBB,
    required this.opponentMenBB,
    required this.opponentKingsBB,
    required this.totalPieces,
  });
}

class TurkishCheckersEvaluator implements BoardEvaluator {
  // --- Material Values ---
  static const double _manMaterialBaseValue = 100.0;
  static const double _kingMaterialBaseValue = 300.0;

  // --- Evaluation Weights ---
  static const double _wMaterial = 1.0;
  static const double _wMobility = 2.0;
  static const double _wKeySquares = 0.2;
  static const double _wPromotion = 0.3;
  static const double _wDefense = 0.25;
  static const double _wClustering = 0.15;
  static const double _wThreatDetection = 1.5;

  // --- Lookup Tables ---
  static const Map<int, double> _centerSquareValues = {
    27: 10.0, 28: 10.0, 35: 10.0, 36: 10.0,
  };
  static const Map<int, double> _extendedCenterValues = {
    18: 5.0, 19: 5.0, 20: 5.0, 21: 5.0,
    26: 5.0, 29: 5.0,
    34: 5.0, 37: 5.0,
    42: 5.0, 43: 5.0, 44: 5.0, 45: 5.0,
  };
  static const List<double> _promotionBonuses = [
    0.0, 2.0, 5.0, 10.0, 18.0, 30.0, 50.0, 150.0
  ];

  // --- Precomputed Move Masks ---
  static final List<int> _blackManMoveMasks = _generateManMoveMasks(1);
  static final List<int> _redManMoveMasks = _generateManMoveMasks(-1);
  static final List<int> _kingMoveMasks = _generateKingMoveMasks();

  // --- Bitboard Utilities ---
  static int indexToRow(int index) => index ~/ 8;
  static int indexToCol(int index) => index % 8;
  static int rcToIndex(int row, int col) => row * 8 + col;

  static int countTrailingZeros(int bitboard) {
    if (bitboard == 0) return -1;
    int count = 0;
    while ((bitboard & 1) == 0 && count < 64) {
      bitboard >>= 1;
      count++;
    }
    return count < 64 ? count : -1;
  }

  static int popLsb(int bitboard) {
    return countTrailingZeros(bitboard);
  }

  static bool _isValidPosition(int r, int c) {
    return r >= 0 && r < 8 && c >= 0 && c < 8;
  }

  static bool _isOccupied(BitboardState board, int idx) {
    return (board.blackMen | board.blackKings | board.redMen | board.redKings).isSet(idx);
  }

  static List<int> _generateManMoveMasks(int forwardDir) {
    List<int> masks = List.filled(64, 0);
    for (int i = 0; i < 64; i++) {
      int r = indexToRow(i), c = indexToCol(i);
      List<List<int>> offsets = [[forwardDir, 0], [0, -1], [0, 1]];
      for (var d in offsets) {
        int nr = r + d[0], nc = c + d[1];
        if (_isValidPosition(nr, nc)) {
          masks[i] |= 1 << rcToIndex(nr, nc);
        }
      }
    }
    return masks;
  }

  static List<int> _generateKingMoveMasks() {
    List<int> masks = List.filled(64, 0);
    for (int i = 0; i < 64; i++) {
      int r = indexToRow(i), c = indexToCol(i);
      List<List<int>> directions = [[-1, 0], [1, 0], [0, -1], [0, 1]];
      for (var dir in directions) {
        for (int step = 1; step < 8; step++) {
          int nr = r + dir[0] * step, nc = c + dir[1] * step;
          if (!_isValidPosition(nr, nc)) break;
          masks[i] |= 1 << rcToIndex(nr, nc);
        }
      }
    }
    return masks;
  }

  @override
  double evaluate({
    required BitboardState board,
    required PieceType aiPlayerType,
    required GameRules rules,
  }) {
    final opponentPlayerType = aiPlayerType.opposite;
    final boardData = _scanBoard(board, aiPlayerType, opponentPlayerType);

    double totalScore = 0;
    totalScore += boardData.materialScore * _wMaterial;

    if (boardData.totalPieces > 6) {
      final mobilityScore = _calculateFastMobility(board, aiPlayerType, opponentPlayerType, rules, boardData);
      totalScore += mobilityScore * _wMobility;
    }

    totalScore += boardData.keySquareScore * _wKeySquares;
    totalScore += boardData.promotionScore * _wPromotion;

    if (boardData.totalPieces > 8) {
      final defenseScore = _calculateSimplifiedDefense(board, boardData);
      totalScore += defenseScore * _wDefense;
    }

    totalScore += boardData.clusteringScore * _wClustering;

    final threatScore = _detectThreats(board, aiPlayerType, opponentPlayerType, rules);
    totalScore += threatScore * _wThreatDetection;

    return totalScore;
  }

  double evaluateMove({
    required BitboardState board,
    required BoardPosition from,
    required BoardPosition to,
    required PieceType aiPlayerType,
    required GameRules rules,
  }) {
    int fromIdx = rcToIndex(from.row, from.col);
    if (!_isOccupied(board, fromIdx)) return evaluate(board: board, aiPlayerType: aiPlayerType, rules: rules);

    Piece piece = board.getPieceAt(from.row, from.col)!;
    BitboardState tempBoard = _copyBoard(board);
    int toIdx = rcToIndex(to.row, to.col);

    // Update bitboards
    if (piece.type == PieceType.black) {
      if (piece.isKing) {
        tempBoard.blackKings &= ~(1 << fromIdx);
        tempBoard.blackKings |= 1 << toIdx;
      } else {
        tempBoard.blackMen &= ~(1 << fromIdx);
        if (to.row == 7) {
          tempBoard.blackKings |= 1 << toIdx;
        } else {
          tempBoard.blackMen |= 1 << toIdx;
        }
      }
    } else {
      if (piece.isKing) {
        tempBoard.redKings &= ~(1 << fromIdx);
        tempBoard.redKings |= 1 << toIdx;
      } else {
        tempBoard.redMen &= ~(1 << fromIdx);
        if (to.row == 0) {
          tempBoard.redKings |= 1 << toIdx;
        } else {
          tempBoard.redMen |= 1 << toIdx;
        }
      }
    }

    final baseScore = evaluate(board: tempBoard, aiPlayerType: aiPlayerType, rules: rules);
    final opponentThreatScore = _analyzeOpponentThreats(tempBoard, aiPlayerType.opposite, aiPlayerType, rules);
    return baseScore + opponentThreatScore;
  }

  _BoardData _scanBoard(BitboardState board, PieceType aiPlayerType, PieceType opponentPlayerType) {
    double materialScore = 0;
    double keySquareScore = 0;
    double promotionScore = 0;
    int aiMenBB = aiPlayerType == PieceType.black ? board.blackMen : board.redMen;
    int aiKingsBB = aiPlayerType == PieceType.black ? board.blackKings : board.redKings;
    int opponentMenBB = opponentPlayerType == PieceType.black ? board.blackMen : board.redMen;
    int opponentKingsBB = opponentPlayerType == PieceType.black ? board.blackKings : board.redKings;
    int totalPieces = (aiMenBB | aiKingsBB | opponentMenBB | opponentKingsBB).countBits();

    int tempAiMen = aiMenBB, tempAiKings = aiKingsBB;
    int tempOppMen = opponentMenBB, tempOppKings = opponentKingsBB;
    double aiClustering = 0, oppClustering = 0;

    while (tempAiMen != 0) {
      int idx = popLsb(tempAiMen);
      if (idx == -1) break;
      tempAiMen &= ~(1 << idx);
      materialScore += _manMaterialBaseValue;
      keySquareScore += (_centerSquareValues[idx] ?? 0.0) + (_extendedCenterValues[idx] ?? 0.0);
      int r = indexToRow(idx);
      int dist = aiPlayerType == PieceType.black ? r : 7 - r;
      promotionScore += _promotionBonuses[dist];
      aiClustering += _countAdjacentFriendly(board, idx, aiPlayerType);
    }
    while (tempAiKings != 0) {
      int idx = popLsb(tempAiKings);
      if (idx == -1) break;
      tempAiKings &= ~(1 << idx);
      materialScore += _kingMaterialBaseValue;
      keySquareScore += (_centerSquareValues[idx] ?? 0.0) + (_extendedCenterValues[idx] ?? 0.0);
      aiClustering += _countAdjacentFriendly(board, idx, aiPlayerType);
    }
    while (tempOppMen != 0) {
      int idx = popLsb(tempOppMen);
      if (idx == -1) break;
      tempOppMen &= ~(1 << idx);
      materialScore -= _manMaterialBaseValue;
      keySquareScore -= (_centerSquareValues[idx] ?? 0.0) + (_extendedCenterValues[idx] ?? 0.0);
      int r = indexToRow(idx);
      int dist = opponentPlayerType == PieceType.black ? r : 7 - r;
      promotionScore -= _promotionBonuses[dist];
      oppClustering += _countAdjacentFriendly(board, idx, opponentPlayerType);
    }
    while (tempOppKings != 0) {
      int idx = popLsb(tempOppKings);
      if (idx == -1) break;
      tempOppKings &= ~(1 << idx);
      materialScore -= _kingMaterialBaseValue;
      keySquareScore -= (_centerSquareValues[idx] ?? 0.0) + (_extendedCenterValues[idx] ?? 0.0);
      oppClustering += _countAdjacentFriendly(board, idx, opponentPlayerType);
    }

    return _BoardData(
      materialScore: materialScore,
      keySquareScore: keySquareScore,
      promotionScore: promotionScore,
      clusteringScore: aiClustering - oppClustering,
      aiMenBB: aiMenBB,
      aiKingsBB: aiKingsBB,
      opponentMenBB: opponentMenBB,
      opponentKingsBB: opponentKingsBB,
      totalPieces: totalPieces,
    );
  }

  double _calculateFastMobility(BitboardState board, PieceType aiPlayerType, PieceType opponentPlayerType, GameRules rules, _BoardData boardData) {
    int aiMoves = 0, oppMoves = 0;
    int aiBB = boardData.aiMenBB | boardData.aiKingsBB;
    int oppBB = boardData.opponentMenBB | boardData.opponentKingsBB;

    while (aiBB != 0) {
      int idx = popLsb(aiBB);
      if (idx == -1) break;
      aiBB &= ~(1 << idx);
      Piece? piece = board.getPieceAt(indexToRow(idx), indexToCol(idx));
      if (piece != null) {
        aiMoves += _countQuickMoves(idx, piece, board);
      }
    }
    while (oppBB != 0) {
      int idx = popLsb(oppBB);
      if (idx == -1) break;
      oppBB &= ~(1 << idx);
      Piece? piece = board.getPieceAt(indexToRow(idx), indexToCol(idx));
      if (piece != null) {
        oppMoves += _countQuickMoves(idx, piece, board);
      }
    }
    return (aiMoves - oppMoves).toDouble();
  }

  int _countQuickMoves(int idx, Piece piece, BitboardState board) {
    int moves = 0;
    int occupied = board.blackMen | board.blackKings | board.redMen | board.redKings;
    if (piece.isKing) {
      moves += (_kingMoveMasks[idx] & ~occupied).countBits();
    } else {
      int moveMask = piece.type == PieceType.black ? _blackManMoveMasks[idx] : _redManMoveMasks[idx];
      moves += (moveMask & ~occupied).countBits();
    }

    List<List<int>> jumpDirs = [[2, 0], [-2, 0], [0, 2], [0, -2]];
    int r = indexToRow(idx), c = indexToCol(idx);
    for (var d in jumpDirs) {
      int nr = r + d[0], nc = c + d[1];
      if (!_isValidPosition(nr, nc)) continue;
      int jumpIdx = rcToIndex(nr, nc);
      int midR = (r + nr) ~/ 2, midC = (c + nc) ~/ 2;
      int midIdx = rcToIndex(midR, midC);
      if (_isOccupied(board, midIdx) && board.getPieceAt(midR, midC)!.type != piece.type && !_isOccupied(board, jumpIdx)) {
        moves += 2;
      }
    }
    return moves;
  }

  double _calculateSimplifiedDefense(BitboardState board, _BoardData boardData) {
    double score = 0;
    const double supportBonus = 0.5;
    int aiSupported = 0, oppSupported = 0;

    int aiBB = boardData.aiMenBB | boardData.aiKingsBB;
    int oppBB = boardData.opponentMenBB | boardData.opponentKingsBB;

    while (aiBB != 0) {
      int idx = popLsb(aiBB);
      if (idx == -1) break;
      aiBB &= ~(1 << idx);
      if (_hasAdjacentAlly(board, idx, boardData.aiMenBB | boardData.aiKingsBB)) {
        aiSupported++;
      }
    }
    while (oppBB != 0) {
      int idx = popLsb(oppBB);
      if (idx == -1) break;
      oppBB &= ~(1 << idx);
      if (_hasAdjacentAlly(board, idx, boardData.opponentMenBB | boardData.opponentKingsBB)) {
        oppSupported++;
      }
    }
    score += (aiSupported - oppSupported) * supportBonus;
    return score;
  }

  bool _hasAdjacentAlly(BitboardState board, int idx, int friendlyBB) {
    int r = indexToRow(idx), c = indexToCol(idx);
    const dirs = [[-1, 0], [1, 0], [0, -1], [0, 1]];
    for (var d in dirs) {
      int nr = r + d[0], nc = c + d[1];
      if (_isValidPosition(nr, nc)) {
        int nIdx = rcToIndex(nr, nc);
        if (friendlyBB.isSet(nIdx)) return true;
      }
    }
    return false;
  }

  double _calculateFastClustering(BitboardState board, int piecesBB, PieceType type) {
    if (piecesBB.countBits() <= 1) return 0;
    double score = 0;
    int tempBB = piecesBB;
    while (tempBB != 0) {
      int idx = popLsb(tempBB);
      if (idx == -1) break;
      tempBB &= ~(1 << idx);
      score += _countAdjacentFriendly(board, idx, type) * 0.5;
    }
    return score;
  }

  double _countAdjacentFriendly(BitboardState board, int idx, PieceType type) {
    int count = 0;
    int r = indexToRow(idx), c = indexToCol(idx);
    const dirs = [[-1, 0], [1, 0], [0, -1], [0, 1]];
    for (var d in dirs) {
      int nr = r + d[0], nc = c + d[1];
      if (_isValidPosition(nr, nc)) {
        int nIdx = rcToIndex(nr, nc);
        if (_isOccupied(board, nIdx) && board.getPieceAt(nr, nc)!.type == type) count++;
      }
    }
    return count * 0.5;
  }

  double _detectThreats(BitboardState board, PieceType aiPlayerType, PieceType opponentPlayerType, GameRules rules) {
    double threatScore = 0;
    const double immediateCaptureBaseBonus = 30.0;
    const double chainCaptureMultiplier = 1.5;

    List<FullCaptureSequence> aiSequences = _getAllPossibleCaptureSequences(board, aiPlayerType, rules);
    if (aiSequences.isNotEmpty) {
      double bestAiCaptureValue = 0;
      for (var seq in aiSequences) {
        double value = seq.numCaptures * _manMaterialBaseValue;
        if (seq.numCaptures > 1) value *= chainCaptureMultiplier;
        bestAiCaptureValue = max(bestAiCaptureValue, value);
      }
      threatScore += immediateCaptureBaseBonus + bestAiCaptureValue;
    }

    List<FullCaptureSequence> oppSequences = _getAllPossibleCaptureSequences(board, opponentPlayerType, rules);
    if (oppSequences.isNotEmpty) {
      double bestOppCaptureValue = 0;
      for (var seq in oppSequences) {
        double value = seq.numCaptures * _manMaterialBaseValue;
        if (seq.numCaptures > 1) value *= chainCaptureMultiplier;
        bestOppCaptureValue = max(bestOppCaptureValue, value);
      }
      threatScore -= (immediateCaptureBaseBonus + bestOppCaptureValue);
    }
    return threatScore;
  }

  List<FullCaptureSequence> _getAllPossibleCaptureSequences(BitboardState board, PieceType player, GameRules rules) {
    List<FullCaptureSequence> allSequences = [];
    int piecesBB = player == PieceType.black ? (board.blackMen | board.blackKings) : (board.redMen | board.redKings);
    while (piecesBB != 0) {
      int idx = popLsb(piecesBB);
      if (idx == -1) break;
      piecesBB &= ~(1 << idx);
      Piece? piece = board.getPieceAt(indexToRow(idx), indexToCol(idx));
      if (piece != null) {
        BoardPosition pos = BoardPosition(indexToRow(idx), indexToCol(idx));
        allSequences.addAll(_findAllCaptureSequencesForPieceLocal(
          pos, piece, board, player, [pos], 0, rules));
      }
    }
    return allSequences;
  }

  List<FullCaptureSequence> _findAllCaptureSequencesForPieceLocal(
    BoardPosition currentPiecePos,
    Piece piece,
    BitboardState boardState,
    PieceType activePlayer,
    List<BoardPosition> pathSoFar,
    int capturesSoFar,
    GameRules rules,
  ) {
    List<FullCaptureSequence> allFoundSequences = [];
    Set<BoardPosition> nextJumps = rules.getJumpMoves(currentPiecePos, piece, boardState);

    if (nextJumps.isEmpty && capturesSoFar > 0) {
      allFoundSequences.add(FullCaptureSequence(
        initialFromPos: pathSoFar.first,
        firstStepToPos: pathSoFar.length > 1 ? pathSoFar[1] : currentPiecePos,
        fullPath: pathSoFar,
        numCaptures: capturesSoFar,
        finalBoardState: boardState,
      ));
      return allFoundSequences;
    }

    int fromIdx = rcToIndex(currentPiecePos.row, currentPiecePos.col);
    for (BoardPosition nextPos in nextJumps) {
      int toIdx = rcToIndex(nextPos.row, nextPos.col);
      BitboardState nextBoard = _copyBoard(boardState);
      BoardPosition? capturedPos;

      if (piece.isKing) {
        int dr = (nextPos.row - currentPiecePos.row).sign;
        int dc = (nextPos.col - currentPiecePos.col).sign;
        int checkR = currentPiecePos.row + dr, checkC = currentPiecePos.col + dc;
        int opponentCount = 0;
        while (checkR != nextPos.row || checkC != nextPos.col) {
          if (!_isValidPosition(checkR, checkC)) {
            capturedPos = null;
            break;
          }
          int idx = rcToIndex(checkR, checkC);
          if (_isOccupied(nextBoard, idx)) {
            if (nextBoard.getPieceAt(checkR, checkC)!.type != activePlayer) {
              opponentCount++;
              if (opponentCount == 1) capturedPos = BoardPosition(checkR, checkC);
              else {
                capturedPos = null;
                break;
              }
            } else {
              capturedPos = null;
              break;
            }
          }
          checkR += dr;
          checkC += dc;
        }
        if (opponentCount != 1) capturedPos = null;
      } else {
        int capR = (currentPiecePos.row + nextPos.row) ~/ 2;
        int capC = (currentPiecePos.col + nextPos.col) ~/ 2;
        capturedPos = BoardPosition(capR, capC);
      }

      if (capturedPos == null) continue;
      int capIdx = rcToIndex(capturedPos.row, capturedPos.col);
      if (!_isOccupied(nextBoard, capIdx) || nextBoard.getPieceAt(capturedPos.row, capturedPos.col)!.type == activePlayer) continue;

      // Update bitboards
      if (piece.type == PieceType.black) {
        if (piece.isKing) {
          nextBoard.blackKings &= ~(1 << fromIdx);
          nextBoard.blackKings |= 1 << toIdx;
        } else {
          nextBoard.blackMen &= ~(1 << fromIdx);
          if (nextPos.row == 7) {
            nextBoard.blackKings |= 1 << toIdx;
          } else {
            nextBoard.blackMen |= 1 << toIdx;
          }
        }
      } else {
        if (piece.isKing) {
          nextBoard.redKings &= ~(1 << fromIdx);
          nextBoard.redKings |= 1 << toIdx;
        } else {
          nextBoard.redMen &= ~(1 << fromIdx);
          if (nextPos.row == 0) {
            nextBoard.redKings |= 1 << toIdx;
          } else {
            nextBoard.redMen |= 1 << toIdx;
          }
        }
      }

      // Remove captured piece
      if (nextBoard.blackMen.isSet(capIdx)) nextBoard.blackMen &= ~(1 << capIdx);
      else if (nextBoard.blackKings.isSet(capIdx)) nextBoard.blackKings &= ~(1 << capIdx);
      else if (nextBoard.redMen.isSet(capIdx)) nextBoard.redMen &= ~(1 << capIdx);
      else if (nextBoard.redKings.isSet(capIdx)) nextBoard.redKings &= ~(1 << capIdx);

      Piece nextPiece = Piece(type: piece.type, isKing: piece.isKing || rules_shouldBecomeKing(nextPos, piece, rules));
      List<BoardPosition> nextPath = List.from(pathSoFar)..add(nextPos);
      allFoundSequences.addAll(_findAllCaptureSequencesForPieceLocal(
        nextPos, nextPiece, nextBoard, activePlayer, nextPath, capturesSoFar + 1, rules));
    }
    return allFoundSequences;
  }

  bool rules_shouldBecomeKing(BoardPosition pos, Piece piece, GameRules rules) {
    if (piece.isKing) return false;
    return (piece.type == PieceType.black && pos.row == 7) || (piece.type == PieceType.red && pos.row == 0);
  }

  double _analyzeOpponentThreats(BitboardState board, PieceType opponentType, PieceType aiPlayerType, GameRules rules) {
    double threatValue = 0;
    List<FullCaptureSequence> oppSequences = _getAllPossibleCaptureSequences(board, opponentType, rules);
    for (var seq in oppSequences) {
      threatValue += seq.numCaptures * _manMaterialBaseValue;
    }
    return -threatValue;
  }

  BitboardState _copyBoard(BitboardState board) {
    return BitboardState(
      blackMen: board.blackMen,
      blackKings: board.blackKings,
      redMen: board.redMen,
      redKings: board.redKings,
    );
  }
}

// Extensions
extension PieceTypeExtension on PieceType {
  PieceType get opposite => this == PieceType.red ? PieceType.black : PieceType.red;
}

extension BitboardExtension on int {
  bool isSet(int index) => (this & (1 << index)) != 0;
  int countBits() {
    int n = this, count = 0;
    while (n != 0) {
      count += n & 1;
      n >>= 1;
    }
    return count;
  }
}