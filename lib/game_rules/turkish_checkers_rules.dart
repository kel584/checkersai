// lib/game_rules/turkish_checkers_rules.dart
import '../models/piece_model.dart';
import 'game_rules.dart';
import 'game_status.dart';

class TurkishCheckersRules extends GameRules {
  @override
  String get gameVariantName => "Turkish Checkers";

  @override
  PieceType get startingPlayer => PieceType.red; // Or PieceType.black, traditionally White starts

  @override
  bool get piecesOnDarkSquaresOnly => false; // Pieces use all squares

  @override
  List<List<Piece?>> initialBoardSetup() {
    List<List<Piece?>> board = List.generate(8, (_) => List.filled(8, null, growable: false));

    // Player Black (e.g., at the "top" of the board view, rows 1 and 2 if 0-indexed)
    // Standard Dama setup: pieces on 2nd and 3rd ranks for each player
    // Let's say rows 1 and 2 for Black, and rows 5 and 6 for Red (if Red is at bottom)
    for (int r = 1; r <= 2; r++) { // Ranks 2 and 3
      for (int c = 0; c < 8; c++) {
        board[r][c] = Piece(type: PieceType.black);
      }
    }

    // Player Red (e.g., at the "bottom", rows 5 and 6)
    for (int r = 5; r <= 6; r++) { // Ranks 6 and 7 from player's perspective (board rows 5 & 6)
      for (int c = 0; c < 8; c++) {
        board[r][c] = Piece(type: PieceType.red);
      }
    }
    return board;
  }

  bool _isValidPosition(int r, int c) {
    return r >= 0 && r < 8 && c >= 0 && c < 8;
  }

  // --- Movement and Capture Logic for Turkish Checkers ---

