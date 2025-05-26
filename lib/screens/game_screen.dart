// lib/screens/game_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For compute (if using isolates for AI)
import 'dart:isolate'; // For Isolate, SendPort, ReceivePort (if using long-lived isolate)
import 'dart:async';   // For Completer (if using with long-lived isolate)

import '../models/piece_model.dart';
import '../models/bitboard_state.dart'; // Import BitboardState
import '../widgets/board_widget.dart';
import '../ai/checkers_ai.dart';     // For AIMove, CheckersAI
// Import your isolate helper if you created one for parameters and top-level function
// e.g., import '../ai/ai_isolate_helper.dart'; or ensure findBestMoveIsolate is accessible
import '../game_rules/game_rules.dart';
import '../game_rules/standard_checkers_rules.dart';
import '../game_rules/turkish_checkers_rules.dart';
import '../game_rules/game_status.dart';

// If using the long-lived isolate pattern, define message classes and entry point
// (These might be in a separate ai_isolate_manager.dart or similar)
class AIComputeRequest {
  final BitboardState board; // Now BitboardState
  final PieceType playerType;
  final GameRules rules;
  final int searchDepth;
  final int quiescenceSearchDepth;
  final SendPort replyPort;

  AIComputeRequest({
    required this.board,
    required this.playerType,
    required this.rules,
    required this.searchDepth,
    required this.quiescenceSearchDepth,
    required this.replyPort,
  });
}

class AIComputeResponse {
  final AIMove? move;
  AIComputeResponse(this.move);
}

// Top-level function for the isolate
void aiIsolateEntry(SendPort mainSendPort) async {
  final ReceivePort isolateReceivePort = ReceivePort();
  mainSendPort.send(isolateReceivePort.sendPort);

  await for (var message in isolateReceivePort) {
    if (message is AIComputeRequest) {
      final ai = CheckersAI(
        rules: message.rules,
        searchDepth: message.searchDepth,
        quiescenceSearchDepth: message.quiescenceSearchDepth,
      );
      // Pass the BitboardState directly
      final AIMove? bestMove = ai.findBestMove(message.board, message.playerType);
      message.replyPort.send(AIComputeResponse(bestMove));
    }
  }
}


