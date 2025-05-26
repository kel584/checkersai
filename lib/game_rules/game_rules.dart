// lib/game_rules/game_rules.dart
import '../models/piece_model.dart';
import '../models/bitboard_state.dart'; // NEW: Import BitboardState
import '../game_rules/game_status.dart';
import '../ai_evaluators/board_evaluator.dart'; // For BoardEvaluator type

// MoveResult now contains BitboardState
class MoveResult {
  final BitboardState board; // CHANGED: Now holds BitboardState
  final bool turnChanged;
  final bool pieceKinged;
  // You might also want to include information about captured pieces if needed by UI/AI directly
  // final List<BoardPosition> capturedPiecesPositions;

  MoveResult({
    required this.board,
    required this.turnChanged,
    this.pieceKinged = false,
    // this.capturedPiecesPositions = const [],
  });
}

abstract class GameRules {
  String get gameVariantName;
  PieceType get startingPlayer;
  bool get piecesOnDarkSquaresOnly; // Still relevant for some UI aspects or initial setup logic

  // Initializes the board for the start of the game using bitboards
  BitboardState initialBoardSetup(); // CHANGED: Returns BitboardState

  // Gets all valid non-jump moves for a specific piece from its current position
  // Note: For bitboard-centric engines, move generation is often done for all pieces of a type at once.
  // This signature might evolve or be supplemented by methods that operate on whole bitboards.
  Set<BoardPosition> getRegularMoves(
    BoardPosition piecePos,
    Piece pieceDetails, // Contains type and isKing for the piece at piecePos
    BitboardState currentBoard, // CHANGED: Takes BitboardState
  );

  // Gets all valid jump landing positions for a specific piece
  Set<BoardPosition> getJumpMoves(
    BoardPosition piecePos,
    Piece pieceDetails,
    BitboardState currentBoard, // CHANGED: Takes BitboardState
  );

  // Applies a move (either regular or the first step of a jump sequence)
  // Handles piece movement, captures for the current step, and kinging.
  MoveResult applyMoveAndGetResult({
    required BitboardState currentBoard, // CHANGED: Takes BitboardState
    required BoardPosition from,
    required BoardPosition to,
    required PieceType currentPlayer,
  });

  // Checks if, after a piece has moved to 'toPos' and potentially captured,
  // it can make further jumps (for multi-jump scenarios).
  Set<BoardPosition> getFurtherJumps(
    BoardPosition piecePos, // Current position of the piece that just moved/jumped
    Piece pieceDetails,     // The piece itself (its current type/king status)
    BitboardState currentBoard, // CHANGED: Takes BitboardState (after the previous jump step)
  );

  // Gets all possible first moves for a player (respecting mandatory jumps, maximal capture if applicable)
  // Returns a map of starting positions to a set of valid first-step landing positions.
  Map<BoardPosition, Set<BoardPosition>> getAllMovesForPlayer(
    BitboardState currentBoard, // CHANGED: Takes BitboardState
    PieceType player,
    bool jumpsOnly, // If true, only returns jumps. If false and jumps exist, still only returns jumps.
  );

  // Checks win/loss/draw conditions
  GameStatus checkWinCondition({
    required BitboardState currentBoard, // CHANGED: Takes BitboardState
    required PieceType currentPlayer, // The player whose turn it *would be* next
    // These are typically derived by calling getAllMovesForPlayer(currentPlayer)
    required Map<BoardPosition, Set<BoardPosition>> allPossibleJumpsForCurrentPlayer,
    required Map<BoardPosition, Set<BoardPosition>> allPossibleRegularMovesForCurrentPlayer,
    required Map<String, int> boardStateCounts, // For threefold repetition
    // required int movesSinceLastSignificantEvent, // For 50-move rule later
  });
  
  // Generates a hash or string representation for a board state
  String generateBoardStateHash(
    BitboardState currentBoard, // CHANGED: Takes BitboardState
    PieceType playerToMove
  );

  // If true, player must choose a sequence that captures the most pieces.
  bool isMaximalCaptureMandatory(); 
  
  // --- AI Evaluation Hook ---
  // Each rule set must provide its specific board evaluator
  BoardEvaluator get boardEvaluator;

  // This method now becomes concrete and delegates to the specific evaluator.
  // The BoardEvaluator's evaluate method will also need to accept BitboardState.
  double evaluateBoardForAI(BitboardState board, PieceType aiPlayerType) { // CHANGED: Takes BitboardState
    return boardEvaluator.evaluate(
      board: board, // This will now be BitboardState
      aiPlayerType: aiPlayerType,
      rules: this, 
    );
  }
}