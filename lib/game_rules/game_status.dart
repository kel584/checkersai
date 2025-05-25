// lib/game_rules/game_status.dart
import '../models/piece_model.dart';
enum GameEndReason {
  checkmate, // Not for checkers, but good for a generic enum
  stalemate, // In checkers, usually a loss for the player with no moves
  noMovesLeft,
  noPiecesLeft,
  threefoldRepetition,
  fiftyMoveRule, // Or a checkers equivalent (e.g., 40 moves no capture/man move)
  insufficientMaterial,
  agreement,
}

class GameStatus {
  final bool isOver;
  final PieceType? winner; // null if draw or ongoing
  final GameEndReason? reason; // null if ongoing

  GameStatus.ongoing() : isOver = false, winner = null, reason = null;
  GameStatus.win(this.winner, this.reason) : isOver = true;
  GameStatus.draw(this.reason) : isOver = true, winner = null;

  @override
  String toString() {
    if (!isOver) return "Ongoing";
    if (winner != null) return "${winner.toString().split('.').last} wins by $reason";
    return "Draw by $reason";
  }
}