// lib/screens/game_screen.dart
import 'package:flutter/material.dart';

import '../models/piece_model.dart';
import '../widgets/board_widget.dart';
import '../ai/checkers_ai.dart';
import '../game_rules/game_rules.dart';
import '../game_rules/standard_checkers_rules.dart';
import '../game_rules/turkish_checkers_rules.dart';
import '../game_rules/game_status.dart';

const String _kDevPassword = "checkersdev25";
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  
  late GameRules _currentRules;
  List<List<Piece?>> _boardData = [];
  late PieceType _currentPlayer;
  BoardPosition? _selectedPiecePosition;
  Set<BoardPosition> _validMoves = {};
  Map<String, int> _boardStateCounts = {};

  bool _isGameOver = false;
  PieceType? _winner;
  GameEndReason? _gameEndReason; // To store the reason for game end

  late CheckersAI _ai;
  AIMove? _suggestedMove;

  @override
  void initState() {
    super.initState();
    _currentRules = StandardCheckersRules(); // Default to standard checkers
    _ai = CheckersAI(rules: _currentRules, searchDepth: 3); // Pass current rules, adjust depth as needed
    _resetGame();
  }

  void _resetGame() {
    setState(() {
      _boardData = _currentRules.initialBoardSetup();
      _currentPlayer = _currentRules.startingPlayer;
      _selectedPiecePosition = null;
      _validMoves = {};
      _isGameOver = false;
      _winner = null;
      _gameEndReason = null; // Reset game end reason
      _suggestedMove = null;
      _boardStateCounts = {}; // Reset history
      // Add initial board state to history
      String initialHash = _currentRules.generateBoardStateHash(_boardData, _currentPlayer);
      _boardStateCounts[initialHash] = 1;
    });
  }

  void _changeGameVariant(GameRules newRules) {
    setState(() {
      _currentRules = newRules;
      _ai = CheckersAI(rules: _currentRules, searchDepth: 3); // Re-initialize AI with new rules
      _resetGame();
    });
  }

  void _handleSquareTap(int row, int col) {
    if (_isGameOver) return;

    final tappedPosition = BoardPosition(row, col);
    final Map<BoardPosition, Set<BoardPosition>> allTurnJumps =
        _currentRules.getAllMovesForPlayer(_boardData, _currentPlayer, true); // true for jumpsOnly
    final bool jumpsAreMandatoryThisTurn = allTurnJumps.isNotEmpty;

    setState(() {
      if (_suggestedMove != null) {
        _suggestedMove = null;
      }

      final pieceOnTappedSquare = _boardData[row][col];

      if (_selectedPiecePosition == null) {
        // === Trying to select a piece ===
        if (pieceOnTappedSquare != null && pieceOnTappedSquare.type == _currentPlayer) {
          if (jumpsAreMandatoryThisTurn) {
            if (allTurnJumps.containsKey(tappedPosition)) {
              _selectedPiecePosition = tappedPosition;
              _validMoves = allTurnJumps[tappedPosition]!;
            } else {
              _validMoves = {};
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("A jump is mandatory with another piece."), duration: Duration(seconds: 2)),
              );
            }
          } else {
            _selectedPiecePosition = tappedPosition;
            _validMoves = _currentRules.getRegularMoves(tappedPosition, pieceOnTappedSquare, _boardData);
          }
        }
      } else {
        // === A piece IS ALREADY SELECTED (_selectedPiecePosition is not null) ===
        if (tappedPosition == _selectedPiecePosition) {
          _selectedPiecePosition = null;
          _validMoves = {};
        } else if (pieceOnTappedSquare != null && pieceOnTappedSquare.type == _currentPlayer) {
          // Tapped another of current player's pieces: Try to switch selection
          if (jumpsAreMandatoryThisTurn) {
            if (allTurnJumps.containsKey(tappedPosition)) {
              _selectedPiecePosition = tappedPosition;
              _validMoves = allTurnJumps[tappedPosition]!;
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Invalid switch: A jump is mandatory with another piece."), duration: Duration(seconds: 2)),
              );
            }
          } else {
            _selectedPiecePosition = tappedPosition;
            _validMoves = _currentRules.getRegularMoves(tappedPosition, pieceOnTappedSquare, _boardData);
          }
        } else if (_validMoves.contains(tappedPosition)) {
          // Tapped a valid move square
          MoveResult result = _currentRules.applyMoveAndGetResult(
            currentBoard: _boardData,
            from: _selectedPiecePosition!,
            to: tappedPosition,
            currentPlayer: _currentPlayer,
          );
          _boardData = result.board;

          if (result.turnChanged) {
            _selectedPiecePosition = null;
            _validMoves = {};
            _currentPlayer = (_currentPlayer == PieceType.red) ? PieceType.black : PieceType.red;
            _updateAndCheckGameState();
          } else {
            // Multi-jump scenario
            _selectedPiecePosition = tappedPosition;
            final pieceThatMoved = _boardData[tappedPosition.row][tappedPosition.col];
            if (pieceThatMoved != null) {
              _validMoves = _currentRules.getFurtherJumps(tappedPosition, pieceThatMoved, _boardData);
              if (_validMoves.isEmpty) {
                _selectedPiecePosition = null; // No more jumps, turn ends
                _currentPlayer = (_currentPlayer == PieceType.red) ? PieceType.black : PieceType.red;
                _updateAndCheckGameState();
              }
            } else { // Should not happen
              _selectedPiecePosition = null;
              _currentPlayer = (_currentPlayer == PieceType.red) ? PieceType.black : PieceType.red;
              _updateAndCheckGameState();
            }
          }
        } else { // Tapped an invalid square
          _selectedPiecePosition = null;
          _validMoves = {};
        }
      }
    });
  }

  void _updateAndCheckGameState() {
    String currentHash = _currentRules.generateBoardStateHash(_boardData, _currentPlayer);
    _boardStateCounts[currentHash] = (_boardStateCounts[currentHash] ?? 0) + 1;

    final Map<BoardPosition, Set<BoardPosition>> allJumps =
        _currentRules.getAllMovesForPlayer(_boardData, _currentPlayer, true);
    final Map<BoardPosition, Set<BoardPosition>> allRegularMoves =
        (allJumps.isEmpty) ? _currentRules.getAllMovesForPlayer(_boardData, _currentPlayer, false) : {};

    GameStatus status = _currentRules.checkWinCondition(
      board: _boardData,
      currentPlayer: _currentPlayer,
      allPossibleJumps: allJumps,
      allPossibleRegularMoves: allRegularMoves,
      boardStateCounts: _boardStateCounts,
    );

    if (status.isOver) {
      setState(() {
        _isGameOver = true;
        _winner = status.winner;
        _gameEndReason = status.reason; // Store the reason
      });
    }
  }
