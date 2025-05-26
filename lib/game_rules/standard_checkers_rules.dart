// lib/game_rules/standard_checkers_rules.dart
import '../models/piece_model.dart';
import '../models/bitboard_state.dart';
import '../utils/bit_utils.dart' hide rcToIndex, indexToCol, indexToRow;
import 'game_rules.dart';
import 'game_status.dart';
import '../ai_evaluators/board_evaluator.dart';
import '../ai_evaluators/standard_checkers_evaluator.dart';

class StandardCheckersRules extends GameRules {
  @override
  String get gameVariantName => "Standard Checkers (Bitboard)";

  @override
  PieceType get startingPlayer => PieceType.red;

  @override
  bool get piecesOnDarkSquaresOnly => true;

  // Optimized bit masks for edge detection
  static const int _notAFile = 0xFEFEFEFEFEFEFEFE; // Prevent left wrapping
  static const int _notHFile = 0x7F7F7F7F7F7F7F7F; // Prevent right wrapping
  static const int _notABFile = 0xFCFCFCFCFCFCFCFC; // Prevent double-left wrapping (jumps)
  static const int _notGHFile = 0x3F3F3F3F3F3F3F3F; // Prevent double-right wrapping (jumps)
  static const int _notRank1 = 0xFFFFFFFFFFFFFF00; // Prevent wrapping below rank 1
  static const int _notRank12 = 0xFFFFFFFFFFFF0000; // Prevent double wrapping below rank 2
  static const int _notRank8 = 0x00FFFFFFFFFFFFFF; // Prevent wrapping above rank 8
  static const int _notRank78 = 0x0000FFFFFFFFFFFF; // Prevent double wrapping above rank 7

  // Precomputed shift directions for performance
  static const Map<String, int> _moveShifts = {
    'blackSW': 7,   // Black southwest (down-left)
    'blackSE': 9,   // Black southeast (down-right)
    'redNW': -9,    // Red northwest (up-left)
    'redNE': -7,    // Red northeast (up-right)
  };

  @override
  BitboardState initialBoardSetup() {
    BitboardState bitboards = BitboardState();

    // Use bit operations for faster setup
    // Black pieces on rows 0-2, dark squares only
    for (int row = 0; row < 3; row++) {
      int rowBits = (row % 2 == 0) ? 0xAA : 0x55; // Alternating pattern for dark squares
      bitboards.blackMen |= (rowBits << (row * 8));
    }

    // Red pieces on rows 5-7, dark squares only
    for (int row = 5; row < 8; row++) {
      int rowBits = (row % 2 == 0) ? 0xAA : 0x55;
      bitboards.redMen |= (rowBits << (row * 8));
    }

    return bitboards;
  }

  // Optimized helper to convert single bit position to BoardPosition
  BoardPosition _indexToPosition(int index) {
    return BoardPosition(index >> 3, index & 7); // Faster than division/modulo
  }

  // Fast bit scan for finding set bits
  Set<BoardPosition> _bitboardToPositions(int bitboard) {
    Set<BoardPosition> positions = <BoardPosition>{};
    while (bitboard != 0) {
      int index = bitboard & -bitboard; // Isolate lowest set bit
      int bitIndex = _trailingZeros(bitboard);
      positions.add(_indexToPosition(bitIndex));
      bitboard &= bitboard - 1; // Clear lowest set bit
    }
    return positions;
  }

  // Count trailing zeros - faster than loop for bit scanning
  int _trailingZeros(int value) {
    if (value == 0) return 64;
    int count = 0;
    if ((value & 0xFFFFFFFF) == 0) { value >>= 32; count += 32; }
    if ((value & 0xFFFF) == 0) { value >>= 16; count += 16; }
    if ((value & 0xFF) == 0) { value >>= 8; count += 8; }
    if ((value & 0xF) == 0) { value >>= 4; count += 4; }
    if ((value & 0x3) == 0) { value >>= 2; count += 2; }
    if ((value & 0x1) == 0) { count += 1; }
    return count;
  }

