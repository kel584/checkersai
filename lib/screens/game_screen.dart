import 'package:flutter/material.dart';
import '../models/piece_model.dart';
import '../widgets/board_widget.dart';
import '../ai/checkers_ai.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  List<List<Piece?>> _boardData = [];
  PieceType _currentPlayer = PieceType.red; // Red starts
  BoardPosition? _selectedPiecePosition;
  Set<BoardPosition> _validMoves = {};
  PieceType? _winner;
  bool _isGameOver = false;
  final CheckersAI _ai = CheckersAI();
  AIMove? _suggestedMove;

  @override
  void initState() {
    super.initState();
    _initializeBoard();
    _resetGame();
  }

  void _initializeBoard() {
    _boardData = List.generate(8, (_) => List.filled(8, null, growable: false));
    _currentPlayer = PieceType.red; // Red always starts
    _selectedPiecePosition = null;
    _validMoves = {};
    _isGameOver = false; // Also reset game over status here
    _winner = null;      // And winner

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        bool isDarkSquare = (r + c) % 2 != 0;
        if (isDarkSquare) {
          if (r < 3) {
            _boardData[r][c] = Piece(type: PieceType.black);
          } else if (r > 4) {
            _boardData[r][c] = Piece(type: PieceType.red);
          }
        }
      }
    }
    setState(() {});
  }

// In _GameScreenState within lib/screens/game_screen.dart
// Ensure your _handleSquareTap looks something like this (it likely already does)

// In _GameScreenState within lib/screens/game_screen.dart

void _resetGame() {
  setState(() {
    _initializeBoard(); // This already sets _currentPlayer, clears selections etc.
    _isGameOver = false;
    _winner = null;
    // print("Game Reset!");
  });
}

