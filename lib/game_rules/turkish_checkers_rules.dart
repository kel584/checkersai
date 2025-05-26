// lib/game_rules/turkish_checkers_rules.dart
import 'dart:math';
import '../models/piece_model.dart';
import '../models/bitboard_state.dart';
import '../utils/bit_utils.dart' hide rcToIndex; // Assumes setBit, clearBit, isSet, rcToIndex, indexToRow, indexToCol
import 'game_rules.dart';
import 'game_status.dart';
import '../ai_evaluators/board_evaluator.dart';
import '../ai_evaluators/turkish_checkers_evaluator.dart';


// Re-defining FullCaptureSequence here for self-containment, or import if in its own file
class FullCaptureSequence {
  final BoardPosition initialFromPos;
  final BoardPosition firstStepToPos;
  final List<BoardPosition> fullPath; // Sequence of landing squares, starting from initialFromPos
  final int numCaptures;
  final BitboardState finalBoardState; // Board state after this sequence

  FullCaptureSequence({
    required this.initialFromPos,
    required this.firstStepToPos,
    required this.fullPath,
    required this.numCaptures,
    required this.finalBoardState,
  });
}

class TurkishCheckersRules extends GameRules {
  @override
  String get gameVariantName => "Turkish Checkers (Bitboard)";

  @override
  PieceType get startingPlayer => PieceType.red; // Traditionally White (often represented by Red)

  @override
  bool get piecesOnDarkSquaresOnly => false; // Pieces use all squares

  // --- Bitboard Masks ---
  static const int _notAFile = 0xFEFEFEFEFEFEFEFE; // ~0x0101010101010101
  static const int _notHFile = 0x7F7F7F7F7F7F7F7F; // ~0x8080808080808080
  static const int _notRank1 = ~0x00000000000000FF; // For pieces moving "up" (Red)
  static const int _notRank8 = ~0xFF00000000000000; // For pieces moving "down" (Black)
  // For jumps (2 squares away)
  static const int _notABFile = 0xFCFCFCFCFCFCFCFC; // ~0x0303030303030303
  static const int _notGHFile = 0x3F3F3F3F3F3F3F3F; // ~0xC0C0C0C0C0C0C0C0
  static const int _notRank12 = ~0x000000000000FFFF;
  static const int _notRank78 = ~0xFFFF000000000000;


  @override
  BitboardState initialBoardSetup() {
    BitboardState bs = BitboardState();
    // Black pieces (e.g., player starting at "top", rows 1 and 2)
    for (int r = 1; r <= 2; r++) {
      for (int c = 0; c < 8; c++) {
        bs.blackMen = setBit(bs.blackMen, rcToIndex(r, c));
      }
    }
    // Red pieces (e.g., player starting at "bottom", rows 5 and 6)
    for (int r = 5; r <= 6; r++) {
      for (int c = 0; c < 8; c++) {
        bs.redMen = setBit(bs.redMen, rcToIndex(r, c));
      }
    }
    return bs;
  }

  bool _isValidPosition(int r, int c) { // Keep this helper for array-based logic if any persists
    return r >= 0 && r < 8 && c >= 0 && c < 8;
  }

  // Helper to get piece details from bitboards at a given index
  Piece? _getPieceDetailsAtIndex(BitboardState board, int index) {
    if (isSet(board.blackMen, index)) return Piece(type: PieceType.black, isKing: false);
    if (isSet(board.blackKings, index)) return Piece(type: PieceType.black, isKing: true);
    if (isSet(board.redMen, index)) return Piece(type: PieceType.red, isKing: false);
    if (isSet(board.redKings, index)) return Piece(type: PieceType.red, isKing: true);
    return null;
  }

  // --- START OF BITBOARD MOVE GENERATION ---

  // Note: The GameRules interface has getRegularMoves/getJumpMoves for a SINGLE piece.
  // Bitboard logic is often more efficient generating all moves for a TYPE of piece.
  // We'll implement the interface methods, but they might call internal helpers
  // that generate moves for a single piece from its bit.

