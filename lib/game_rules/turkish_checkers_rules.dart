// lib/game_rules/turkish_checkers_rules.dart
import '../models/piece_model.dart';
import 'game_rules.dart';
import 'game_status.dart';

class FullCaptureSequence {
  final BoardPosition initialFromPos;
  final BoardPosition firstStepToPos; // The landing spot of the very first jump
  final List<BoardPosition> fullPath; // The sequence of squares the jumping piece lands on
  final int numCaptures;
  final List<List<Piece?>> finalBoardState; // Board state after this sequence

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
List<FullCaptureSequence> _findAllCaptureSequencesForPiece(
  BoardPosition currentPiecePos, // Current position of the piece being evaluated
  Piece piece,                   // The current state of the piece
  List<List<Piece?>> boardState, // The board state *before* jumps from currentPiecePos
  PieceType activePlayer,        // The player whose piece is jumping
  List<BoardPosition> pathSoFar, // Path of squares the piece has landed on, STARTS with initial 'from' pos
  int capturesSoFar,
) {
  List<FullCaptureSequence> allFoundSequences = [];

  Set<BoardPosition> nextImmediateJumps =
      getJumpMoves(currentPiecePos, piece, boardState);

  if (nextImmediateJumps.isEmpty) {
    // Base case: No more jumps from this position.
    if (capturesSoFar > 0) {
      // pathSoFar includes the initial starting position and all subsequent landing spots.
      // currentPiecePos is the final landing spot and is already the last element of pathSoFar here.
      allFoundSequences.add(FullCaptureSequence(
        initialFromPos: pathSoFar.first,
        firstStepToPos: pathSoFar.length > 1 
            ? pathSoFar[1] 
            : currentPiecePos, // Should be pathSoFar[1] if capturesSoFar > 0. This case needs care if pathSoFar only has 1 element.
                               // If capturesSoFar=1, pathSoFar is [initialPos, currentPiecePos (first landing)]
                               // So pathSoFar[1] is correct.
        fullPath: pathSoFar, 
        numCaptures: capturesSoFar,
        finalBoardState: boardState,
      ));
    }
  } else {
    // Recursive step: Explore each possible next jump
    for (BoardPosition nextLandingPos in nextImmediateJumps) {
      List<List<Piece?>> boardAfterThisJumpStep =
          boardState.map((row) => List<Piece?>.from(row)).toList();
      Piece pieceAfterThisJumpStep = Piece(type: piece.type, isKing: piece.isKing);

      BoardPosition? capturedPiecePos;
      if (pieceAfterThisJumpStep.isKing) {
        int dr = (nextLandingPos.row - currentPiecePos.row).sign;
        int dc = (nextLandingPos.col - currentPiecePos.col).sign;
        int opponentPiecesOnPath = 0;
        int friendlyPiecesOnPath = 0;

        int checkR = currentPiecePos.row + dr;
        int checkC = currentPiecePos.col + dc;
        while (checkR != nextLandingPos.row || checkC != nextLandingPos.col) {
          if (!_isValidPosition(checkR, checkC)) break;
          Piece? p = boardAfterThisJumpStep[checkR][checkC];
          if (p != null) {
            if (p.type != activePlayer) {
              opponentPiecesOnPath++;
              if (opponentPiecesOnPath == 1) capturedPiecePos = BoardPosition(checkR, checkC);
              else { capturedPiecePos = null; break; }
            } else {
              friendlyPiecesOnPath++; break;
            }
          }
          checkR += dr;
          checkC += dc;
        }
        if (friendlyPiecesOnPath > 0 || opponentPiecesOnPath != 1) capturedPiecePos = null;
      } else { // Man
        int capR = currentPiecePos.row + (nextLandingPos.row - currentPiecePos.row) ~/ 2;
        int capC = currentPiecePos.col + (nextLandingPos.col - currentPiecePos.col) ~/ 2;
        // Assuming getJumpMoves validated the piece at (capR, capC)
        capturedPiecePos = BoardPosition(capR, capC);
      }

      if (capturedPiecePos != null && 
          _isValidPosition(capturedPiecePos.row, capturedPiecePos.col) && // Check validity of capturedPiecePos
          boardAfterThisJumpStep[capturedPiecePos.row][capturedPiecePos.col] != null &&
          boardAfterThisJumpStep[capturedPiecePos.row][capturedPiecePos.col]!.type != activePlayer) {
           boardAfterThisJumpStep[capturedPiecePos.row][capturedPiecePos.col] = null;
      } else {
          // This jump is invalid or the captured piece is not as expected.
          // This branch path should not result in a valid sequence.
          // print("Error in jump simulation: No valid piece to capture for move from $currentPiecePos to $nextLandingPos via $capturedPiecePos");
          continue; // Skip to the next potential jump in nextImmediateJumps
      }

      boardAfterThisJumpStep[nextLandingPos.row][nextLandingPos.col] = pieceAfterThisJumpStep;
      boardAfterThisJumpStep[currentPiecePos.row][currentPiecePos.col] = null;

      if (_shouldBecomeKing(nextLandingPos, pieceAfterThisJumpStep)) {
        pieceAfterThisJumpStep.isKing = true;
      }

      // Create the path for the next recursive call
      List<BoardPosition> nextPath = List.from(pathSoFar)..add(nextLandingPos);

      allFoundSequences.addAll(_findAllCaptureSequencesForPiece(
        nextLandingPos,
        pieceAfterThisJumpStep,
        boardAfterThisJumpStep,
        activePlayer,
        nextPath, // Use the correctly named variable
        capturesSoFar + 1,
      ));
    }
  }
  return allFoundSequences;
}

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

