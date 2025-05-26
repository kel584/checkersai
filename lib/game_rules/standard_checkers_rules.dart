// lib/game_rules/standard_checkers_rules.dart
import '../models/piece_model.dart';
import '../models/bitboard_state.dart'; // Import your BitboardState
import '../utils/bit_utils.dart' hide rcToIndex, indexToCol, indexToRow;     // Import your bit utility functions
import 'game_rules.dart';
import 'game_status.dart';
import '../ai_evaluators/board_evaluator.dart';
import '../ai_evaluators/standard_checkers_evaluator.dart';

class StandardCheckersRules extends GameRules {
  @override
  String get gameVariantName => "Standard Checkers (Bitboard)";

  @override
  PieceType get startingPlayer => PieceType.red; // Red typically starts in American Checkers

  @override
  bool get piecesOnDarkSquaresOnly => true;

// These prevent wrap-around when shifting for diagonal moves.
  // Assumes square 0 (A1) is LSB, square 63 (H8) is MSB.
  static const int _notAFile = 0xFEFEFEFEFEFEFEFE; // ~0x0101010101010101 (for leftward moves)
  static const int _notHFile = 0x7F7F7F7F7F7F7F7F; // ~0x8080808080808080 (for rightward moves)
  // Masks for jumps (preventing jumps off 2 files)
  static const int _notABFile = 0xFCFCFCFCFCFCFCFC; // ~0x0303030303030303 (for leftward jumps)
  static const int _notGHFile = 0x3F3F3F3F3F3F3F3F; // ~0xC0C0C0C0C0C0C0C0 (for rightward jumps)e.