  @override
  Set<BoardPosition> getRegularMoves(
      BoardPosition piecePos, Piece pieceDetails, BitboardState currentBoard) {
    Set<BoardPosition> moves = {};
    final int fromIndex = rcToIndex(piecePos.row, piecePos.col);
    final int empty = currentBoard.allEmptySquares;

    if (pieceDetails.isKing) { // Dama (King) - Rook-like moves
      const List<List<int>> directions = [[-1,0],[1,0],[0,-1],[0,1]]; // N, S, W, E
      for (var dir in directions) {
        for (int i = 1; i < 8; i++) {
          int toR = piecePos.row + dir[0] * i;
          int toC = piecePos.col + dir[1] * i;
          if (!_isValidPosition(toR, toC)) break;
          int toIndex = rcToIndex(toR, toC);
          if (!isSet(empty, toIndex)) break; // Blocked
          moves.add(BoardPosition(toR, toC));
        }
      }
    } else { // Taş (Man) - Forward or Sideways
      int forwardRowDelta = (pieceDetails.type == PieceType.black) ? 1 : -1; // Black moves R++, Red moves R--
      
      // Forward
      int fR = piecePos.row + forwardRowDelta;
      if (_isValidPosition(fR, piecePos.col) && isSet(empty, rcToIndex(fR, piecePos.col))) {
        moves.add(BoardPosition(fR, piecePos.col));
      }
      // Sideways Left
      int sLC = piecePos.col - 1;
      if (_isValidPosition(piecePos.row, sLC) && isSet(empty, rcToIndex(piecePos.row, sLC))) {
        moves.add(BoardPosition(piecePos.row, sLC));
      }
      // Sideways Right
      int sRC = piecePos.col + 1;
      if (_isValidPosition(piecePos.row, sRC) && isSet(empty, rcToIndex(piecePos.row, sRC))) {
        moves.add(BoardPosition(piecePos.row, sRC));
      }
    }
    return moves;
  }

  @override
  Set<BoardPosition> getJumpMoves(
      BoardPosition piecePos, Piece pieceDetails, BitboardState currentBoard) {
    Set<BoardPosition> jumps = {};
    final int r = piecePos.row;
    final int c = piecePos.col;
    final int fromIndex = rcToIndex(r,c);
    final int empty = currentBoard.allEmptySquares;
    final int opponentPieces = (pieceDetails.type == PieceType.black)
        ? currentBoard.allRedPieces
        : currentBoard.allBlackPieces;

    const List<List<int>> directions = [[-1,0],[1,0],[0,-1],[0,1]]; // N, S, W, E

    if (pieceDetails.isKing) { // Dama (King) jump
      for (var dir in directions) {
        BoardPosition? opponentToJumpPos;
        // 1. Scan for the first piece along the line
        for (int i = 1; i < 8; i++) {
          int checkR = r + dir[0] * i;
          int checkC = c + dir[1] * i;
          if (!_isValidPosition(checkR, checkC)) break;
          
          int checkIndex = rcToIndex(checkR, checkC);
          if (isSet(currentBoard.allOccupiedSquares, checkIndex)) { // Found a piece
            if (isSet(opponentPieces, checkIndex)) { // It's an opponent
              opponentToJumpPos = BoardPosition(checkR, checkC);
            }
            break; // Stop scan whether friendly or opponent
          }
        }
        // 2. If an opponent was found, scan beyond it for empty landing squares
        if (opponentToJumpPos != null) {
          for (int i = 1; i < 8; i++) {
            int landR = opponentToJumpPos.row + dir[0] * i;
            int landC = opponentToJumpPos.col + dir[1] * i;
            if (!_isValidPosition(landR, landC)) break;
            int landIndex = rcToIndex(landR, landC);
            if (isSet(empty, landIndex)) {
              jumps.add(BoardPosition(landR, landC));
            } else {
              break; // Path for landing blocked
            }
          }
        }
      }
    } else { // Taş (Man) jump - Forward or Sideways capture only
      int forwardRowDelta = (pieceDetails.type == PieceType.black) ? 1 : -1;
      final List<List<int>> manJumpDirs = [
        [forwardRowDelta, 0], // Forward jump
        [0, -1],              // Sideways left jump
        [0, 1],               // Sideways right jump
      ];

      for (var dir in manJumpDirs) {
        int jumpOverR = r + dir[0];
        int jumpOverC = c + dir[1];
        int landR = r + dir[0] * 2;
        int landC = c + dir[1] * 2;

        if (_isValidPosition(landR, landC) && isSet(empty, rcToIndex(landR, landC))) {
          if (_isValidPosition(jumpOverR, jumpOverC) && isSet(opponentPieces, rcToIndex(jumpOverR, jumpOverC))) {
            jumps.add(BoardPosition(landR, landC));
          }
        }
      }
    }
    return jumps;
  }
  