void _handleSquareTap(int row, int col) {
  final tappedPosition = BoardPosition(row, col);

  setState(() {

    if (_suggestedMove != null) {
      _suggestedMove = null;
    }
    // First, determine if any jumps are available for the current player this turn
    Map<BoardPosition, Set<BoardPosition>> allTurnJumps = _getAllJumpOpportunities(_currentPlayer);
    bool jumpsAreMandatoryThisTurn = allTurnJumps.isNotEmpty;

    // print("[DEBUG HST] Tap: $tappedPosition. Player: $_currentPlayer. Jumps Mandatory This Turn: $jumpsAreMandatoryThisTurn");
    // if (jumpsAreMandatoryThisTurn) {
    //   print("[DEBUG HST] Pieces that can jump: ${allTurnJumps.keys.map((p) => p.toString()).join(', ')}");
    // }

    final pieceOnTappedSquare = _boardData[row][col];

    if (_selectedPiecePosition == null) {
      // === Trying to select a piece ===
      if (pieceOnTappedSquare != null && pieceOnTappedSquare.type == _currentPlayer) {
        if (jumpsAreMandatoryThisTurn) {
          // Jumps are mandatory. Can the tapped piece make one of these jumps?
          if (allTurnJumps.containsKey(tappedPosition)) {
            _selectedPiecePosition = tappedPosition;
            _calculateValidMovesForSelectedPiece(); // Will set _validMoves to its jumps
            // print("[DEBUG HST] Selected piece $tappedPosition which CAN make a mandatory jump.");
          } else {
            // Tapped a piece that cannot make a mandatory jump. Do nothing or show message.
            // print("[DEBUG HST] Tapped piece $tappedPosition which CANNOT make a mandatory jump. Selection denied.");
             // Optionally: ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Invalid selection: A jump is mandatory.")));
            _validMoves = {}; // Clear any previous valid moves
          }
        } else {
          // No jumps are mandatory this turn. Select the piece normally.
          _selectedPiecePosition = tappedPosition;
          _calculateValidMovesForSelectedPiece(); // Will calculate regular moves
          // print("[DEBUG HST] Selected piece $tappedPosition. No jumps mandatory.");
        }
      }
    } else {
      // === A piece IS ALREADY SELECTED (_selectedPiecePosition is not null) ===
      if (tappedPosition == _selectedPiecePosition) {
        // Tapped the same selected piece: Deselect
        // print("[DEBUG HST] Deselecting piece at $tappedPosition.");
        _selectedPiecePosition = null;
        _validMoves = {};
      } else if (pieceOnTappedSquare != null && pieceOnTappedSquare.type == _currentPlayer) {
        // Tapped another of current player's pieces: Try to switch selection
        if (jumpsAreMandatoryThisTurn) {
          if (allTurnJumps.containsKey(tappedPosition)) {
            _selectedPiecePosition = tappedPosition;
            _calculateValidMovesForSelectedPiece(); // Will set its jumps
            // print("[DEBUG HST] Switched selection to $tappedPosition which CAN make a mandatory jump.");
          } else {
            // print("[DEBUG HST] Attempted to switch to $tappedPosition which CANNOT make a mandatory jump. Switch denied.");
            // Optionally provide feedback, or just do nothing, keeping current selection.
            // For simplicity, we can deselect the current one if the new tap is invalid in mandatory jump context
            // _selectedPiecePosition = null;
            // _validMoves = {};
          }
        } else {
          // No jumps mandatory, switch selection normally
          _selectedPiecePosition = tappedPosition;
          _calculateValidMovesForSelectedPiece();
          // print("[DEBUG HST] Switched selection to $tappedPosition (no jumps mandatory).");
        }
      } else if (_validMoves.contains(tappedPosition)) {
        // Tapped a valid move square for the currently selected piece
        // _validMoves should already be correctly populated (only jumps if they were mandatory for this piece, or regular moves)
        // print("[DEBUG HST] Tapped valid move $tappedPosition for piece at $_selectedPiecePosition. Making move.");
        _makeMove(_selectedPiecePosition!, tappedPosition);
        // After _makeMove, if it wasn't a multi-jump continuation, _selectedPiecePosition will be null.
        // If it WAS a multi-jump, _selectedPiecePosition and _validMoves are updated by _makeMove.
        // The UI will reflect the state for the next action (either new player's turn or current player's multi-jump)
      } else {
        // Tapped an invalid square (empty, opponent, or not a valid move for selected piece)
        // print("[DEBUG HST] Tapped invalid square $tappedPosition. Current _validMoves: ${_validMoves.map((p)=>p.toString())}");
        // Consider deselecting if an invalid non-piece square is tapped.
        // If an opponent piece is tapped, or empty square not in valid moves, generally do nothing or deselect.
         _selectedPiecePosition = null;
         _validMoves = {};
      }
    }
  });
}

Map<BoardPosition, Set<BoardPosition>> _getAllJumpOpportunities(PieceType player) {
  Map<BoardPosition, Set<BoardPosition>> allJumps = {};
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final piece = _boardData[r][c];
      if (piece != null && piece.type == player) {
        final piecePos = BoardPosition(r, c);
        final jumpsForThisPiece = _getJumpMovesForPiece(piecePos, piece);
        if (jumpsForThisPiece.isNotEmpty) {
          allJumps[piecePos] = jumpsForThisPiece;
        }
      }
    }
  }
  // print("[DEBUG GLOBAL JUMPS] For player $player, all available jumps: $allJumps");
  return allJumps;
}

// In _GameScreenState within lib/screens/game_screen.dart