class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late GameRules _currentRules;
  late BitboardState _boardData; // CHANGED to BitboardState
  late PieceType _currentPlayer;
  BoardPosition? _selectedPiecePosition;
  Set<BoardPosition> _validMoves = {};
  Map<String, int> _boardStateCounts = {};

  bool _isGameOver = false;
  PieceType? _winner;
  GameEndReason? _gameEndReason;

  late CheckersAI _ai; // AI instance itself
  AIMove? _suggestedMove;
  bool _isAiThinking = false;
  bool _isBoardFlipped = false;

  // For long-lived isolate
  Isolate? _aiIsolate;
  SendPort? _toAiIsolateSendPort;
  ReceivePort? _fromMainIsolateReceivePort; // Receives the SendPort from the AI isolate initially

  static const String _kDevPassword = "checkersdev25"; // Your dev password
  bool _isDevAccessGranted = false;


  @override
  void initState() {
    super.initState();
    _currentRules = StandardCheckersRules();
    // _ai instance is kept for holding parameters like searchDepth
    _ai = CheckersAI(rules: _currentRules, searchDepth: 4, quiescenceSearchDepth: 3);
    _spawnAiIsolate(); // Spawn the long-lived isolate
    _resetGame();
  }

  Future<void> _spawnAiIsolate() async {
    if (_aiIsolate != null) return; // Already spawned
    _fromMainIsolateReceivePort = ReceivePort();
    try {
      _aiIsolate = await Isolate.spawn(aiIsolateEntry, _fromMainIsolateReceivePort!.sendPort);
      final dynamic firstMessage = await _fromMainIsolateReceivePort!.first;
      if (firstMessage is SendPort) {
        _toAiIsolateSendPort = firstMessage;
      } else {
        print("Error: AI Isolate did not send back its SendPort.");
      }
    } catch (e) {
      print("Error spawning AI isolate: $e");
    }
  }

  @override
  void dispose() {
    _fromMainIsolateReceivePort?.close();
    _aiIsolate?.kill(priority: Isolate.immediate);
    super.dispose();
  }

  void _resetGame() {
    setState(() {
      _boardData = _currentRules.initialBoardSetup(); // Returns BitboardState
      _currentPlayer = _currentRules.startingPlayer;
      _selectedPiecePosition = null;
      _validMoves = {};
      _isGameOver = false;
      _winner = null;
      _gameEndReason = null;
      _suggestedMove = null;
      _boardStateCounts = {};
      String initialHash = _currentRules.generateBoardStateHash(_boardData, _currentPlayer);
      _boardStateCounts[initialHash] = 1;
      _isDevAccessGranted = false; // Reset dev access for AI suggestion
    });
  }

  void _changeGameVariant(GameRules newRules) {
    setState(() {
      _currentRules = newRules;
      // AI parameters are stored in _ai, but the 'rules' for computation are passed with each request
      // If _ai itself needs to change based on rules (e.g. different default depths), update _ai here.
      // For now, _ai.searchDepth and _ai.quiescenceSearchDepth are used from the existing _ai instance.
      _resetGame();
    });
  }

  void _handleSquareTap(int row, int col) {
    if (_isGameOver || _isAiThinking) return;

    final tappedPosition = BoardPosition(row, col);
    final Map<BoardPosition, Set<BoardPosition>> allTurnJumps =
        _currentRules.getAllMovesForPlayer(_boardData, _currentPlayer, true);
    final bool jumpsAreMandatoryThisTurn = allTurnJumps.isNotEmpty;

    setState(() {
      if (_suggestedMove != null) {
        _suggestedMove = null;
      }

      final Piece? pieceOnTappedSquare = _boardData.getPieceAt(row, col); // Use getPieceAt

      if (_selectedPiecePosition == null) {
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
            // getRegularMoves needs Piece details, which we got from getPieceAt
            _validMoves = _currentRules.getRegularMoves(tappedPosition, pieceOnTappedSquare, _boardData);
          }
        }
      } else { // A piece IS ALREADY SELECTED
        if (tappedPosition == _selectedPiecePosition) {
          _selectedPiecePosition = null;
          _validMoves = {};
        } else if (pieceOnTappedSquare != null && pieceOnTappedSquare.type == _currentPlayer) {
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
          MoveResult result = _currentRules.applyMoveAndGetResult(
            currentBoard: _boardData, // Pass BitboardState
            from: _selectedPiecePosition!,
            to: tappedPosition,
            currentPlayer: _currentPlayer,
          );
          _boardData = result.board; // Receives BitboardState

          if (result.turnChanged) {
            _selectedPiecePosition = null;
            _validMoves = {};
            _currentPlayer = (_currentPlayer == PieceType.red) ? PieceType.black : PieceType.red;
            _updateAndCheckGameState();
          } else { // Multi-jump
            _selectedPiecePosition = tappedPosition;
            final pieceThatMoved = _boardData.getPieceAt(tappedPosition.row, tappedPosition.col);
            if (pieceThatMoved != null) {
              _validMoves = _currentRules.getFurtherJumps(tappedPosition, pieceThatMoved, _boardData);
              if (_validMoves.isEmpty) {
                _selectedPiecePosition = null;
                _currentPlayer = (_currentPlayer == PieceType.red) ? PieceType.black : PieceType.red;
                _updateAndCheckGameState();
              }
            } else {
              _selectedPiecePosition = null;
              _currentPlayer = (_currentPlayer == PieceType.red) ? PieceType.black : PieceType.red;
              _updateAndCheckGameState();
            }
          }
        } else {
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
      currentBoard: _boardData, // Pass BitboardState
      currentPlayer: _currentPlayer,
      allPossibleJumpsForCurrentPlayer: allJumps,
      allPossibleRegularMovesForCurrentPlayer: allRegularMoves,
      boardStateCounts: _boardStateCounts,
    );

    if (status.isOver) {
      setState(() {
        _isGameOver = true;
        _winner = status.winner;
        _gameEndReason = status.reason;
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
            child: ListBody(children: <Widget>[
              const Text('Enter the developer password to get an AI suggestion.'),
              const SizedBox(height: 10),
              TextField(
                controller: passwordController, obscureText: true,
                decoration: const InputDecoration(hintText: "Password", border: OutlineInputBorder()),
                // autofocus: false, // Keep autofocus off if it caused issues
                onSubmitted: (_) { Navigator.of(dialogContext).pop(passwordController.text);},
              ),
            ]),
          ),
          actions: <Widget>[
            TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(dialogContext).pop(null)),
            ElevatedButton(child: const Text('Submit'), onPressed: () => Navigator.of(dialogContext).pop(passwordController.text)),
          ],
        );
      },
    );
  }

  void _onAIAssistPressed() async {
    if (_isGameOver) {
      _resetGame();
      return;
    }
    if (_isAiThinking) return;

    if (!_isDevAccessGranted) {
      final String? enteredPassword = await _showPasswordDialog(context);
      if (enteredPassword == null || !mounted) return;
      if (enteredPassword == _kDevPassword) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Developer AI access granted for this game."), duration: Duration(seconds: 2)),
        );
        setState(() { _isDevAccessGranted = true; });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Incorrect password."), duration: Duration(seconds: 2)),
        );
        return;
      }
    }
    
    // Proceed with AI suggestion if access is granted
    setState(() { _isAiThinking = true; _suggestedMove = null; });

    if (_toAiIsolateSendPort == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("AI engine not ready. Retrying initialization...")));
        await _spawnAiIsolate(); // Try to respawn if not ready
        if(_toAiIsolateSendPort == null && mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("AI engine failed to initialize.")));
           setState(() => _isAiThinking = false);
           return;
        }
      } else { return; }
    }


    final ReceivePort replyPort = ReceivePort();
    final BitboardState boardCopyForAI = _boardData.copy();

    final request = AIComputeRequest(
      board: boardCopyForAI, playerType: _currentPlayer, rules: _currentRules,
      searchDepth: _ai.searchDepth, quiescenceSearchDepth: _ai.quiescenceSearchDepth,
      replyPort: replyPort.sendPort,
    );

    _toAiIsolateSendPort!.send(request);

    try {
      final dynamic response = await replyPort.first.timeout(const Duration(seconds: 60));
      if (response is AIComputeResponse) {
        if (!mounted) return;
        setState(() { _suggestedMove = response.move; });
        if (response.move == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("AI (${_currentRules.gameVariantName}) found no moves or timed out.")),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("AI Error: $e")));
    } finally {
      replyPort.close();
      if (mounted) setState(() => _isAiThinking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String appBarTitle = _currentRules.gameVariantName;
    String gameStatusText = "";
    Color appBarColor = Colors.brown[700]!;
    Color gameStatusMessageColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;

    if (_isGameOver) {
      if (_winner != null) {
        appBarTitle = "${_winner!.name.toUpperCase()} Wins! (${_currentRules.gameVariantName})";
        gameStatusText = "${_winner!.name.toUpperCase()} Wins by ${_gameEndReason?.name ?? 'Unknown'}!";
        appBarColor = _winner == PieceType.red ? Colors.red[900]! : Colors.black87;
        gameStatusMessageColor = appBarColor;
      } else { // Draw
        appBarTitle = "Draw! (${_currentRules.gameVariantName})";
        gameStatusText = "Draw by ${_gameEndReason?.name ?? 'Unknown'}!";
        appBarColor = Colors.blueGrey[700]!;
        gameStatusMessageColor = Colors.blueGrey[900]!;
      }
    } else {
      appBarTitle = '${_currentRules.gameVariantName} - ${_currentPlayer.name.toUpperCase()}\'s Turn';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        backgroundColor: appBarColor,
        actions: <Widget>[
          IconButton(
            icon: Icon(_isBoardFlipped ? Icons.flip_camera_android_outlined : Icons.flip_camera_android),
            tooltip: "Flip Board",
            onPressed: () {
              setState(() {
                _isBoardFlipped = !_isBoardFlipped;
                _selectedPiecePosition = null; _validMoves = {}; _suggestedMove = null;
              });
            },
          ),
          if (!_isGameOver)
            PopupMenuButton<GameRules>(
              icon: const Icon(Icons.settings_applications),
              tooltip: "Change Game Variant",
              onSelected: (GameRules selectedRules) {
                if (_currentRules.gameVariantName != selectedRules.gameVariantName) {
                  _changeGameVariant(selectedRules);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<GameRules>>[
                PopupMenuItem<GameRules>(value: StandardCheckersRules(), child: Text(StandardCheckersRules().gameVariantName)),
                PopupMenuItem<GameRules>(value: TurkishCheckersRules(), child: Text(TurkishCheckersRules().gameVariantName)),
              ],
            ),
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
                  child: LayoutBuilder(builder: (context, constraints) {
                    double potentialSize = constraints.maxWidth < constraints.maxHeight ? constraints.maxWidth : constraints.maxHeight;
                    double boardSize = (potentialSize > 0) ? potentialSize : 100.0;
                    // _boardData is now BitboardState
                    return BoardWidget(
                      boardData: _boardData, // Pass BitboardState
                      boardSize: boardSize,
                      onSquareTap: _isGameOver || _isAiThinking ? (r, c) {} : _handleSquareTap,
                      selectedPiecePosition: _selectedPiecePosition,
                      validMoves: _validMoves,
                      suggestedMoveFrom: _suggestedMove?.from,
                      suggestedMoveTo: _suggestedMove?.to,
                      isBoardFlipped: _isBoardFlipped,
                      // piecesOnDarkSquaresOnly: _currentRules.piecesOnDarkSquaresOnly, // If BoardWidget uses this
                    );
                  }),
                ),
              ),
            ),
            if (_isGameOver)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(gameStatusText, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: gameStatusMessageColor), textAlign: TextAlign.center),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_isGameOver)
                    Text("${_currentPlayer.name.toUpperCase()}'s Turn", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _currentPlayer == PieceType.red ? Colors.red[700] : Colors.black87)),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), textStyle: const TextStyle(fontSize: 16)),
                    onPressed: _isAiThinking ? null : _onAIAssistPressed,
                    child: _isAiThinking 
                           ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                           : Text(_isGameOver ? 'Play Again' : 'Get AI Suggestion'),
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