  // Recursive helper for finding all capture sequences for a single piece using bitboards
  List<FullCaptureSequence> _findAllCaptureSequencesForPieceBitboard(
    BoardPosition currentPiecePos,
    Piece piece, // Current state of the piece (type, isKing)
    BitboardState boardState,
    PieceType activePlayer,
    List<BoardPosition> pathTakenSoFar, // Path including currentPiecePos as last
    int capturesSoFar,
  ) {
    List<FullCaptureSequence> allFoundSequences = [];
    Set<BoardPosition> nextImmediateJumps = getJumpMoves(currentPiecePos, piece, boardState);

    if (nextImmediateJumps.isEmpty) {
      if (capturesSoFar > 0) {
        allFoundSequences.add(FullCaptureSequence(
          initialFromPos: pathTakenSoFar.first,
          firstStepToPos: pathTakenSoFar[1], // path must have at least initial and first jump
          fullPath: pathTakenSoFar,
          numCaptures: capturesSoFar,
          finalBoardState: boardState,
        ));
      }
    } else {
      for (BoardPosition nextLandingPos in nextImmediateJumps) {
        BitboardState boardAfterThisJumpStep = boardState.copy();
        Piece pieceAfterThisJumpStep = Piece(type: piece.type, isKing: piece.isKing);
        
        int fromIdx = rcToIndex(currentPiecePos.row, currentPiecePos.col);
        int toIdx = rcToIndex(nextLandingPos.row, nextLandingPos.col);

        // 1. Remove original piece from old position
        if (pieceAfterThisJumpStep.isKing) {
          if (activePlayer == PieceType.black) boardAfterThisJumpStep.blackKings = clearBit(boardAfterThisJumpStep.blackKings, fromIdx);
          else boardAfterThisJumpStep.redKings = clearBit(boardAfterThisJumpStep.redKings, fromIdx);
        } else {
          if (activePlayer == PieceType.black) boardAfterThisJumpStep.blackMen = clearBit(boardAfterThisJumpStep.blackMen, fromIdx);
          else boardAfterThisJumpStep.redMen = clearBit(boardAfterThisJumpStep.redMen, fromIdx);
        }

        // 2. Determine and remove captured piece
        BoardPosition capturedPiecePos;
        if (pieceAfterThisJumpStep.isKing) {
            int dr = (nextLandingPos.row - currentPiecePos.row).sign;
            int dc = (nextLandingPos.col - currentPiecePos.col).sign;
            int checkR = currentPiecePos.row + dr;
            int checkC = currentPiecePos.col + dc;
            while(checkR != nextLandingPos.row || checkC != currentPiecePos.col + dc * (nextLandingPos.col - currentPiecePos.col).abs()) { // Iterate up to, but not including, landing spot
                 if (!_isValidPosition(checkR, checkC)) break; // Should not happen if getJumpMoves was correct
                 int checkIdx = rcToIndex(checkR, checkC);
                 if (isSet(boardAfterThisJumpStep.allOccupiedSquares, checkIdx)) { // Found the piece to capture
                    capturedPiecePos = BoardPosition(checkR, checkC);
                    // Clear this captured piece from all bitboards
                    boardAfterThisJumpStep.blackMen = clearBit(boardAfterThisJumpStep.blackMen, checkIdx);
                    boardAfterThisJumpStep.blackKings = clearBit(boardAfterThisJumpStep.blackKings, checkIdx);
                    boardAfterThisJumpStep.redMen = clearBit(boardAfterThisJumpStep.redMen, checkIdx);
                    boardAfterThisJumpStep.redKings = clearBit(boardAfterThisJumpStep.redKings, checkIdx);
                    break;
                 }
                 checkR += dr;
                 checkC += dc;
            }
        } else { // Man captures adjacent
            capturedPiecePos = BoardPosition(
                currentPiecePos.row + (nextLandingPos.row - currentPiecePos.row) ~/ 2,
                currentPiecePos.col + (nextLandingPos.col - currentPiecePos.col) ~/ 2
            );
            int capturedIdx = rcToIndex(capturedPiecePos.row, capturedPiecePos.col);
            boardAfterThisJumpStep.blackMen = clearBit(boardAfterThisJumpStep.blackMen, capturedIdx);
            boardAfterThisJumpStep.blackKings = clearBit(boardAfterThisJumpStep.blackKings, capturedIdx);
            boardAfterThisJumpStep.redMen = clearBit(boardAfterThisJumpStep.redMen, capturedIdx);
            boardAfterThisJumpStep.redKings = clearBit(boardAfterThisJumpStep.redKings, capturedIdx);
        }

        // 3. Kinging check
        bool justKinged = false;
        if (!pieceAfterThisJumpStep.isKing) {
          if ((activePlayer == PieceType.black && nextLandingPos.row == 7) ||
              (activePlayer == PieceType.red && nextLandingPos.row == 0)) {
            pieceAfterThisJumpStep.isKing = true;
            justKinged = true;
          }
        }
        
        // 4. Place the piece (or new king) at landing spot
        if (pieceAfterThisJumpStep.isKing) {
          if (activePlayer == PieceType.black) boardAfterThisJumpStep.blackKings = setBit(boardAfterThisJumpStep.blackKings, toIdx);
          else boardAfterThisJumpStep.redKings = setBit(boardAfterThisJumpStep.redKings, toIdx);
          if (justKinged && activePlayer == PieceType.black) boardAfterThisJumpStep.blackMen = clearBit(boardAfterThisJumpStep.blackMen, toIdx); // ensure it's not also a man
          if (justKinged && activePlayer == PieceType.red) boardAfterThisJumpStep.redMen = clearBit(boardAfterThisJumpStep.redMen, toIdx);
        } else { // Still a man
          if (activePlayer == PieceType.black) boardAfterThisJumpStep.blackMen = setBit(boardAfterThisJumpStep.blackMen, toIdx);
          else boardAfterThisJumpStep.redMen = setBit(boardAfterThisJumpStep.redMen, toIdx);
        }

        List<BoardPosition> nextPath = List.from(pathTakenSoFar)..add(nextLandingPos);
        allFoundSequences.addAll(_findAllCaptureSequencesForPieceBitboard(
          nextLandingPos, pieceAfterThisJumpStep, boardAfterThisJumpStep, activePlayer,
          nextPath, capturesSoFar + 1,
        ));
      }
    }
    return allFoundSequences;
  }


