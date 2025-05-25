// lib/ai_evaluators/board_evaluator.dart
import '../models/piece_model.dart';
import '../game_rules/game_rules.dart'; // Evaluator might need access to game rules for things like move generation

abstract class BoardEvaluator {
  double evaluate({
    required List<List<Piece?>> board,
    required PieceType aiPlayerType,
    required GameRules rules, // Pass rules for context (e.g., calling rules.getAllMovesForPlayer)
  });
}