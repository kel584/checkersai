// Ensure these imports are present
//import 'package:flutter/foundation.dart'; // For compute
import '../models/piece_model.dart';
import '../game_rules/game_rules.dart';
import 'checkers_ai.dart'; // Your CheckersAI class

class AIFindBestMoveParams {
  final GameRules rules;
  final List<List<Piece?>> board;
  final PieceType playerType;
  final int searchDepth;
  final int quiescenceSearchDepth;

  AIFindBestMoveParams({
    required this.rules,
    required this.board,
    required this.playerType,
    required this.searchDepth,
    required this.quiescenceSearchDepth,
  });
}

AIMove? findBestMoveIsolate(AIFindBestMoveParams params) {
  // This function runs in the new isolate
  final ai = CheckersAI(
    rules: params.rules,
    searchDepth: params.searchDepth,
    quiescenceSearchDepth: params.quiescenceSearchDepth,
  );
  return ai.findBestMove(params.board, params.playerType);
}