  @override
  Map<BoardPosition, Set<BoardPosition>> getAllMovesForPlayer(
    BitboardState currentBoard,
    PieceType player,
    bool jumpsOnly, // If true and no jumps, returns empty.
  ) {
    List<FullCaptureSequence> allCaptureSequences = [];
    int playerMen = (player == PieceType.black) ? currentBoard.blackMen : currentBoard.redMen;
    int playerKings = (player == PieceType.black) ? currentBoard.blackKings : currentBoard.redKings;

    for (int i = 0; i < 64; i++) {
      if (isSet(playerMen, i)) {
        Piece manDetails = Piece(type: player, isKing: false);
        BoardPosition fromPos = BoardPosition(indexToRow(i), indexToCol(i));
        allCaptureSequences.addAll(_findAllCaptureSequencesForPieceBitboard(
            fromPos, manDetails, currentBoard, player, [fromPos], 0));
      }
      if (isSet(playerKings, i)) {
        Piece kingDetails = Piece(type: player, isKing: true);
        BoardPosition fromPos = BoardPosition(indexToRow(i), indexToCol(i));
        allCaptureSequences.addAll(_findAllCaptureSequencesForPieceBitboard(
            fromPos, kingDetails, currentBoard, player, [fromPos], 0));
      }
    }

    if (allCaptureSequences.isNotEmpty) {
      int maxCaptures = 0;
      for (var seq in allCaptureSequences) {
        if (seq.numCaptures > maxCaptures) maxCaptures = seq.numCaptures;
      }

      if (maxCaptures > 0) { // Only proceed if there are actual captures
        Map<BoardPosition, Set<BoardPosition>> validFirstSteps = {};
        List<FullCaptureSequence> maximalSequences = allCaptureSequences
            .where((seq) => seq.numCaptures == maxCaptures)
            .toList();
        
        for (var seq in maximalSequences) {
          validFirstSteps
              .putIfAbsent(seq.initialFromPos, () => <BoardPosition>{})
              .add(seq.firstStepToPos);
        }
        return validFirstSteps;
      }
    }

    if (jumpsOnly) return {}; // No jumps found, and only jumps were requested

    // No jumps, or no actual captures found, so find regular moves
    Map<BoardPosition, Set<BoardPosition>> allRegularMoves = {};
    for (int i = 0; i < 64; i++) {
      Piece? pieceDetails = _getPieceDetailsAtIndex(currentBoard, i);
      if (pieceDetails != null && pieceDetails.type == player) {
          BoardPosition fromPos = BoardPosition(indexToRow(i), indexToCol(i));
          Set<BoardPosition> moves = getRegularMoves(fromPos, pieceDetails, currentBoard);
          if (moves.isNotEmpty) {
            allRegularMoves[fromPos] = moves;
          }
      }
    }
    return allRegularMoves;
  }