    if (piece.isKing) { // King (Dama) jump logic (remains the same as your corrected version)
      const List<List<int>> kingJumpDirections = [[-1, 0], [1, 0], [0, -1], [0, 1]];
      for (var dir in kingJumpDirections) {
        BoardPosition? opponentPieceToJumpPos;
        // Scan along the line to find the first piece to potentially jump
        for (int i = 1; i < 8; i++) {
          int checkRow = r + dir[0] * i;
          int checkCol = c + dir[1] * i;

          if (!_isValidPosition(checkRow, checkCol)) break;

          Piece? encounteredPiece = board[checkRow][checkCol];
          if (encounteredPiece != null) {
            if (encounteredPiece.type != piece.type) {
              opponentPieceToJumpPos = BoardPosition(checkRow, checkCol);
            }
            break;
          }
        }

        if (opponentPieceToJumpPos != null) {
          for (int j = 1; j < 8; j++) {
            int landRow = opponentPieceToJumpPos.row + dir[0] * j;
            int landCol = opponentPieceToJumpPos.col + dir[1] * j;
            if (!_isValidPosition(landRow, landCol)) break;
            if (board[landRow][landCol] == null) {
              jumps.add(BoardPosition(landRow, landCol));
            } else {
              break;
            }
          }
        }
      }
    } else { // Man (Taş) jump logic - MODIFIED FOR NO BACKWARD CAPTURES
      // piece.moveDirection is -1 for Red (moves up, row decreases), +1 for Black (moves down, row increases)
      final List<List<int>> manJumpDirections = [
        [piece.moveDirection, 0], // Forward jump
        [0, -1],                   // Sideways left jump
        [0, 1],                    // Sideways right jump
      ];

      for (var dir in manJumpDirections) {
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
    bool jumpsOnly,
  ) {
    List<FullCaptureSequence> allPossibleSequences = [];
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null && piece.type == player) {
          final piecePos = BoardPosition(r, c);
          allPossibleSequences.addAll(_findAllCaptureSequencesForPiece(
            piecePos, piece, board, player,
            [piecePos], // Path starts with the current piece's original position
            0,
          ));
        }
      }
    }

    if (allPossibleSequences.isNotEmpty) {
      int maxCaptures = 0;
      for (var seq in allPossibleSequences) {
        if (seq.numCaptures > maxCaptures) {
          maxCaptures = seq.numCaptures;
        }
      }
      if (maxCaptures == 0 && jumpsOnly) { // No actual captures were made, even if jumps were explored
        return {};
      }
       if (maxCaptures == 0 && !jumpsOnly) { // No captures, proceed to regular moves if allowed
          // Fall through to regular move logic below
       } else { // There are actual capture sequences
          List<FullCaptureSequence> maximalSequences = allPossibleSequences
              .where((seq) => seq.numCaptures == maxCaptures && seq.numCaptures > 0) // Ensure actual captures
              .toList();
          
          if (maximalSequences.isNotEmpty) {
            Map<BoardPosition, Set<BoardPosition>> validFirstStepsOfMaximalJumps = {};
            for (var seq in maximalSequences) {
              validFirstStepsOfMaximalJumps
                  .putIfAbsent(seq.initialFromPos, () => <BoardPosition>{})
                  .add(seq.firstStepToPos);
            }
            return validFirstStepsOfMaximalJumps;
          }
          // If somehow maximalSequences is empty but allPossibleSequences was not (e.g. all numCaptures were 0)
          // then fall through to regular moves if !jumpsOnly
       }
    }

    if (jumpsOnly) return {}; // If only jumps were requested and none found (or no actual captures)

    Map<BoardPosition, Set<BoardPosition>> regularMovesMap = {};
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null && piece.type == player) {
          final piecePos = BoardPosition(r, c);
          final moves = getRegularMoves(piecePos, piece, board);
          if (moves.isNotEmpty) {
            regularMovesMap[piecePos] = moves;
          }
        }
      }
    }
    return regularMovesMap;
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