  @override
  Set<BoardPosition> getRegularMoves(
    BoardPosition piecePos,
    Piece pieceDetails,
    BitboardState currentBoard,
  ) {
    final int fromIndex = rcToIndex(piecePos.row, piecePos.col);
    
    // Bounds check
    if (fromIndex < 0 || fromIndex >= 64) return <BoardPosition>{};
    
    final int fromBit = 1 << fromIndex;
    final int emptySquares = currentBoard.allEmptySquares;
    Set<BoardPosition> moves = <BoardPosition>{};

    if (pieceDetails.isKing) {
      // King moves in all 4 diagonal directions
      final shifts = [-9, -7, 7, 9]; // NW, NE, SW, SE
      final masks = [_notAFile & _notRank1, _notHFile & _notRank1, 
                     _notAFile & _notRank8, _notHFile & _notRank8];

      for (int i = 0; i < 4; i++) {
        if ((fromBit & masks[i]) != 0) {
          int targetIndex = fromIndex + shifts[i];
          if (targetIndex >= 0 && targetIndex < 64 && 
              isSet(emptySquares, targetIndex)) {
            moves.add(_indexToPosition(targetIndex));
          }
        }
      }
    } else {
      // Men move forward only
      if (pieceDetails.type == PieceType.black) {
        // Black moves down the board
        if ((fromBit & _notAFile & _notRank8) != 0) {
          int targetIndex = fromIndex + 7; // SW
          if (targetIndex < 64 && isSet(emptySquares, targetIndex)) {
            moves.add(_indexToPosition(targetIndex));
          }
        }
        if ((fromBit & _notHFile & _notRank8) != 0) {
          int targetIndex = fromIndex + 9; // SE
          if (targetIndex < 64 && isSet(emptySquares, targetIndex)) {
            moves.add(_indexToPosition(targetIndex));
          }
        }
      } else {
        // Red moves up the board
        if ((fromBit & _notHFile & _notRank1) != 0) {
          int targetIndex = fromIndex - 7; // NE
          if (targetIndex >= 0 && isSet(emptySquares, targetIndex)) {
            moves.add(_indexToPosition(targetIndex));
          }
        }
        if ((fromBit & _notAFile & _notRank1) != 0) {
          int targetIndex = fromIndex - 9; // NW
          if (targetIndex >= 0 && isSet(emptySquares, targetIndex)) {
            moves.add(_indexToPosition(targetIndex));
          }
        }
      }
    }

    return moves;
  }

  @override
  Set<BoardPosition> getJumpMoves(
    BoardPosition piecePos,
    Piece pieceDetails,
    BitboardState currentBoard,
  ) {
    final int fromIndex = rcToIndex(piecePos.row, piecePos.col);
    
    // Bounds check
    if (fromIndex < 0 || fromIndex >= 64) return <BoardPosition>{};
    
    final int fromBit = 1 << fromIndex;
    final int emptySquares = currentBoard.allEmptySquares;
    final int opponentPieces = (pieceDetails.type == PieceType.black)
        ? currentBoard.allRedPieces
        : currentBoard.allBlackPieces;

    Set<BoardPosition> jumps = <BoardPosition>{};

    // Define jump patterns based on piece type
    List<int> jumpShifts = [];
    List<int> edgeMasks = [];

    if (pieceDetails.isKing) {
      jumpShifts = [-18, -14, 14, 18]; // NW, NE, SW, SE (2 squares)
      edgeMasks = [
        _notABFile & _notRank12,  // NW
        _notGHFile & _notRank12,  // NE
        _notABFile & _notRank78,  // SW
        _notGHFile & _notRank78   // SE
      ];
    } else if (pieceDetails.type == PieceType.black) {
      jumpShifts = [14, 18]; // SW, SE
      edgeMasks = [_notABFile & _notRank78, _notGHFile & _notRank78];
    } else {
      jumpShifts = [-18, -14]; // NW, NE
      edgeMasks = [_notABFile & _notRank12, _notGHFile & _notRank12];
    }

    for (int i = 0; i < jumpShifts.length; i++) {
      if ((fromBit & edgeMasks[i]) != 0) {
        int jumpShift = jumpShifts[i];
        int middleIndex = fromIndex + (jumpShift >> 1); // Divide by 2 for middle square
        int landIndex = fromIndex + jumpShift;

        // Verify all indices are valid
        if (middleIndex >= 0 && middleIndex < 64 && 
            landIndex >= 0 && landIndex < 64 &&
            isSet(opponentPieces, middleIndex) &&
            isSet(emptySquares, landIndex)) {
          jumps.add(_indexToPosition(landIndex));
        }
      }
    }

    return jumps;
  }