  @override
  MoveResult applyMoveAndGetResult({
    required BitboardState currentBoard,
    required BoardPosition from,
    required BoardPosition to, // 'to' is the first step of a potential multi-jump sequence
    required PieceType currentPlayer,
  }) {
    BitboardState nextBoard = currentBoard.copy();
    final int fromIndex = rcToIndex(from.row, from.col);
    final int toIndex = rcToIndex(to.row, to.col);

    Piece? movingPieceInitial = _getPieceDetailsAtIndex(nextBoard, fromIndex);
    if (movingPieceInitial == null) return MoveResult(board: currentBoard, turnChanged: true);

    Piece pieceInAction = Piece(type: movingPieceInitial.type, isKing: movingPieceInitial.isKing);
    bool wasActualJumpPerformed = false;
    bool pieceKingedThisMove = false;

    // 1. Clear piece from original position's specific bitboard
    if (pieceInAction.isKing) {
      if (currentPlayer == PieceType.black) nextBoard.blackKings = clearBit(nextBoard.blackKings, fromIndex);
      else nextBoard.redKings = clearBit(nextBoard.redKings, fromIndex);
    } else {
      if (currentPlayer == PieceType.black) nextBoard.blackMen = clearBit(nextBoard.blackMen, fromIndex);
      else nextBoard.redMen = clearBit(nextBoard.redMen, fromIndex);
    }

    // 2. Determine if this from-to move was a jump and remove captured piece
    // This requires knowing if 'to' was a jump destination from 'from'.
    // We infer jump if distance suggests it and intermediate square has opponent.
    // For Turkish Dama, jumps are orthogonal.
    int drAbs = (to.row - from.row).abs();
    int dcAbs = (to.col - from.col).abs();

    if ((drAbs == 2 && dcAbs == 0) || (dcAbs == 2 && drAbs == 0)) { // Man-like jump (2 squares straight)
      int capturedR = from.row + (to.row - from.row) ~/ 2;
      int capturedC = from.col + (to.col - from.col) ~/ 2;
      int capturedIndex = rcToIndex(capturedR, capturedC);
      Piece? capturedPieceDetails = _getPieceDetailsAtIndex(nextBoard, capturedIndex); // Check before nulling
      if (capturedPieceDetails != null && capturedPieceDetails.type != currentPlayer) {
        nextBoard.clearSquare(capturedR, capturedC); // Remove from all bitboards
        wasActualJumpPerformed = true;
      }
    } else if (pieceInAction.isKing && (drAbs > 1 || dcAbs > 1) && (from.row == to.row || from.col == to.col)) { // King extended move
      // Find the single opponent piece on the line between from and to
      int drSign = (to.row - from.row).sign;
      int dcSign = (to.col - from.col).sign;
      int scanR = from.row + drSign;
      int scanC = from.col + dcSign;
      BoardPosition? capturedPiecePosKing;
      int opponentsOnPath = 0;

      while (scanR != to.row || scanC != to.col) {
        if (!_isValidPosition(scanR, scanC)) break;
        Piece? p = _getPieceDetailsAtIndex(nextBoard, rcToIndex(scanR, scanC));
        if (p != null) {
          if (p.type != currentPlayer) {
            opponentsOnPath++;
            if (opponentsOnPath == 1) capturedPiecePosKing = BoardPosition(scanR, scanC);
            else { capturedPiecePosKing = null; break; } // More than one piece
          } else { capturedPiecePosKing = null; break; } // Friendly piece
        }
        scanR += drSign;
        scanC += dcSign;
      }
      if (opponentsOnPath == 1 && capturedPiecePosKing != null) {
        nextBoard.clearSquare(capturedPiecePosKing.row, capturedPiecePosKing.col);
        wasActualJumpPerformed = true;
      }
    }

    // 3. Kinging
    bool isNowKing = pieceInAction.isKing;
    if (!pieceInAction.isKing) {
      if ((pieceInAction.type == PieceType.black && to.row == 7) ||
          (pieceInAction.type == PieceType.red && to.row == 0)) {
        isNowKing = true;
        pieceKingedThisMove = true;
      }
    }

    // 4. Place the piece (or new king) at the destination
    if (isNowKing) {
      if (currentPlayer == PieceType.black) nextBoard.blackKings = setBit(nextBoard.blackKings, toIndex);
      else nextBoard.redKings = setBit(nextBoard.redKings, toIndex);
    } else { // Still a man
      if (currentPlayer == PieceType.black) nextBoard.blackMen = setBit(nextBoard.blackMen, toIndex);
      else nextBoard.redMen = setBit(nextBoard.redMen, toIndex);
    }
    
    // 5. Determine if turn should change
    bool turnShouldChange = true;
    if (wasActualJumpPerformed) {
      Piece currentPieceStateAtTo = Piece(type: currentPlayer, isKing: isNowKing);
      Set<BoardPosition> furtherJumps = getFurtherJumps(to, currentPieceStateAtTo, nextBoard);
      if (furtherJumps.isNotEmpty) {
        turnShouldChange = false;
      }
    }

    return MoveResult(
      board: nextBoard,
      turnChanged: turnShouldChange,
      pieceKinged: pieceKingedThisMove,
    );
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

    bool hasPieces = (currentPlayer == PieceType.red)
        ? (currentBoard.allRedPieces != 0)
        : (currentBoard.allBlackPieces != 0);

    if (!hasPieces) {
      return GameStatus.win(
          (currentPlayer == PieceType.red) ? PieceType.black : PieceType.red,
          GameEndReason.noPiecesLeft);
    }

    if (allPossibleJumpsForCurrentPlayer.isEmpty && allPossibleRegularMovesForCurrentPlayer.isEmpty) {
      return GameStatus.win(
          (currentPlayer == PieceType.red) ? PieceType.black : PieceType.red,
          GameEndReason.noMovesLeft);
    }
    
    return GameStatus.ongoing();
  }