// Simplified PST tables - smaller and faster to access
static const List<List<double>> _turkishManPst = [
  [0.0, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.0],
  [0.1, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.1],
  [0.2, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.2],
  [0.3, 0.4, 0.4, 0.5, 0.5, 0.4, 0.4, 0.3],
  [0.4, 0.5, 0.5, 0.6, 0.6, 0.5, 0.5, 0.4],
  [0.5, 0.6, 0.6, 0.7, 0.7, 0.6, 0.6, 0.5],
  [0.6, 0.7, 0.7, 0.8, 0.8, 0.7, 0.7, 0.6],
  [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
];

static const List<List<double>> _turkishKingPst = [
  [0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6],
  [0.6, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.6],
  [0.6, 0.7, 0.8, 0.8, 0.8, 0.8, 0.7, 0.6],
  [0.6, 0.7, 0.8, 0.9, 0.9, 0.8, 0.7, 0.6],
  [0.6, 0.7, 0.8, 0.9, 0.9, 0.8, 0.7, 0.6],
  [0.6, 0.7, 0.8, 0.8, 0.8, 0.8, 0.7, 0.6],
  [0.6, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.6],
  [0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6],
];

@override
  String generateBoardStateHash(List<List<Piece?>> board, PieceType playerToMove) {
    StringBuffer sb = StringBuffer();
    sb.write('${playerToMove.name}:'); // Include whose turn it is in the hash
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece == null) {
          sb.write('E'); // Empty
        } else {
          sb.write(piece.type == PieceType.red ? 'R' : 'B');
          if (piece.isKing) {
            sb.write('K');
          }
        }
      }
    }
    return sb.toString();
  }


