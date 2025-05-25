// lib/game_rules/standard_checkers_rules.dart
// For max in evaluation (if needed here or in AI)
import '../models/piece_model.dart';
import 'game_rules.dart';
import 'game_status.dart';

class StandardCheckersRules extends GameRules {
  @override
  String get gameVariantName => "Standard Checkers";

  @override
  PieceType get startingPlayer => PieceType.red; // Or your default

  @override
  bool get piecesOnDarkSquaresOnly => true;

  @override
  List<List<Piece?>> initialBoardSetup() {
    List<List<Piece?>> board = List.generate(8, (_) => List.filled(8, null, growable: false));
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        if ((r + c) % 2 != 0) { // Dark squares
          if (r < 3) {
            board[r][c] = Piece(type: PieceType.black);
          } else if (r > 4) {
            board[r][c] = Piece(type: PieceType.red);
          }
        }
      }
    }
    return board;
  }

  bool _isValidPosition(int r, int c) {
    return r >= 0 && r < 8 && c >= 0 && c < 8;
  }

  @override
  Set<BoardPosition> getRegularMoves(
      BoardPosition piecePos, Piece piece, List<List<Piece?>> board) {
    Set<BoardPosition> moves = {};
    int r = piecePos.row;
    int c = piecePos.col;

    List<BoardPosition> directionsDeltas = [];
    if (piece.isKing) {
      directionsDeltas = [
        BoardPosition(-1, -1), BoardPosition(-1, 1),
        BoardPosition(1, -1), BoardPosition(1, 1),
      ];
    } else {
      directionsDeltas = [
        BoardPosition(piece.moveDirection, -1),
        BoardPosition(piece.moveDirection, 1),
      ];
    }

    for (var moveDirDelta in directionsDeltas) {
      int nextRow = r + moveDirDelta.row;
      int nextCol = c + moveDirDelta.col;
      if (_isValidPosition(nextRow, nextCol) && board[nextRow][nextCol] == null) {
        moves.add(BoardPosition(nextRow, nextCol));
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

    List<BoardPosition> directionsDeltas = [];
    if (piece.isKing) {
      directionsDeltas = [
        BoardPosition(-1, -1), BoardPosition(-1, 1),
        BoardPosition(1, -1), BoardPosition(1, 1),
      ];
    } else {
      directionsDeltas = [
        BoardPosition(piece.moveDirection, -1),
        BoardPosition(piece.moveDirection, 1),
      ];
    }

    for (var dirDelta in directionsDeltas) {
      int jumpOverRow = r + dirDelta.row;
      int jumpOverCol = c + dirDelta.col;
      int landRow = r + dirDelta.row * 2;
      int landCol = c + dirDelta.col * 2;

      if (_isValidPosition(landRow, landCol) && board[landRow][landCol] == null) {
        if (_isValidPosition(jumpOverRow, jumpOverCol)) {
          Piece? jumpedPiece = board[jumpOverRow][jumpOverCol];
          if (jumpedPiece != null && jumpedPiece.type != piece.type) {
            jumps.add(BoardPosition(landRow, landCol));
          }
        }
      }
    }
    return jumps;
  }
  
  bool _shouldBecomeKing(BoardPosition pos, Piece piece) {
    if (piece.isKing) return false;
    if (piece.type == PieceType.red && pos.row == 0) return true;
    if (piece.type == PieceType.black && pos.row == 7) return true;
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
    final pieceToMove = boardCopy[from.row][from.col]; // Should exist
    if (pieceToMove == null) {
      // This should not happen if 'from' is a valid piece position
      return MoveResult(board: currentBoard, turnChanged: true, pieceKinged: false);
    }
    
    // Create a new piece instance for the new position to avoid modifying the original piece directly
    // if it was obtained from the original board state that might be used elsewhere (e.g. by AI's parent node)
    Piece movedPiece = Piece(type: pieceToMove.type, isKing: pieceToMove.isKing);

    boardCopy[to.row][to.col] = movedPiece;
    boardCopy[from.row][from.col] = null;

    bool wasJump = (to.row - from.row).abs() == 2;
    bool pieceKingedThisMove = false;

    if (wasJump) {
      int capturedRow = from.row + (to.row - from.row) ~/ 2;
      int capturedCol = from.col + (to.col - from.col) ~/ 2;
      boardCopy[capturedRow][capturedCol] = null;
    }

    if (_shouldBecomeKing(to, movedPiece)) {
      movedPiece.isKing = true;
      pieceKingedThisMove = true;
    }

    // For standard checkers, a turn ends unless a multi-jump is possible *by the piece that just jumped*.
    // And kinging on a jump that allows further jumps means the piece continues as a king.
    bool turnShouldChange = true;
    if (wasJump) {
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
    // For standard checkers, getFurtherJumps is the same as getJumpMoves
    // for the piece that just moved (now kinged if applicable).
    return getJumpMoves(piecePos, piece, board);
  }
  
@override
String generateBoardStateHash(List<List<Piece?>> board, PieceType playerToMove) {
  StringBuffer sb = StringBuffer();
  sb.write('${playerToMove.name}:'); // Add whose turn it is to the hash
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final piece = board[r][c];
      if (piece == null) {
        sb.write('E'); // Empty
      } else {
        sb.write(piece.type == PieceType.red ? 'R' : 'B');
        if (piece.isKing) sb.write('K');
      }
    }
  }
  return sb.toString();
}


  @override
  Map<BoardPosition, Set<BoardPosition>> getAllMovesForPlayer(
    List<List<Piece?>> board,
    PieceType player,
    bool jumpsOnly, // If true, only considers jumps. (Not used by current logic, but for AI)
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
      return jumpOpportunities; // Mandatory jumps
    }

    if (jumpsOnly) return {}; // If only jumps were requested and none found

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
  // required int movesSinceLastSignificantEvent, // For later
}) {
  // Check for threefold repetition
  String currentBoardHash = generateBoardStateHash(board, currentPlayer);
  if ((boardStateCounts[currentBoardHash] ?? 0) >= 3) {
    return GameStatus.draw(GameEndReason.threefoldRepetition);
  }

  // Check for no pieces left (copied from old logic, now returns GameStatus)
  bool currentPlayerHasPieces = false;
  // ... (your existing logic to check if currentPlayerHasPieces) ...
   for (int r = 0; r < 8; r++) { // Re-add piece checking logic
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

  // Check for no legal moves (copied from old logic, now returns GameStatus)
  if (allPossibleJumps.isEmpty && allPossibleRegularMoves.isEmpty) {
    return GameStatus.win(
        (currentPlayer == PieceType.red) ? PieceType.black : PieceType.red,
        GameEndReason.noMovesLeft);
  }

  return GameStatus.ongoing(); // Game ongoing
}
  
  // --- Piece-Square Tables (PSTs) ---
  static const List<List<double>> _manPst = [
    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 
    [0.5, 0.6, 0.7, 0.7, 0.7, 0.7, 0.6, 0.5], 
    [0.4, 0.5, 0.6, 0.6, 0.6, 0.6, 0.5, 0.4],
    [0.3, 0.4, 0.5, 0.5, 0.5, 0.5, 0.4, 0.3], 
    [0.2, 0.3, 0.4, 0.4, 0.4, 0.4, 0.3, 0.2],
    [0.1, 0.2, 0.3, 0.3, 0.3, 0.3, 0.2, 0.1],
    [0.05, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.05],
    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 
  ];

  static const List<List<double>> _kingPst = [
    [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
    [0.5, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.5],
    [0.5, 0.6, 0.7, 0.7, 0.7, 0.7, 0.6, 0.5],
    [0.5, 0.6, 0.7, 0.8, 0.8, 0.7, 0.6, 0.5], 
    [0.5, 0.6, 0.7, 0.8, 0.8, 0.7, 0.6, 0.5], 
    [0.5, 0.6, 0.7, 0.7, 0.7, 0.7, 0.6, 0.5],
    [0.5, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.5],
    [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5], 
  ];

  @override
  double evaluateBoardForAI(List<List<Piece?>> board, PieceType aiPlayerType) {
    double score = 0;
    PieceType opponentPlayerType =
        (aiPlayerType == PieceType.red) ? PieceType.black : PieceType.red;

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null) {
          double pieceValue = piece.isKing ? 3.0 : 1.0;
          double positionalValue = 0;

          if (piece.isKing) {
            positionalValue = _kingPst[r][c];
          } else {
            if (piece.type == PieceType.black) { // Black moves 0->7
              positionalValue = _manPst[r][c];
            } else { // Red moves 7->0
              positionalValue = _manPst[7 - r][c];
            }
          }

          if (piece.type == aiPlayerType) {
            score += pieceValue + positionalValue;
          } else if (piece.type == opponentPlayerType) {
            score -= (pieceValue + positionalValue);
          }
        }
      }
    }
    return score;
  }
}