  @override
  bool isMaximalCaptureMandatory() => true; // Turkish Dama has maximal capture

  final TurkishCheckersEvaluator _evaluator = TurkishCheckersEvaluator();
  @override
  BoardEvaluator get boardEvaluator => _evaluator;
  
  @override
  String generateBoardStateHash(BitboardState currentBoard, PieceType playerToMove) {
    // Using the integer values of the bitboards themselves creates a unique hash.
    // Adding playerToMove ensures different states if board is same but turn differs.
    return '${playerToMove.name}:'
           'BM${currentBoard.blackMen}:'
           'BK${currentBoard.blackKings}:'
           'RM${currentBoard.redMen}:'
           'RK${currentBoard.redKings}';
  }
  
  @override
  Set<BoardPosition> getFurtherJumps(
    BoardPosition piecePos, // The current position of the piece that just made a jump
    Piece pieceDetails,     // The current state of that piece (type, and importantly, isKing status)
    BitboardState currentBoard, // The board state *after* the previous jump and capture
  ) {
    // For Turkish Checkers (and standard checkers), the rules for continuing a jump sequence
    // are the same as making an initial jump from the piece's new position.
    // The 'pieceDetails' parameter should reflect if the piece was kinged on the previous jump.
    return getJumpMoves(piecePos, pieceDetails, currentBoard);
  }
}