void _calculateValidMovesForSelectedPiece() { // Renamed from _calculateValidMoves
  if (_selectedPiecePosition == null) {
    _validMoves = {};
    return;
  }
  final piece = _boardData[_selectedPiecePosition!.row][_selectedPiecePosition!.col];
  if (piece == null) {
    _validMoves = {};
    return;
  }

  // print("[DEBUG CVM_SEL] Calculating moves for piece at: ${_selectedPiecePosition}, Type: ${piece.type}, King: ${piece.isKing}");

  // Check ALL jump opportunities for the current player for THIS TURN
  Map<BoardPosition, Set<BoardPosition>> allPlayerJumps = _getAllJumpOpportunities(_currentPlayer);

  if (allPlayerJumps.isNotEmpty) {
    // Jumps are mandatory for the turn.
    // Does the CURRENTLY selected piece have any of these mandatory jumps?
    if (allPlayerJumps.containsKey(_selectedPiecePosition!)) {
      _validMoves = allPlayerJumps[_selectedPiecePosition!]!;
      // print("[DEBUG CVM_SEL] ---> JUMPS MANDATORY FOR TURN. Selected piece CAN jump. _validMoves: ${_validMoves.map((p) => p.toString()).join(', ')}");
    } else {
      // Selected piece cannot make a jump, but jumps are mandatory for the turn.
      // This piece effectively has no valid moves in this context.
      _validMoves = {};
      // print("[DEBUG CVM_SEL] ---> JUMPS MANDATORY FOR TURN. Selected piece CANNOT jump. _validMoves cleared.");
    }
  } else {
    // No jumps are mandatory for the turn for any piece.
    // Calculate regular moves for the selected piece.
    _validMoves = _getRegularMovesForPiece(_selectedPiecePosition!, piece);
    // print("[DEBUG CVM_SEL] ---> NO JUMPS MANDATORY FOR TURN. Regular moves: ${_validMoves.map((p) => p.toString()).join(', ')}");
  }
}



// New helper method to get JUMP moves
Set<BoardPosition> _getJumpMovesForPiece(BoardPosition pos, Piece piece) {
  Set<BoardPosition> jumps = {};
  int r = pos.row;
  int c = pos.col;

  List<BoardPosition> directionsToCheck = [];
  if (piece.isKing) {
    directionsToCheck = [
      BoardPosition(-2, -2), BoardPosition(-2, 2), // Up-left, Up-right jumps
      BoardPosition(2, -2), BoardPosition(2, 2),   // Down-left, Down-right jumps
    ];
  } else {
    // Non-kings jump based on their move direction
    directionsToCheck = [
      BoardPosition(piece.moveDirection * 2, -2), // Forward-left jump
      BoardPosition(piece.moveDirection * 2, 2),  // Forward-right jump
    ];
  }

  for (var jumpDir in directionsToCheck) {
    int landRow = r + jumpDir.row;
    int landCol = c + jumpDir.col;

    int jumpOverRow = r + jumpDir.row ~/ 2; // Integer division to get midpoint
    int jumpOverCol = c + jumpDir.col ~/ 2;

    if (_isValidPosition(landRow, landCol) && _boardData[landRow][landCol] == null) {
      Piece? jumpedPiece = _boardData[jumpOverRow][jumpOverCol];
      if (jumpedPiece != null && jumpedPiece.type != piece.type) {
        // There's an opponent piece to jump over
        jumps.add(BoardPosition(landRow, landCol));
      }
    }
  }
  return jumps;
}

// New helper method to get REGULAR (non-jump) moves
Set<BoardPosition> _getRegularMovesForPiece(BoardPosition pos, Piece piece) {
  Set<BoardPosition> moves = {};
  int r = pos.row;
  int c = pos.col;

  List<BoardPosition> directionsToCheck = [];
  if (piece.isKing) {
    directionsToCheck = [
      BoardPosition(-1, -1), BoardPosition(-1, 1), // Up-left, Up-right
      BoardPosition(1, -1), BoardPosition(1, 1),   // Down-left, Down-right
    ];
  } else {
    // Non-kings move based on their move direction
    directionsToCheck = [
      BoardPosition(piece.moveDirection, -1), // Forward-left
      BoardPosition(piece.moveDirection, 1),  // Forward-right
    ];
  }

  for (var moveDir in directionsToCheck) {
    int nextRow = r + moveDir.row;
    int nextCol = c + moveDir.col;
    if (_isValidPosition(nextRow, nextCol) && _boardData[nextRow][nextCol] == null) {
      moves.add(BoardPosition(nextRow, nextCol));
    }
  }
  return moves;
}

// In _GameScreenState within lib/screens/game_screen.dart

// Make sure this helper is present and correct
bool _isValidPosition(int r, int c) {
  return r >= 0 && r < 8 && c >= 0 && c < 8;
}

// Add this helper method for kinging condition
bool _shouldBecomeKing(BoardPosition pos, Piece piece) {
  if (piece.isKing) return false; // Already a king
  if (piece.type == PieceType.red && pos.row == 0) return true; // Red reaches black's back rank
  if (piece.type == PieceType.black && pos.row == 7) return true; // Black reaches red's back rank
  return false;
}