  @override
  MoveResult applyMoveAndGetResult({
    required BitboardState currentBoard,
    required BoardPosition from,
    required BoardPosition to,
    required PieceType currentPlayer,
  }) {
    BitboardState nextBoard = currentBoard.copy();
    final int fromIndex = rcToIndex(from.row, from.col);
    final int toIndex = rcToIndex(to.row, to.col);

    // Bounds checking
    if (fromIndex < 0 || fromIndex >= 64 || toIndex < 0 || toIndex >= 64) {
      return MoveResult(board: currentBoard, turnChanged: true);
    }

    Piece? movedPiece;
    bool wasJump = false;
    bool pieceKinged = false;

    // Identify and move the piece efficiently
    final int fromBit = 1 << fromIndex;
    final int toBit = 1 << toIndex;

    if ((nextBoard.blackMen & fromBit) != 0) {
      movedPiece = Piece(type: PieceType.black, isKing: false);
      nextBoard.blackMen = (nextBoard.blackMen & ~fromBit) | toBit;
    } else if ((nextBoard.blackKings & fromBit) != 0) {
      movedPiece = Piece(type: PieceType.black, isKing: true);
      nextBoard.blackKings = (nextBoard.blackKings & ~fromBit) | toBit;
    } else if ((nextBoard.redMen & fromBit) != 0) {
      movedPiece = Piece(type: PieceType.red, isKing: false);
      nextBoard.redMen = (nextBoard.redMen & ~fromBit) | toBit;
    } else if ((nextBoard.redKings & fromBit) != 0) {
      movedPiece = Piece(type: PieceType.red, isKing: true);
      nextBoard.redKings = (nextBoard.redKings & ~fromBit) | toBit;
    }

    if (movedPiece == null) {
      return MoveResult(board: currentBoard, turnChanged: true);
    }

    // Check for jump (Manhattan distance of 4 indicates diagonal jump of 2)
    int rowDiff = (from.row - to.row).abs();
    int colDiff = (from.col - to.col).abs();
    
    if (rowDiff == 2 && colDiff == 2) {
      wasJump = true;
      int capturedRow = (from.row + to.row) >> 1; // Faster division by 2
      int capturedCol = (from.col + to.col) >> 1;
      int capturedIndex = rcToIndex(capturedRow, capturedCol);
      
      if (capturedIndex >= 0 && capturedIndex < 64) {
        int capturedBit = 1 << capturedIndex;
        // Clear captured piece from all bitboards
        nextBoard.blackMen &= ~capturedBit;
        nextBoard.blackKings &= ~capturedBit;
        nextBoard.redMen &= ~capturedBit;
        nextBoard.redKings &= ~capturedBit;
      }
    }

    // Check for kinging
    if (!movedPiece.isKing) {
      bool shouldKing = (movedPiece.type == PieceType.black && to.row == 7) ||
                       (movedPiece.type == PieceType.red && to.row == 0);
      
      if (shouldKing) {
        pieceKinged = true;
        if (movedPiece.type == PieceType.black) {
          nextBoard.blackMen &= ~toBit;
          nextBoard.blackKings |= toBit;
        } else {
          nextBoard.redMen &= ~toBit;
          nextBoard.redKings |= toBit;
        }
        movedPiece = Piece(type: movedPiece.type, isKing: true);
      }
    }

    // Check for further jumps
    bool turnChanged = true;
    if (wasJump) {
      Set<BoardPosition> furtherJumps = getFurtherJumps(to, movedPiece, nextBoard);
      if (furtherJumps.isNotEmpty) {
        turnChanged = false;
      }
    }

    return MoveResult(
      board: nextBoard,
      turnChanged: turnChanged,
      pieceKinged: pieceKinged,
    );
  }