Future<String?> _showPasswordDialog(BuildContext context) async {
  final TextEditingController passwordController = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('Developer AI Access'),
        content: SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              const Text('Enter the developer password to get an AI suggestion.'),
              const SizedBox(height: 10),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: "Password",
                  border: OutlineInputBorder(),
                ),
                // autofocus: true, // Let's try removing or commenting this out
                onSubmitted: (_) { // Allow submitting with enter key
                   Navigator.of(dialogContext).pop(passwordController.text);
                },
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () {
              Navigator.of(dialogContext).pop(null);
            },
          ),
          ElevatedButton(
            child: const Text('Submit'),
            onPressed: () {
              Navigator.of(dialogContext).pop(passwordController.text);
            },
          ),
        ],
      );
    },
  );
}

void _onAIAssistPressed() async { // Make the method async
  if (_isGameOver) {
    _resetGame();
    return;
  }

  // Show password dialog and wait for result
  final String? enteredPassword = await _showPasswordDialog(context);

  // Check if the dialog was cancelled or if the widget is no longer mounted
  if (enteredPassword == null || !mounted) {
    return; // User cancelled or widget is gone
  }

  if (enteredPassword == _kDevPassword) {
    // Password correct, proceed with AI suggestion
    AIMove? bestMove = _ai.findBestMove(_boardData, _currentPlayer);
    if (!mounted) return; // Check mounted again after async AI call

    setState(() {
      _suggestedMove = bestMove;
      if (bestMove == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  "AI (${_currentRules.gameVariantName}) found no moves for $_currentPlayer."),
              duration: const Duration(seconds: 2)),
        );
      }
    });
  } else {
    // Password incorrect
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("Incorrect password."),
          duration: Duration(seconds: 2)),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    String appBarTitle = _currentRules.gameVariantName;
    String gameStatusMessage = "";
    Color appBarColor = Colors.brown[700]!;
    Color gameStatusMessageColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;


    if (_isGameOver) {
      if (_winner != null) {
        appBarTitle = "${_winner.toString().split('.').last.toUpperCase()} Wins! (${_currentRules.gameVariantName})";
        gameStatusMessage = "${_winner.toString().split('.').last.toUpperCase()} Wins by ${_gameEndReason?.toString().split('.').last ?? 'Unknown'}!";
        appBarColor = _winner == PieceType.red ? Colors.red[900]! : Colors.black87;
        gameStatusMessageColor = _winner == PieceType.red ? Colors.red[900]! : Colors.black87;
      } else { // It's a draw
        appBarTitle = "Draw! (${_currentRules.gameVariantName})";
        gameStatusMessage = "Draw by ${_gameEndReason?.toString().split('.').last ?? 'Unknown'}!";
        appBarColor = Colors.blueGrey[700]!;
        gameStatusMessageColor = Colors.blueGrey[900]!;
      }
    } else {
      appBarTitle = '${_currentRules.gameVariantName} - ${_currentPlayer.toString().split('.').last.toUpperCase()}\'s Turn';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        backgroundColor: appBarColor,
        actions: [
          if (!_isGameOver) // Optionally hide settings when game is over
            PopupMenuButton<GameRules>(
              icon: const Icon(Icons.settings_applications),
              tooltip: "Change Game Variant",
              onSelected: (GameRules selectedRules) {
                if (_currentRules.gameVariantName != selectedRules.gameVariantName) {
                  _changeGameVariant(selectedRules);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<GameRules>>[
                PopupMenuItem<GameRules>(
                  value: StandardCheckersRules(),
                  child: Text(StandardCheckersRules().gameVariantName),
                ),
                PopupMenuItem<GameRules>(
                  value: TurkishCheckersRules(),
                  child: Text(TurkishCheckersRules().gameVariantName),
                ),
              ],
            )
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      double potentialSize = constraints.maxWidth < constraints.maxHeight
                          ? constraints.maxWidth
                          : constraints.maxHeight;
                      double boardSize = (potentialSize > 0) ? potentialSize : 0.01;

                      if (_boardData.isEmpty && !_isGameOver) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      return BoardWidget(
                        boardData: _boardData,
                        boardSize: boardSize,
                        onSquareTap: _isGameOver ? (r, c) {} : _handleSquareTap,
                        selectedPiecePosition: _selectedPiecePosition,
                        validMoves: _validMoves,
                        suggestedMoveFrom: _suggestedMove?.from,
                        suggestedMoveTo: _suggestedMove?.to,
                        // piecesOnDarkSquaresOnly: _currentRules.piecesOnDarkSquaresOnly, // Pass this to BoardWidget
                      );
                    },
                  ),
                ),
              ),
            ),
            if (_isGameOver)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  gameStatusMessage,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: gameStatusMessageColor),
                  textAlign: TextAlign.center,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min, // Important for Column in Column
                children: [
                  if (!_isGameOver)
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
                    onPressed: _onAIAssistPressed,
                    child: Text(_isGameOver ? 'Play Again' : 'Get AI Suggestion'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}