// In _GameScreenState within lib/screens/game_screen.dart
// Modify _makeMove method

void _makeMove(BoardPosition from, BoardPosition to) {
  final pieceToMove = _boardData[from.row][from.col];
  if (pieceToMove == null) return;

  _boardData[to.row][to.col] = pieceToMove;
  _boardData[from.row][from.col] = null;

  bool wasJump = (to.row - from.row).abs() == 2;

  if (wasJump) {
    int capturedRow = from.row + (to.row - from.row) ~/ 2;
    int capturedCol = from.col + (to.col - from.col) ~/ 2;
    _boardData[capturedRow][capturedCol] = null;
  }

  if (_shouldBecomeKing(to, pieceToMove)) {
    pieceToMove.isKing = true;
  }

  if (wasJump) {
    Set<BoardPosition> furtherJumps = _getJumpMovesForPiece(to, pieceToMove);
    if (furtherJumps.isNotEmpty) {
      _selectedPiecePosition = to;
      _validMoves = furtherJumps;
      // print("[DEBUG MM] Multi-jump available! _validMoves for next jump set to: ${_validMoves.map((p) => p.toString()).join(', ')}");
      // Current player remains the same for multi-jump.
      // Game state will be checked when this multi-jump sequence finally ends.
      return; // Early exit, turn does not switch
    }
  }

  // If not a multi-jump continuation, or if it was a regular move:
  _selectedPiecePosition = null;
  _validMoves = {};
  _currentPlayer = (_currentPlayer == PieceType.red) ? PieceType.black : PieceType.red;

  // Call _checkGameState() for the NEW current player
  _checkGameState(); // <--- ADD THIS CALL HERE
}
// In _GameScreenState within lib/screens/game_screen.dart

void _checkGameState() {
  // Check for the new _currentPlayer
  bool currentPlayerHasPieces = false;
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      if (_boardData[r][c] != null && _boardData[r][c]!.type == _currentPlayer) {
        currentPlayerHasPieces = true;
        break;
      }
    }
    if (currentPlayerHasPieces) break;
  }

  if (!currentPlayerHasPieces) {
    // Current player has no pieces left, so the OTHER player wins.
    _isGameOver = true;
    _winner = (_currentPlayer == PieceType.red) ? PieceType.black : PieceType.red;
    print("Game Over! Winner: $_winner (opponent ran out of pieces)");
    return;
  }

  // Current player has pieces, now check if they have any legal moves.
  // We can reuse _getAllJumpOpportunities and _getRegularMovesForPiece logic.
  Map<BoardPosition, Set<BoardPosition>> allJumps = _getAllJumpOpportunities(_currentPlayer);
  if (allJumps.isNotEmpty) {
    // Current player has jump moves, game continues.
    // print("Game continues, $_currentPlayer has jump moves.");
    return;
  }

  // No jump moves, check for regular moves.
  bool hasAnyRegularMove = false;
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final piece = _boardData[r][c];
      if (piece != null && piece.type == _currentPlayer) {
        final regularMoves = _getRegularMovesForPiece(BoardPosition(r, c), piece);
        if (regularMoves.isNotEmpty) {
          hasAnyRegularMove = true;
          break;
        }
      }
    }
    if (hasAnyRegularMove) break;
  }

  if (!hasAnyRegularMove) {
    // Current player has pieces but no jumps and no regular moves. The OTHER player wins.
    _isGameOver = true;
    _winner = (_currentPlayer == PieceType.red) ? PieceType.black : PieceType.red;
    print("Game Over! Winner: $_winner ($_currentPlayer has no legal moves)");
  } else {
    // print("Game continues, $_currentPlayer has regular moves.");
  }
}


// In _GameScreenState within lib/screens/game_screen.dart
// Modify the build method

