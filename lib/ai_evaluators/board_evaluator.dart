// lib/ai_evaluators/board_evaluator.dart
import '../models/piece_model.dart';
import '../models/bitboard_state.dart'; // NEW IMPORT
import '../game_rules/game_rules.dart';

abstract class BoardEvaluator {
  double evaluate({
    required BitboardState board, // CHANGED: Takes BitboardState
    required PieceType aiPlayerType,
    required GameRules rules,
  });
}