  @override
  Set<BoardPosition> getFurtherJumps(
    BoardPosition piecePos,
    Piece pieceDetails,
    BitboardState currentBoard,
  ) {
    return getJumpMoves(piecePos, pieceDetails, currentBoard);
  }

  @override
  Map<BoardPosition, Set<BoardPosition>> getAllMovesForPlayer(
    BitboardState currentBoard,
    PieceType player,
    bool jumpsOnlyFlag,
  ) {
    Map<BoardPosition, Set<BoardPosition>> allMoves = <BoardPosition, Set<BoardPosition>>{};
    Map<BoardPosition, Set<BoardPosition>> allJumps = <BoardPosition, Set<BoardPosition>>{};

    int playerMen = (player == PieceType.black) ? currentBoard.blackMen : currentBoard.redMen;
    int playerKings = (player == PieceType.black) ? currentBoard.blackKings : currentBoard.redKings;

    // Use bit scanning for better performance
    void scanPieces(int bitboard, bool isKing) {
      int remaining = bitboard;
      while (remaining != 0) {
        int index = _trailingZeros(remaining);
        BoardPosition pos = _indexToPosition(index);
        Piece piece = Piece(type: player, isKing: isKing);
        
        Set<BoardPosition> jumps = getJumpMoves(pos, piece, currentBoard);
        if (jumps.isNotEmpty) {
          allJumps[pos] = jumps;
        }
        
        if (allJumps.isEmpty) { // Only get regular moves if no jumps available
          Set<BoardPosition> moves = getRegularMoves(pos, piece, currentBoard);
          if (moves.isNotEmpty) {
            allMoves[pos] = moves;
          }
        }
        
        remaining &= remaining - 1; // Clear the lowest set bit
      }
    }

    // Scan men and kings
    scanPieces(playerMen, false);
    scanPieces(playerKings, true);

    // Return jumps if available (mandatory jump rule), otherwise regular moves
    return allJumps.isNotEmpty ? allJumps : allMoves;
  }

  @override
  GameStatus checkWinCondition({
    required BitboardState currentBoard,
    required PieceType currentPlayer,
    required Map<BoardPosition, Set<BoardPosition>> allPossibleJumpsForCurrentPlayer,
    required Map<BoardPosition, Set<BoardPosition>> allPossibleRegularMovesForCurrentPlayer,
    required Map<String, int> boardStateCounts,
  }) {
    // Check for threefold repetition
    String currentBoardHash = generateBoardStateHash(currentBoard, currentPlayer);
    if ((boardStateCounts[currentBoardHash] ?? 0) >= 3) {
      return GameStatus.draw(GameEndReason.threefoldRepetition);
    }

    // Check if current player has pieces
    int currentPlayerPieces = (currentPlayer == PieceType.red) 
        ? currentBoard.allRedPieces 
        : currentBoard.allBlackPieces;

    if (currentPlayerPieces == 0) {
      PieceType winner = (currentPlayer == PieceType.red) ? PieceType.black : PieceType.red;
      return GameStatus.win(winner, GameEndReason.noPiecesLeft);
    }

    // Check if current player has moves
    if (allPossibleJumpsForCurrentPlayer.isEmpty && allPossibleRegularMovesForCurrentPlayer.isEmpty) {
      PieceType winner = (currentPlayer == PieceType.red) ? PieceType.black : PieceType.red;
      return GameStatus.win(winner, GameEndReason.noMovesLeft);
    }

    return GameStatus.ongoing();
  }

  @override
  String generateBoardStateHash(BitboardState currentBoard, PieceType playerToMove) {
    // Use a more efficient hash combining bit operations
    int hash = playerToMove.index;
    hash = hash * 31 + currentBoard.blackMen.hashCode;
    hash = hash * 31 + currentBoard.blackKings.hashCode;
    hash = hash * 31 + currentBoard.redMen.hashCode;
    hash = hash * 31 + currentBoard.redKings.hashCode;
    return hash.toString();
  }

  @override
  bool isMaximalCaptureMandatory() => false;

  final StandardCheckersEvaluator _evaluator = StandardCheckersEvaluator();
  
  @override
  BoardEvaluator get boardEvaluator => _evaluator;
}