@override
Widget build(BuildContext context) {
  String appBarTitle = 'Checkers Game';
  if (_isGameOver && _winner != null) {
    appBarTitle = "${_winner.toString().split('.').last.toUpperCase()} Wins!";
  } else if (!_isGameOver) {
    appBarTitle = 'Checkers - ${_currentPlayer.toString().split('.').last.toUpperCase()}\'s Turn';
  }

  return Scaffold(
    appBar: AppBar(
      title: Text(appBarTitle),
      backgroundColor: _isGameOver && _winner != null
          ? (_winner == PieceType.red ? Colors.red[900] : Colors.black)
          : Colors.brown[700],
    ),
    body: SafeArea(
      child: Column(
        // mainAxisAlignment: MainAxisAlignment.spaceBetween, // Keep this or adjust
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // ... (your existing LayoutBuilder code for BoardWidget) ...
                    // Pass _isGameOver to BoardWidget if you want to disable taps
                    // e.g. BoardWidget(..., onSquareTap: _isGameOver ? null : _handleSquareTap, ...);
                    // For now, we'll just show winner message.
                    double potentialSize = constraints.maxWidth < constraints.maxHeight
                        ? constraints.maxWidth
                        : constraints.maxHeight;
                    double boardSize = (potentialSize > 0) ? potentialSize : 0;

                    if (_boardData.isEmpty && !_isGameOver) { // check !isGameOver here
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (boardSize <= 0 && !_isGameOver) { // check !isGameOver here
                      return const Center(child: Text("Not enough space for the board."));
                    }
                    
                    // If game is over, you might want to show the final board state
                    // or even a message overlaying the board.
                    // For simplicity, we'll keep rendering the board.
                    return BoardWidget(
                      boardData: _boardData,
                      boardSize: boardSize,
                      onSquareTap: _isGameOver ? (r,c) {} : _handleSquareTap, // Disable taps if game is over
                      selectedPiecePosition: _selectedPiecePosition,
                      validMoves: _validMoves,
                      suggestedMoveFrom: _suggestedMove?.from, // Pass AI suggestion 'from'
                      suggestedMoveTo: _suggestedMove?.to,     // Pass AI suggestion 'to'
                    );
                  },
                ),
              ),
            ),
          ),
          // Display Winner Message and Reset Button
          if (_isGameOver)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: Text(
                _winner != null ? "${_winner.toString().split('.').last.toUpperCase()} Wins!" : "Game Over!",
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _winner == PieceType.red ? Colors.red[900] : Colors.black),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (!_isGameOver) // Only show current player if game is not over
                  Text(
                    "${_currentPlayer.toString().split('.').last.toUpperCase()}'s Turn",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _currentPlayer == PieceType.red ? Colors.red[700] : Colors.black87),
                  ),
                const SizedBox(height: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                  // Change button text and action based on game state
// In _GameScreenState's build method, for the ElevatedButton:
        onPressed: _isGameOver ? _resetGame : () {
          if (_isGameOver) {
            _resetGame();
          } else {
            // It should be AI's turn to suggest a move if it's AI vs Human
            // For now, let's assume it suggests for the current player
            if (_currentPlayer == PieceType.black) { // Example: AI plays as Black
              AIMove? bestMove = _ai.findBestMove(_boardData, _currentPlayer);
              setState(() {
                _suggestedMove = bestMove;
                if (bestMove != null) {
                  print("AI suggests moving from ${bestMove.from} to ${bestMove.to} (Score: ${bestMove.score})");
                  // Next step: highlight this move on the board
                } else {
                  print("AI found no moves.");
                }
              });
            } else {
              print("Not AI's turn (or AI not configured for current player).");
              // Or, if you want the button to always suggest for current player:
              // AIMove? bestMove = _ai.findBestMove(_boardData, _currentPlayer); ...
            }
          }
        },
          child: Text(_isGameOver ? 'Play Again' : 'Get AI Suggestion'),
                ),
                // Optionally add a dedicated reset button if "Get AI Suggestion" is kept
                if (!_isGameOver && true) // Control if you want a separate reset during game
                   SizedBox(height: 10),
                if (!_isGameOver && true)
                   ElevatedButton(onPressed: _resetGame, child: Text("Reset Game (Debug)")),

              ],
            ),
          ),
        ],
      ),
    ),
  );
 }
}