  @override
  Set<BoardPosition> getRegularMoves(
      BoardPosition piecePos, Piece piece, List<List<Piece?>> board) {
    Set<BoardPosition> moves = {};
    int r = piecePos.row;
    int c = piecePos.col;

    if (piece.isKing) { // King (Dama) movement - like a rook
      const List<List<int>> directions = [[-1, 0], [1, 0], [0, -1], [0, 1]]; // Up, Down, Left, Right
      for (var dir in directions) {
        for (int i = 1; i < 8; i++) {
          int nextRow = r + dir[0] * i;
          int nextCol = c + dir[1] * i;
          if (!_isValidPosition(nextRow, nextCol) || board[nextRow][nextCol] != null) {
            break; // Blocked or off board
          }
          moves.add(BoardPosition(nextRow, nextCol));
        }
      }
    } else { // Man (Taş) movement
      // Forward movement direction depends on piece color
      int forwardDir = (piece.type == PieceType.black) ? 1 : -1; // Black moves "down" (r increases), Red moves "up" (r decreases)

      // Forward
      if (_isValidPosition(r + forwardDir, c) && board[r + forwardDir][c] == null) {
        moves.add(BoardPosition(r + forwardDir, c));
      }
      // Sideways Left
      if (_isValidPosition(r, c - 1) && board[r][c - 1] == null) {
        moves.add(BoardPosition(r, c - 1));
      }
      // Sideways Right
      if (_isValidPosition(r, c + 1) && board[r][c + 1] == null) {
        moves.add(BoardPosition(r, c + 1));
      }
    }
    return moves;
  }

@override
  Set<BoardPosition> getJumpMoves(
      BoardPosition piecePos, Piece piece, List<List<Piece?>> board) {
    Set<BoardPosition> jumps = {};
    int r = piecePos.row;
    int c = piecePos.col;

    // Orthogonal directions (Up, Down, Left, Right)
    const List<List<int>> directions = [[-1, 0], [1, 0], [0, -1], [0, 1]]; 

    if (piece.isKing) { // King (Dama) jump logic
      for (var dir in directions) {
        BoardPosition? opponentPieceToJumpPos;
        // Scan along the line to find the first piece to potentially jump
        for (int i = 1; i < 8; i++) { // Max 7 squares to check along a line
          int checkRow = r + dir[0] * i;
          int checkCol = c + dir[1] * i;

          if (!_isValidPosition(checkRow, checkCol)) { // Went off board
            break;
          }

          Piece? encounteredPiece = board[checkRow][checkCol];
          if (encounteredPiece != null) { // Found a piece
            if (encounteredPiece.type != piece.type) { // It's an opponent's piece
              opponentPieceToJumpPos = BoardPosition(checkRow, checkCol);
            }
            // Whether it's an opponent or friendly, this piece blocks further scanning *for a piece to jump*.
            break;
          }
        }

        // If an opponent piece was found that can be jumped
        if (opponentPieceToJumpPos != null) {
          // Now, scan *beyond* that opponent piece for all subsequent empty landing squares
          for (int j = 1; j < 8; j++) {
            int landRow = opponentPieceToJumpPos.row + dir[0] * j;
            int landCol = opponentPieceToJumpPos.col + dir[1] * j;

            if (!_isValidPosition(landRow, landCol)) { // Went off board
              break;
            }

            if (board[landRow][landCol] == null) { // If the square is empty, it's a valid landing spot
              jumps.add(BoardPosition(landRow, landCol));
            } else {
              // Path for landing is blocked by another piece (friendly or opponent), stop scanning in this direction.
              break;
            }
          }
        }
      }
    } else { // Man (Taş) jump logic - only over adjacent pieces
      for (var dir in directions) { // Men also jump orthogonally
        int jumpOverRow = r + dir[0];
        int jumpOverCol = c + dir[1];
        int landRow = r + dir[0] * 2;
        int landCol = c + dir[1] * 2;

        if (_isValidPosition(landRow, landCol) && board[landRow][landCol] == null) {
          if (_isValidPosition(jumpOverRow, jumpOverCol)) {
            Piece? jumpedPiece = board[jumpOverRow][jumpOverCol];
            if (jumpedPiece != null && jumpedPiece.type != piece.type) {
              jumps.add(BoardPosition(landRow, landCol));
            }
          }
        }
      }
    }
    return jumps;
  }



@override
MoveResult applyMoveAndGetResult({
  required List<List<Piece?>> currentBoard,
  required BoardPosition from,
  required BoardPosition to,
  required PieceType currentPlayer,
}) {
  List<List<Piece?>> boardCopy = currentBoard.map((row) => List<Piece?>.from(row)).toList();
  final pieceToMoveInitialState = boardCopy[from.row][from.col];

  if (pieceToMoveInitialState == null) {
    return MoveResult(board: currentBoard, turnChanged: true, pieceKinged: false);
  }

  Piece pieceInAction = Piece(type: pieceToMoveInitialState.type, isKing: pieceToMoveInitialState.isKing);
  bool wasActualJumpPerformed = false;
  bool pieceKingedThisMove = false;

  // Clear the 'from' position on the copy *before* scanning the path for captures
  boardCopy[from.row][from.col] = null;

  // Determine if a capture occurred and remove the captured piece
  if (pieceInAction.isKing) {
    // For a king's move from 'from' to 'to' to be a jump, there must be exactly one
    // opponent piece on the straight line strictly between 'from' and 'to'.
    // getJumpMoves should have already validated that 'to' is a valid empty landing square
    // after such a configuration.

    int dr = (to.row - from.row).sign; // Direction of move: -1, 0, or 1
    int dc = (to.col - from.col).sign; // Direction of move: -1, 0, or 1

    BoardPosition? capturedPiecePositionOnPath;
    int opponentPiecesFoundOnPath = 0;
    int friendlyPiecesFoundOnPath = 0;

    // Scan squares on the line strictly between 'from' and 'to'
    int currentRow = from.row + dr;
    int currentCol = from.col + dc;

    while ((dr != 0 && (dr > 0 ? currentRow < to.row : currentRow > to.row)) || // Moving towards to.row
           (dc != 0 && (dc > 0 ? currentCol < to.col : currentCol > to.col))) {  // Moving towards to.col
      if (!_isValidPosition(currentRow, currentCol)) { // Should not happen if 'to' is valid and path is straight
        break;
      }

      Piece? intermediatePiece = boardCopy[currentRow][currentCol];
      if (intermediatePiece != null) {
        if (intermediatePiece.type != pieceInAction.type) { // Opponent piece
          opponentPiecesFoundOnPath++;
          if (opponentPiecesFoundOnPath == 1) { // This is the first (and should be only) opponent
            capturedPiecePositionOnPath = BoardPosition(currentRow, currentCol);
          } else { // Found a second opponent piece on the path
            // This implies an invalid jump path (king jumps one piece at a time)
            // getJumpMoves should ideally prevent this.
          }
        } else { // Friendly piece on the path
          friendlyPiecesFoundOnPath++;
        }
      }
      currentRow += dr;
      currentCol += dc;
    }

    // A valid king capture requires exactly one opponent piece and no friendly pieces on the path.
    if (opponentPiecesFoundOnPath == 1 && friendlyPiecesFoundOnPath == 0 && capturedPiecePositionOnPath != null) {
      boardCopy[capturedPiecePositionOnPath.row][capturedPiecePositionOnPath.col] = null; // Perform capture
      wasActualJumpPerformed = true;
    }

  } else { // Man (Taş) capture
    // A man's jump is always over an adjacent piece, landing 2 squares away.
    // This is an "extended jump" of exactly 2 squares.
    if (((to.row - from.row).abs() == 2 && from.col == to.col) || // Vertical jump by 2
        ((to.col - from.col).abs() == 2 && from.row == to.row)) { // Horizontal jump by 2
      
      int capturedRow = from.row + (to.row - from.row) ~/ 2;
      int capturedCol = from.col + (to.col - from.col) ~/ 2;
      
      // What was on the square to be jumped before 'from' was cleared from boardCopy?
      // We should check against the original currentBoard state for the jumped piece.
      Piece? pieceThatWasAtCapturedSquare = currentBoard[capturedRow][capturedCol]; 

      if (_isValidPosition(capturedRow, capturedCol) &&
          pieceThatWasAtCapturedSquare != null &&
          pieceThatWasAtCapturedSquare.type != pieceInAction.type) {
        boardCopy[capturedRow][capturedCol] = null; // Capture the piece on the copy
        wasActualJumpPerformed = true;
      }
    }
  }

  // Place the piece at the 'to' position in the copy
  boardCopy[to.row][to.col] = pieceInAction;

  // Kinging
  if (_shouldBecomeKing(to, pieceInAction)) { // Ensure _shouldBecomeKing is defined in this class
    pieceInAction.isKing = true;
    pieceKingedThisMove = true;
  }

  // Determine if turn should change
  bool turnShouldChange = true;
  if (wasActualJumpPerformed) {
    Set<BoardPosition> furtherJumps = getFurtherJumps(to, pieceInAction, boardCopy);
    if (furtherJumps.isNotEmpty) {
      turnShouldChange = false; // Multi-jump pending
    }
  }

  return MoveResult(
    board: boardCopy,
    turnChanged: turnShouldChange,
    pieceKinged: pieceKingedThisMove,
  );
}