  @override
  BitboardState initialBoardSetup() {
    BitboardState bitboards = BitboardState();

    // Black pieces (traditionally at top, rows 0, 1, 2 on dark squares)
    // Black moves towards higher indices (e.g. A3(16) to B4(25) is +9)
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 8; c++) {
        if ((r + c) % 2 != 0) { // Dark square
          bitboards.blackMen = setBit(bitboards.blackMen, rcToIndex(r, c));
        }
      }
    }

    // Red pieces (traditionally at bottom, rows 5, 6, 7 on dark squares)
    // Red moves towards lower indices (e.g. H6(47) to G5(38) is -9)
    for (int r = 5; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        if ((r + c) % 2 != 0) { // Dark square
          bitboards.redMen = setBit(bitboards.redMen, rcToIndex(r, c));
        }
      }
    }
    return bitboards;
  }

  // Helper to convert bitboard of moves originating from a single 'from' square
  // back to a Set<BoardPosition> for that 'from' square.
  Set<BoardPosition> _bitboardToDestinations(int moveBitboard) {
    Set<BoardPosition> destinations = {};
    for (int i = 0; i < 64; i++) {
      if (isSet(moveBitboard, i)) {
        destinations.add(BoardPosition(i ~/ 8, i % 8));
      }
    }
    return destinations;
  }


  // Generates regular (non-capturing) moves for men of a given player
  Map<BoardPosition, Set<BoardPosition>> _getAllRegularMenMoves(
      BitboardState currentBoard, PieceType player) {
    Map<BoardPosition, Set<BoardPosition>> allMoves = {};
    int menToMove = (player == PieceType.black) ? currentBoard.blackMen : currentBoard.redMen;
    int emptySquares = currentBoard.allEmptySquares;

    // Define shift amounts for diagonal forward moves
    // Black moves "down" the board (positive shifts if A1=0, H8=63)
    // Red moves "up" the board (negative shifts)
    final int forwardLeftShift = (player == PieceType.black) ? 7 : -9;
    final int forwardRightShift = (player == PieceType.black) ? 9 : -7;

    // Masks to prevent wrap-around
    final int canMoveLeftMask = (player == PieceType.black) ? _notAFile : _notHFile; // Black moving SW needs notAFile, Red moving NW needs notHFile
    final int canMoveRightMask = (player == PieceType.black) ? _notHFile : _notAFile; // Black moving SE needs notHFile, Red moving NE needs notAFile


    for (int i = 0; i < 64; i++) { // Iterate over all possible source squares
      if (isSet(menToMove, i)) { // If there's a man of the current player on this square
        int sourceSquareBit = 1 << i;
        Set<BoardPosition> destinationsForThisPiece = {};

        // Try forward-left move
        if ((sourceSquareBit & canMoveLeftMask) != 0) { // Check if not on edge preventing this move
          int targetSquareBit = (player == PieceType.black) ? sourceSquareBit << forwardLeftShift : sourceSquareBit >> -forwardLeftShift;
          if ((targetSquareBit & emptySquares) != 0) { // If target is empty
             // Ensure target is on board (shift might go off for edge rows - though masks should help files)
             // For simplicity, we can assume shifts on a 64-bit int won't cause issues if masked correctly for files.
             // A more robust check would be if targetSquareIndex is still valid (0-63).
             // However, if targetSquareBit becomes 0 after shifting off board, (targetSquareBit & emptySquares) will be 0.
            destinationsForThisPiece.add(BoardPosition((i + forwardLeftShift) ~/ 8, (i + forwardLeftShift) % 8));
          }
        }

        // Try forward-right move
        if ((sourceSquareBit & canMoveRightMask) != 0) { // Check if not on edge
          int targetSquareBit = (player == PieceType.black) ? sourceSquareBit << forwardRightShift : sourceSquareBit >> -forwardRightShift;
          if ((targetSquareBit & emptySquares) != 0) {
            destinationsForThisPiece.add(BoardPosition((i + forwardRightShift) ~/ 8, (i + forwardRightShift) % 8));
          }
        }
        
        if (destinationsForThisPiece.isNotEmpty) {
          allMoves[BoardPosition(i ~/ 8, i % 8)] = destinationsForThisPiece;
        }
      }
    }
    return allMoves;
  }


  // --- GameRules Interface Methods to be fully implemented with Bitboards ---

  @override
  Set<BoardPosition> getRegularMoves(
    BoardPosition piecePos, // The current position of the piece
    Piece pieceDetails,    // Details of the piece (type, isKing)
    BitboardState currentBoard,
  ) {
    Set<BoardPosition> moves = {};
    final int fromIndex = rcToIndex(piecePos.row, piecePos.col);
    final int emptySquares = currentBoard.allEmptySquares;

    if (pieceDetails.isKing) {
      // King regular moves (all 4 diagonals, 1 step)
      const List<int> kingShifts = [-9, -7, 7, 9]; // NW, NE, SW, SE
      const List<int> kingMasks = [_notAFile, _notHFile, _notAFile, _notHFile]; // For NW/SW, NE/SE respectively for left/right edge check

      for (int i = 0; i < kingShifts.length; i++) {
        int shift = kingShifts[i];
        int targetIndex = fromIndex + shift;
        
        // Check edge conditions based on shift direction
        bool canMove = true;
        if (shift == -9 || shift == 7) { // Moving towards file A (NW or SW)
            if (!isSet(1 << fromIndex, _notAFile)) canMove = false;
        } else if (shift == -7 || shift == 9) { // Moving towards file H (NE or SE)
            if (!isSet(1 << fromIndex, _notHFile)) canMove = false;
        }

        if (canMove && targetIndex >= 0 && targetIndex < 64 && isSet(emptySquares, targetIndex)) {
          moves.add(BoardPosition(indexToRow(targetIndex), indexToCol(targetIndex)));
        }
      }
    } else { // Man regular moves (forward diagonally, 1 step)
      final PieceType player = pieceDetails.type;
      final int forwardLeftShift = (player == PieceType.black) ? 7 : -9;
      final int forwardRightShift = (player == PieceType.black) ? 9 : -7;

      // Forward-left move
      bool canMoveLeft = (player == PieceType.black) ? isSet(1 << fromIndex, _notAFile) : isSet(1 << fromIndex, _notHFile);
      if (canMoveLeft) {
        int targetIndex = fromIndex + forwardLeftShift;
        if (targetIndex >= 0 && targetIndex < 64 && isSet(emptySquares, targetIndex)) {
          moves.add(BoardPosition(indexToRow(targetIndex), indexToCol(targetIndex)));
        }
      }

      // Forward-right move
      bool canMoveRight = (player == PieceType.black) ? isSet(1 << fromIndex, _notHFile) : isSet(1 << fromIndex, _notAFile);
      if (canMoveRight) {
        int targetIndex = fromIndex + forwardRightShift;
        if (targetIndex >= 0 && targetIndex < 64 && isSet(emptySquares, targetIndex)) {
          moves.add(BoardPosition(indexToRow(targetIndex), indexToCol(targetIndex)));
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
    Set<BoardPosition> jumps = {};
    final int fromIndex = rcToIndex(piecePos.row, piecePos.col);
    final int emptySquares = currentBoard.allEmptySquares;
    final int opponentPieces = (pieceDetails.type == PieceType.black)
        ? currentBoard.allRedPieces
        : currentBoard.allBlackPieces;

    List<int> jumpOverShifts = []; // Shifts to the square TO BE JUMPED
    List<int> landShifts = [];     // Corresponding shifts to the LANDING square
    List<int> jumpEdgeMasks = [];  // Masks to prevent jumping off 2 files

    if (pieceDetails.isKing) {
      jumpOverShifts = [7, 9, -7, -9]; // SW, SE, NE, NW
      landShifts     = [14, 18, -14, -18];
      jumpEdgeMasks  = [_notABFile, _notGHFile, _notGHFile, _notABFile];
    } else if (pieceDetails.type == PieceType.black) {
      jumpOverShifts = [7, 9]; // SW, SE
      landShifts     = [14, 18];
      jumpEdgeMasks  = [_notABFile, _notGHFile];
    } else { // Red Men
      jumpOverShifts = [-9, -7]; // NW, NE
      landShifts     = [-18, -14];
      jumpEdgeMasks  = [_notABFile, _notGHFile]; // Red NW needs notABFile, Red NE needs notGHFile
    }
    
    final int pieceBit = 1 << fromIndex;

    for (int i = 0; i < jumpOverShifts.length; i++) {
      int jumpOverShift = jumpOverShifts[i];
      int landShift = landShifts[i];
      int edgeMask = jumpEdgeMasks[i];

      if (isSet(pieceBit, edgeMask)) { // Check if piece is not too close to the edge for a jump
        int opponentSquareIndex = fromIndex + jumpOverShift;
        int landingSquareIndex = fromIndex + landShift; // This is equivalent to fromIndex + jumpOverShift*2, which is wrong.
                                                      // landShift should be jumpOverShift * 2 relative to fromIndex
                                                      // Or more simply, opponentSquareIndex + jumpOverShift
        landingSquareIndex = opponentSquareIndex + jumpOverShift;


        if (opponentSquareIndex >= 0 && opponentSquareIndex < 64 && // Opponent square on board
            landingSquareIndex >= 0 && landingSquareIndex < 64 && // Landing square on board
            isSet(opponentPieces, opponentSquareIndex) &&       // Opponent piece is on the intermediate square
            isSet(emptySquares, landingSquareIndex)) {          // Landing square is empty
          jumps.add(BoardPosition(indexToRow(landingSquareIndex), indexToCol(landingSquareIndex)));
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

    Piece? movedPieceDetails;
    bool pieceKingedThisMove = false;
    bool wasActualJumpPerformed = false;

    // Identify the piece being moved and update its bitboard
    if (isSet(nextBoard.blackMen, fromIndex)) {
      movedPieceDetails = Piece(type: PieceType.black, isKing: false);
      nextBoard.blackMen = clearBit(nextBoard.blackMen, fromIndex);
      nextBoard.blackMen = setBit(nextBoard.blackMen, toIndex);
    } else if (isSet(nextBoard.blackKings, fromIndex)) {
      movedPieceDetails = Piece(type: PieceType.black, isKing: true);
      nextBoard.blackKings = clearBit(nextBoard.blackKings, fromIndex);
      nextBoard.blackKings = setBit(nextBoard.blackKings, toIndex);
    } else if (isSet(nextBoard.redMen, fromIndex)) {
      movedPieceDetails = Piece(type: PieceType.red, isKing: false);
      nextBoard.redMen = clearBit(nextBoard.redMen, fromIndex);
      nextBoard.redMen = setBit(nextBoard.redMen, toIndex);
    } else if (isSet(nextBoard.redKings, fromIndex)) {
      movedPieceDetails = Piece(type: PieceType.red, isKing: true);
      nextBoard.redKings = clearBit(nextBoard.redKings, fromIndex);
      nextBoard.redKings = setBit(nextBoard.redKings, toIndex);
    }

    if (movedPieceDetails == null) {
      // Should not happen if 'from' is valid
      return MoveResult(board: currentBoard, turnChanged: true);
    }

    // Check for capture (Standard Checkers: jump is always 2 steps diagonally)
    if ((from.row - to.row).abs() == 2 && (from.col - to.col).abs() == 2) {
      wasActualJumpPerformed = true;
      int capturedRow = (from.row + to.row) ~/ 2;
      int capturedCol = (from.col + to.col) ~/ 2;
      int capturedIndex = rcToIndex(capturedRow, capturedCol);

      // Remove the captured piece from all opponent bitboards
      nextBoard.blackMen = clearBit(nextBoard.blackMen, capturedIndex);
      nextBoard.blackKings = clearBit(nextBoard.blackKings, capturedIndex);
      nextBoard.redMen = clearBit(nextBoard.redMen, capturedIndex);
      nextBoard.redKings = clearBit(nextBoard.redKings, capturedIndex);
    }

    // Kinging
    bool shouldKing = false;
    if (!movedPieceDetails.isKing) {
      if (movedPieceDetails.type == PieceType.black && to.row == 7) shouldKing = true;
      if (movedPieceDetails.type == PieceType.red && to.row == 0) shouldKing = true;
    }

    if (shouldKing) {
      pieceKingedThisMove = true;
      // Update bitboards: remove from men, add to kings
      if (movedPieceDetails.type == PieceType.black) {
        nextBoard.blackMen = clearBit(nextBoard.blackMen, toIndex);
        nextBoard.blackKings = setBit(nextBoard.blackKings, toIndex);
      } else { // Red
        nextBoard.redMen = clearBit(nextBoard.redMen, toIndex);
        nextBoard.redKings = setBit(nextBoard.redKings, toIndex);
      }
      // Update movedPieceDetails for getFurtherJumps if it needs the Piece object
      movedPieceDetails = Piece(type: movedPieceDetails.type, isKing: true);
    }
    
    bool turnShouldChange = true;
    if (wasActualJumpPerformed) {
      // For the piece that just moved (now at 'to'), check for further jumps.
      // We need its current state (especially if it just kinged).
      final pieceAtTo = movedPieceDetails; // Already updated if kinged
      Set<BoardPosition> furtherJumps = getFurtherJumps(to, pieceAtTo, nextBoard);
      if (furtherJumps.isNotEmpty) {
        turnShouldChange = false; // Multi-jump pending
      }
    }

    return MoveResult(
      board: nextBoard,
      turnChanged: turnShouldChange,
      pieceKinged: pieceKingedThisMove,
    );
  }

@override
  Set<BoardPosition> getFurtherJumps(
    BoardPosition piecePos,
    Piece pieceDetails, // Piece at piecePos, potentially just kinged
    BitboardState currentBoard,
  ) {
    // For standard checkers, further jumps are calculated the same way as initial jumps
    // but using the piece's current (possibly kinged) state from its new position.
    return getJumpMoves(piecePos, pieceDetails, currentBoard);
  }

  @override
  Map<BoardPosition, Set<BoardPosition>> getAllMovesForPlayer(
    BitboardState currentBoard,
    PieceType player,
    bool jumpsOnlyFlag_NotUsed, // The 'jumpsOnly' flag is implicitly handled by mandatory jump rule
  ) {
    Map<BoardPosition, Set<BoardPosition>> allValidMoves = {};
    List<MapEntry<BoardPosition, Set<BoardPosition>>> allPossibleJumps = [];

    int playerMen = (player == PieceType.black) ? currentBoard.blackMen : currentBoard.redMen;
    int playerKings = (player == PieceType.black) ? currentBoard.blackKings : currentBoard.redKings;

    // Check Jumps for Men
    for (int i = 0; i < 64; i++) {
      if (isSet(playerMen, i)) {
        BoardPosition fromPos = BoardPosition(indexToRow(i), indexToCol(i));
        Piece manDetails = Piece(type: player, isKing: false);
        Set<BoardPosition> jumps = getJumpMoves(fromPos, manDetails, currentBoard);
        if (jumps.isNotEmpty) {
          allPossibleJumps.add(MapEntry(fromPos, jumps));
        }
      }
    }

    // Check Jumps for Kings
    for (int i = 0; i < 64; i++) {
      if (isSet(playerKings, i)) {
        BoardPosition fromPos = BoardPosition(indexToRow(i), indexToCol(i));
        Piece kingDetails = Piece(type: player, isKing: true);
        Set<BoardPosition> jumps = getJumpMoves(fromPos, kingDetails, currentBoard);
        if (jumps.isNotEmpty) {
          allPossibleJumps.add(MapEntry(fromPos, jumps));
        }
      }
    }

    if (allPossibleJumps.isNotEmpty) {
      // Mandatory jump rule: only jumps are allowed.
      // Here, we'd implement logic for "must complete sequence" / "maximal capture" if desired.
      // For now, we return all possible first jumps. Multi-jumps are handled iteratively
      // by GameScreenState calling getFurtherJumps.
      for (var entry in allPossibleJumps) {
        allValidMoves[entry.key] = entry.value;
      }
      return allValidMoves;
    }

    // If no jumps, then gather regular moves
    // Regular Moves for Men
    for (int i = 0; i < 64; i++) {
      if (isSet(playerMen, i)) {
        BoardPosition fromPos = BoardPosition(indexToRow(i), indexToCol(i));
        Piece manDetails = Piece(type: player, isKing: false);
        Set<BoardPosition> moves = getRegularMoves(fromPos, manDetails, currentBoard);
        if (moves.isNotEmpty) {
          allValidMoves[fromPos] = moves;
        }
      }
    }

    // Regular Moves for Kings
    for (int i = 0; i < 64; i++) {
      if (isSet(playerKings, i)) {
        BoardPosition fromPos = BoardPosition(indexToRow(i), indexToCol(i));
        Piece kingDetails = Piece(type: player, isKing: true);
        Set<BoardPosition> moves = getRegularMoves(fromPos, kingDetails, currentBoard);
        if (moves.isNotEmpty) {
          allValidMoves[fromPos] = moves;
        }
      }
    }
    return allValidMoves;
  }

@override
  GameStatus checkWinCondition({
    required BitboardState currentBoard,
    required PieceType currentPlayer,
    required Map<BoardPosition, Set<BoardPosition>> allPossibleJumpsForCurrentPlayer,
    required Map<BoardPosition, Set<BoardPosition>> allPossibleRegularMovesForCurrentPlayer,
    required Map<String, int> boardStateCounts,
  }) {
    String currentBoardHash = generateBoardStateHash(currentBoard, currentPlayer);
    if ((boardStateCounts[currentBoardHash] ?? 0) >= 3) {
      return GameStatus.draw(GameEndReason.threefoldRepetition);
    }

    bool currentPlayerHasPieces = false;
    if (currentPlayer == PieceType.red) {
      if (currentBoard.allRedPieces != 0) currentPlayerHasPieces = true;
    } else { // Black
      if (currentBoard.allBlackPieces != 0) currentPlayerHasPieces = true;
    }

    if (!currentPlayerHasPieces) {
      return GameStatus.win(
          (currentPlayer == PieceType.red) ? PieceType.black : PieceType.red,
          GameEndReason.noPiecesLeft);
    }

    // allPossibleJumps and allPossibleRegularMoves are passed in from GameScreenState,
    // which should have called a bitboard-based getAllMovesForPlayer.
    if (allPossibleJumpsForCurrentPlayer.isEmpty && allPossibleRegularMovesForCurrentPlayer.isEmpty) {
      return GameStatus.win(
          (currentPlayer == PieceType.red) ? PieceType.black : PieceType.red,
          GameEndReason.noMovesLeft);
    }
    
    return GameStatus.ongoing();
  }

  @override
    String generateBoardStateHash(BitboardState currentBoard, PieceType playerToMove) {
      // A more robust hash would be Zobrist hashing.
      // For simplicity now, a string based on the bitboard integers.
      return '${playerToMove.name}:'
            'BM${currentBoard.blackMen}:'
            'BK${currentBoard.blackKings}:'
            'RM${currentBoard.redMen}:'
            'RK${currentBoard.redKings}';
    }

  @override
  bool isMaximalCaptureMandatory() => false; // Standard checkers often has this, can be true later.

  // --- Provide the specific evaluator ---
  final StandardCheckersEvaluator _evaluator = StandardCheckersEvaluator();
  @override
  BoardEvaluator get boardEvaluator => _evaluator;
}