@override
double evaluateBoardForAI(List<List<Piece?>> board, PieceType aiPlayerType) {
  double score = 0;
  PieceType opponentPlayerType = (aiPlayerType == PieceType.red) ? PieceType.black : PieceType.red;

  // Single pass through the board to collect all information
  int aiMen = 0, aiKings = 0;
  int opponentMen = 0, opponentKings = 0;
  double aiPositional = 0, opponentPositional = 0;
  double aiAdvancement = 0, opponentAdvancement = 0;
  double aiCentralization = 0, opponentCentralization = 0;
  int aiCenterPieces = 0, opponentCenterPieces = 0;
  
  // Pre-calculate values to avoid repeated calculations
  const double manValue = 100.0;
  const double kingValue = 350.0;
  
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final piece = board[r][c];
      if (piece == null) continue;
      
      bool isAiPiece = (piece.type == aiPlayerType);
      
      if (piece.isKing) {
        if (isAiPiece) {
          aiKings++;
          aiPositional += _turkishKingPst[r][c];
          // Kings prefer center - quick calculation
          aiCentralization += (4.0 - ((r - 3.5).abs() + (c - 3.5).abs()) * 0.5) * 3.0;
        } else {
          opponentKings++;
          opponentPositional += _turkishKingPst[r][c];
          opponentCentralization += (4.0 - ((r - 3.5).abs() + (c - 3.5).abs()) * 0.5) * 3.0;
        }
      } else {
        // Man piece
        double pstValue, advancementValue;
        int distanceToPromotion;
        
        if (piece.type == PieceType.black) {
          pstValue = _turkishManPst[r][c];
          distanceToPromotion = 7 - r;
        } else {
          pstValue = _turkishManPst[7 - r][c];
          distanceToPromotion = r;
        }
        
        advancementValue = (8 - distanceToPromotion) * 5.0;
        if (distanceToPromotion <= 2) advancementValue += 25.0; // Near promotion bonus
        
        if (isAiPiece) {
          aiMen++;
          aiPositional += pstValue;
          aiAdvancement += advancementValue;
        } else {
          opponentMen++;
          opponentPositional += pstValue * 0.5; // Reduce opponent positional impact
          opponentAdvancement += advancementValue * 0.7;
        }
      }
      
      // Count center pieces (quick check)
      if (r >= 2 && r <= 5 && c >= 2 && c <= 5) {
        if (isAiPiece) aiCenterPieces++;
        else opponentCenterPieces++;
      }
    }
  }

  // === CORE SCORING ===
  
  // Material advantage (most important)
  score += (aiMen * manValue + aiKings * kingValue) - 
           (opponentMen * manValue + opponentKings * kingValue);

  // Positional advantage
  score += (aiPositional - opponentPositional) * 8.0;

  // Advancement bonus
  score += (aiAdvancement - opponentAdvancement);

  // King activity bonus
  score += (aiCentralization - opponentCentralization);

  // Center control
  score += (aiCenterPieces - opponentCenterPieces) * 12.0;

  // === FAST MOBILITY CHECK ===
  // Only do expensive mobility calculation in certain conditions
  int totalPieces = aiMen + aiKings + opponentMen + opponentKings;
  
  if (totalPieces <= 12 || // Endgame
      aiKings != opponentKings || // King imbalance
      (aiMen + aiKings) <= 3 || (opponentMen + opponentKings) <= 3) { // Few pieces left
    
    score += _fastMobilityEvaluation(board, aiPlayerType, opponentPlayerType);
  }

  // === ENDGAME BONUSES ===
  if (totalPieces <= 8) {
    score += (aiKings - opponentKings) * 75.0; // Extra king bonus in endgame
    
    // Winning side should centralize kings, losing side should avoid edges
    if (aiMen + aiKings > opponentMen + opponentKings) {
      score += aiCentralization * 2.0;
    }
  }

  // === QUICK TACTICAL CHECKS ===
  
  // Fast capture threat detection (only check immediate threats)
  if (_hasImmediateCaptures(board, opponentPlayerType)) {
    score -= 30.0; // Penalty for being under immediate threat
  }
  
  if (_hasImmediateCaptures(board, aiPlayerType)) {
    score += 20.0; // Bonus for having captures available
  }

  return score;
}

