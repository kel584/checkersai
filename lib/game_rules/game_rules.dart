// lib/game_rules/game_rules.dart
import '../models/piece_model.dart'; // Or wherever your models are
import 'game_status.dart'; // Import the new GameStatus

// Helper to return results from applying a move
class MoveResult {
  final List<List<Piece?>> board;
  final bool turnChanged; // false if multi-jump is pending for the same player
  final bool pieceKinged;

  MoveResult({required this.board, required this.turnChanged, this.pieceKinged = false});
}

abstract class GameRules {
  String get gameVariantName; // e.g., "Standard Checkers", "Turkish Checkers"
  PieceType get startingPlayer;

  // Initializes the board for the start of the game
  List<List<Piece?>> initialBoardSetup();

  // Determines if pieces are only on dark squares (for UI and logic)
  bool get piecesOnDarkSquaresOnly;

  // Gets all valid non-jump moves for a piece
  Set<BoardPosition> getRegularMoves(
    BoardPosition piecePos,
    Piece piece,
    List<List<Piece?>> board,
  );

  // Gets all valid jump landing positions for a piece
  // This should return only the *first* jump destinations. Multi-jumps are handled during applyMove.
  Set<BoardPosition> getJumpMoves(
    BoardPosition piecePos,
    Piece piece,
    List<List<Piece?>> board,
  );

  // Applies a move (either regular or the first step of a jump sequence)
  // Handles piece movement, captures for the current step, and kinging.
  // Returns the new board state and if the turn should switch or if a multi-jump is pending.
  MoveResult applyMoveAndGetResult({
    required List<List<Piece?>> currentBoard,
    required BoardPosition from,
    required BoardPosition to,
    required PieceType currentPlayer,
  });

  // Checks if, after a piece has moved to 'toPos' and potentially captured,
  // it can make further jumps (for multi-jump scenarios).
  // This is called after 'applyMoveAndGetResult' if turnChanged was false.
  Set<BoardPosition> getFurtherJumps(
    BoardPosition piecePos, // Current position of the piece that just moved/jumped
    Piece piece,          // The piece itself
    List<List<Piece?>> board,
  );

  // Checks win/loss/draw conditions
  // Returns null if game is ongoing, or the PieceType of the winner if game over.
  // Could be extended to return a more complex GameStatus enum (Win, Loss, Draw).
  GameStatus checkWinCondition({
    required List<List<Piece?>> board,
    required PieceType currentPlayer, // The player whose turn it *would be*
    required Map<BoardPosition, Set<BoardPosition>> allPossibleJumps,
    required Map<BoardPosition, Set<BoardPosition>> allPossibleRegularMoves,
    required Map<String, int> boardStateCounts, // For threefold repetition
    // required int movesSinceLastSignificantEvent, // For 50-move rule later
  });
  
  // AI specific helpers that depend on rules
  // These might call getRegularMoves and getJumpMoves internally
  Map<BoardPosition, Set<BoardPosition>> getAllMovesForPlayer(
    List<List<Piece?>> board,
    PieceType player,
    bool jumpsOnly, // If true, only returns jumps, otherwise regular moves (if no jumps available board-wide)
  );

  // Max Cature Rule (specific to variants like Turkish Dama)
  // If true, player must choose a sequence that captures the most pieces.
  // This makes _getSuccessorStates in AI much more complex.
  // For now, we can assume false for standard checkers and simple implementation.
  bool isMaximalCaptureMandatory() => false; 
  
  // Evaluation function specific to this game variant for AI
  // This is a big one; the AI's evaluation is highly rule-dependent.
  // For now, you can have a default or make AI use a generic one and then specialize.
  double evaluateBoardForAI(List<List<Piece?>> board, PieceType aiPlayerType);

  String generateBoardStateHash(List<List<Piece?>> board, PieceType playerToMove);
}