  @override
  Set<BoardPosition> getFurtherJumps(
      BoardPosition piecePos, Piece piece, List<List<Piece?>> board) {
    // For Turkish checkers, further jumps are just regular jumps from the new position
    return getJumpMoves(piecePos, piece, board);
  }

  @override
  Map<BoardPosition, Set<BoardPosition>> getAllMovesForPlayer(
    List<List<Piece?>> board,
    PieceType player,
    bool jumpsOnly, // This flag from GameRules can be used by AI. GameScreen uses it.
  ) {
    Map<BoardPosition, Set<BoardPosition>> allMoves = {};
    Map<BoardPosition, Set<BoardPosition>> jumpOpportunities = {};

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final currentPiece = board[r][c];
        if (currentPiece != null && currentPiece.type == player) {
          final piecePos = BoardPosition(r, c);
          final jumps = getJumpMoves(piecePos, currentPiece, board);
          if (jumps.isNotEmpty) {
            jumpOpportunities[piecePos] = jumps;
          }
        }
      }
    }

    if (jumpOpportunities.isNotEmpty) {
      return jumpOpportunities; // Mandatory jumps rule
    }

    if (jumpsOnly && jumpOpportunities.isEmpty) {
      // If only jumps were requested but none were found, return empty.
      return {};
    }
    
    // No jumps, get regular moves
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final currentPiece = board[r][c];
        if (currentPiece != null && currentPiece.type == player) {
          final piecePos = BoardPosition(r, c);
          final regular = getRegularMoves(piecePos, currentPiece, board);
          if (regular.isNotEmpty) {
            allMoves[piecePos] = regular;
          }
        }
      }
    }
    return allMoves;
  }