// Optimized mobility evaluation - only called when needed
double _fastMobilityEvaluation(List<List<Piece?>> board, PieceType aiPlayerType, PieceType opponentPlayerType) {
  int aiMobility = 0;
  int opponentMobility = 0;
  
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final piece = board[r][c];
      if (piece == null) continue;
      
      int mobility = _countQuickMoves(board, r, c, piece);
      
      if (piece.type == aiPlayerType) {
        aiMobility += mobility;
      } else {
        opponentMobility += mobility;
      }
    }
  }
  
  return (aiMobility - opponentMobility) * 4.0;
}

// Quick move counting without generating full move sets
int _countQuickMoves(List<List<Piece?>> board, int r, int c, Piece piece) {
  int moveCount = 0;
  
  if (piece.isKing) {
    // King moves - check 4 directions
    const List<List<int>> directions = [[-1, 0], [1, 0], [0, -1], [0, 1]];
    for (var dir in directions) {
      for (int i = 1; i < 8; i++) {
        int newR = r + dir[0] * i;
        int newC = c + dir[1] * i;
        if (!_isValidPosition(newR, newC) || board[newR][newC] != null) break;
        moveCount++;
      }
    }
  } else {
    // Man moves - check 3 directions (forward + sideways)
    int forwardDir = (piece.type == PieceType.black) ? 1 : -1;
    
    // Forward
    if (_isValidPosition(r + forwardDir, c) && board[r + forwardDir][c] == null) {
      moveCount++;
    }
    // Left
    if (_isValidPosition(r, c - 1) && board[r][c - 1] == null) {
      moveCount++;
    }
    // Right  
    if (_isValidPosition(r, c + 1) && board[r][c + 1] == null) {
      moveCount++;
    }
  }
  
  return moveCount;
}

// Fast capture detection - only checks if captures exist, doesn't enumerate them
bool _hasImmediateCaptures(List<List<Piece?>> board, PieceType playerType) {
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final piece = board[r][c];
      if (piece != null && piece.type == playerType) {
        if (_canCaptureFromPosition(board, r, c, piece)) {
          return true;
        }
      }
    }
  }
  return false;
}

// Quick capture check for a single piece
bool _canCaptureFromPosition(List<List<Piece?>> board, int r, int c, Piece piece) {
  if (piece.isKing) {
    // King capture check - simplified
    const List<List<int>> directions = [[-1, 0], [1, 0], [0, -1], [0, 1]];
    for (var dir in directions) {
      bool foundOpponent = false;
      for (int i = 1; i < 7; i++) { // Don't check full board length
        int checkR = r + dir[0] * i;
        int checkC = c + dir[1] * i;
        if (!_isValidPosition(checkR, checkC)) break;
        
        Piece? checkPiece = board[checkR][checkC];
        if (checkPiece != null) {
          if (checkPiece.type != piece.type && !foundOpponent) {
            foundOpponent = true;
          } else {
            break;
          }
        } else if (foundOpponent) {
          return true; // Found empty square after opponent
        }
      }
    }
  } else {
    // Man capture check
    int forwardDir = (piece.type == PieceType.black) ? 1 : -1;
    const List<List<int>> manDirs = [[1, 0], [0, -1], [0, 1]]; // Forward, left, right relative
    
    for (var dir in manDirs) {
      int actualDr = (dir[0] == 1) ? forwardDir : dir[0];
      int actualDc = dir[1];
      
      int jumpOverR = r + actualDr;
      int jumpOverC = c + actualDc;
      int landR = r + actualDr * 2;
      int landC = c + actualDc * 2;
      
      if (_isValidPosition(landR, landC) && board[landR][landC] == null &&
          _isValidPosition(jumpOverR, jumpOverC)) {
        Piece? jumpedPiece = board[jumpOverR][jumpOverC];
        if (jumpedPiece != null && jumpedPiece.type != piece.type) {
          return true;
        }
      }
    }
  }
  return false;
}


  @override
  bool isMaximalCaptureMandatory() => true; // Implemented as false for now
}