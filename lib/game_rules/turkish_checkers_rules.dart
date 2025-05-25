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

    // Men and Kings jump orthogonally
    const List<List<int>> jumpDirections = [[-1, 0], [1, 0], [0, -1], [0, 1]]; // Up, Down, Left, Right

    if (piece.isKing) { // King (Dama) jump
      for (var dir in jumpDirections) {
        for (int i = 1; i < 8; i++) { // Check along the line
          int jumpOverRow = r + dir[0] * i;
          int jumpOverCol = c + dir[1] * i;
          int landRow = r + dir[0] * (i + 1);
          int landCol = c + dir[1] * (i + 1);

          if (!_isValidPosition(jumpOverRow, jumpOverCol)) break; // Off board

          Piece? encounteredPiece = board[jumpOverRow][jumpOverCol];
          if (encounteredPiece != null) {
            if (encounteredPiece.type != piece.type) { // Opponent piece
              if (_isValidPosition(landRow, landCol) && board[landRow][landCol] == null) {
                jumps.add(BoardPosition(landRow, landCol));
              }
            }
            break; // Path blocked (either by opponent that can be jumped or friendly)
          }
          // If empty square, continue along line, but only if landing square is also valid
          if (!_isValidPosition(landRow, landCol)) break;
        }
      }
    } else { // Man (Taş) jump - only over adjacent pieces
      for (var dir in jumpDirections) {
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

  bool _shouldBecomeKing(BoardPosition pos, Piece piece) {
    if (piece.isKing) return false;
    // Black pieces king at row 7 (last row from their perspective)
    if (piece.type == PieceType.black && pos.row == 7) return true;
    // Red pieces king at row 0 (last row from their perspective)
    if (piece.type == PieceType.red && pos.row == 0) return true;
    return false;
  }

  @override
  MoveResult applyMoveAndGetResult({
    required List<List<Piece?>> currentBoard,
    required BoardPosition from,
    required BoardPosition to,
    required PieceType currentPlayer,
  }) {
    List<List<Piece?>> boardCopy = currentBoard.map((row) => List<Piece?>.from(row)).toList();
    final pieceToMove = boardCopy[from.row][from.col];
    if (pieceToMove == null) {
      return MoveResult(board: currentBoard, turnChanged: true, pieceKinged: false);
    }

    Piece movedPiece = Piece(type: pieceToMove.type, isKing: pieceToMove.isKing);
    boardCopy[to.row][to.col] = movedPiece;
    boardCopy[from.row][from.col] = null;
    bool pieceKingedThisMove = false;

    // Determine if it was a jump by checking distance and path for Turkish Checkers
    bool wasJump = false;
    if ((from.row == to.row && (to.col - from.col).abs() > 1) || // Horizontal jump
        (from.col == to.col && (to.row - from.row).abs() > 1)) { // Vertical jump
      wasJump = true;
      int capturedRow, capturedCol;
      if (from.row == to.row) { // Horizontal jump
          capturedRow = from.row;
          capturedCol = from.col + ((to.col - from.col) ~/ (to.col - from.col).abs()); // Square next to 'from' in direction of 'to'
      } else { // Vertical jump
          capturedCol = from.col;
          capturedRow = from.row + ((to.row - from.row) ~/ (to.row - from.row).abs());
      }
      // For kings, the jumped piece could be further away, we need to find it if it was a king jump
      if (movedPiece.isKing) {
          int dr = (to.row - from.row).sign; // -1, 0, or 1
          int dc = (to.col - from.col).sign; // -1, 0, or 1
          // Iterate from 'from' towards 'to' to find the piece to capture
          for (int i=1; i<8; i++) {
              int rCheck = from.row + i * dr;
              int cCheck = from.col + i * dc;
              if (rCheck == to.row && cCheck == to.col) break; // Reached destination
              if(!_isValidPosition(rCheck, cCheck)) break; // Out of bounds
              
              if (boardCopy[rCheck][cCheck] != null) { // Found piece to capture
                  if(boardCopy[rCheck][cCheck]!.type != movedPiece.type) {
                      boardCopy[rCheck][cCheck] = null;
                  }
                  break; // Only one piece can be jumped over per segment by a king
              }
          }
      } else { // Man jump (always adjacent)
           boardCopy[capturedRow][capturedCol] = null;
      }
    }


    if (_shouldBecomeKing(to, movedPiece)) {
      movedPiece.isKing = true;
      pieceKingedThisMove = true;
    }

    bool turnShouldChange = true;
    if (wasJump) {
      // Pieces are removed immediately, so boardCopy is up-to-date
      Set<BoardPosition> furtherJumps = getFurtherJumps(to, movedPiece, boardCopy);
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