bool _shouldBecomeKing(BoardPosition pos, Piece piece) {
    if (piece.isKing) { // Already a king, no change
      return false;
    }

    // Assuming Black pieces start at the "top" (e.g., rows 1, 2 in your initial setup)
    // and move towards row 7 to become a king.
    if (piece.type == PieceType.black && pos.row == 7) {
      return true;
    }

    // Assuming Red pieces start at the "bottom" (e.g., rows 5, 6 in your initial setup)
    // and move towards row 0 to become a king.
    if (piece.type == PieceType.red && pos.row == 0) {
      return true;
    }

    return false;
  }

@override
  GameStatus checkWinCondition({
    required List<List<Piece?>> board,
    required PieceType currentPlayer,
    required Map<BoardPosition, Set<BoardPosition>> allPossibleJumps,
    required Map<BoardPosition, Set<BoardPosition>> allPossibleRegularMoves,
    required Map<String, int> boardStateCounts,
    // Make sure this matches GameRules: if movesSinceLastSignificantEvent is commented out there,
    // it should be commented out here too, or vice-versa.
    // required int movesSinceLastSignificantEvent, 
  }) {
    // ---- YOUR IMPLEMENTATION FOR TURKISH CHECKERS WIN/DRAW CONDITIONS ----

    // Example: Check for threefold repetition (same as in StandardCheckersRules)
    String currentBoardHash = generateBoardStateHash(board, currentPlayer); // Ensure this method is also implemented
    if ((boardStateCounts[currentBoardHash] ?? 0) >= 3) {
      return GameStatus.draw(GameEndReason.threefoldRepetition);
    }

    // Check for no pieces left for the current player
    bool currentPlayerHasPieces = false;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        if (board[r][c] != null && board[r][c]!.type == currentPlayer) {
          currentPlayerHasPieces = true;
          break;
        }
      }
      if (currentPlayerHasPieces) break;
    }
    if (!currentPlayerHasPieces) {
      return GameStatus.win(
          (currentPlayer == PieceType.red) ? PieceType.black : PieceType.red,
          GameEndReason.noPiecesLeft);
    }

    // Check if current player has any legal moves
    // (allPossibleJumps and allPossibleRegularMoves are passed in, calculated by GameScreenState)
    if (allPossibleJumps.isEmpty && allPossibleRegularMoves.isEmpty) {
      return GameStatus.win(
          (currentPlayer == PieceType.red) ? PieceType.black : PieceType.red,
          GameEndReason.noMovesLeft);
    }
    
    // TODO: Add any Turkish Checkers specific draw conditions if they exist
    // (e.g., specific king vs king scenarios, or if you implement a move count rule later)

    return GameStatus.ongoing(); // If no win/loss/draw condition met
  }

  @override
  double evaluateBoardForAI(List<List<Piece?>> board, PieceType aiPlayerType) {
    // Placeholder: A proper evaluation for Turkish Dama is needed.
    // This will be very different from standard checkers due to orthogonal movement
    // and different strategic values.
    // For now, a simple material count.
    double score = 0;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null) {
          double pieceValue = piece.isKing ? 5.0 : 1.0; // Kings (Dama) are very powerful
          if (piece.type == aiPlayerType) {
            score += pieceValue;
          } else {
            score -= pieceValue;
          }
        }
      }
    }
    return score;
  }

  @override
  String generateBoardStateHash(List<List<Piece?>> board, PieceType playerToMove) {
    StringBuffer sb = StringBuffer();
    sb.write('${playerToMove.name}:');
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece == null) {
          sb.write('E'); // Empty
        } else {
          // Using 'R' and 'B' is fine, but for Turkish Dama, 
          // sometimes White/Black is used, or Light/Dark.
          // Stick to your PieceType enum for consistency.
          sb.write(piece.type == PieceType.red ? 'R' : 'B');
          if (piece.isKing) sb.write('K');
        }
      }
    }
    return sb.toString();
  }

  @override
  bool isMaximalCaptureMandatory() => false; // Implemented as false for now
}