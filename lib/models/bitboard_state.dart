// lib/models/bitboard_state.dart

import 'package:checkersai/utils/bit_utils.dart';

import 'piece_model.dart'; // Assuming Piece, PieceType, BoardPosition are here

// Helper functions for square-to-index and index-to-square conversions
// These can be top-level or static methods in a utility class.
int rcToIndex(int r, int c) => r * 8 + c;
int indexToRow(int index) => index ~/ 8;
int indexToCol(int index) => index % 8;

class BitboardState {
  int blackMen;
  int blackKings;
  int redMen;
  int redKings;

  // Mask for the 8x8 board (all 64 bits set to 1)
  // Dart's 'int' is 64-bit on native platforms. For web, if 'int' is not 64-bit
  // for bitwise operations, BigInt would be required, significantly changing the approach.
  // We are proceeding assuming native 64-bit int behavior.
  static const int _boardMask = 0xFFFFFFFFFFFFFFFF;

  BitboardState({
    this.blackMen = 0,
    this.blackKings = 0,
    this.redMen = 0,
    this.redKings = 0,
  });

  // --- Derived Bitboards (Read-only getters) ---
  int get allBlackPieces => blackMen | blackKings;
  int get allRedPieces => redMen | redKings;
  int get allOccupiedSquares => allBlackPieces | allRedPieces;
  // Ensure empty squares are masked to the board area if ~occupied might set higher bits
  int get allEmptySquares => (~allOccupiedSquares) & _boardMask;

  // --- Utility Methods ---

  /// Checks if a specific bit (square) is set in the given bitboard.
  bool isBitSet(int bitboard, int squareIndex) {
    return (bitboard & (1 << squareIndex)) != 0;
  }

  /// Gets the Piece object at a given square, or null if empty.
  /// This is useful for UI or logic that needs Piece details.
  Piece? getPieceAt(int r, int c) {
    final int index = rcToIndex(r,c);
    if (isBitSet(blackMen, index)) return Piece(type: PieceType.black, isKing: false);
    if (isBitSet(blackKings, index)) return Piece(type: PieceType.black, isKing: true);
    if (isBitSet(redMen, index)) return Piece(type: PieceType.red, isKing: false);
    if (isBitSet(redKings, index)) return Piece(type: PieceType.red, isKing: true);
    return null;
  }
  
  /// Checks if a square is occupied by any piece.
  bool isSquareOccupied(int r, int c) {
    return isBitSet(allOccupiedSquares, rcToIndex(r, c));
  }

  /// Creates a deep copy of this BitboardState.
  BitboardState copy() {
    return BitboardState(
      blackMen: blackMen,
      blackKings: blackKings,
      redMen: redMen,
      redKings: redKings,
    );
  }

  /// Clears all piece information from the bitboards.
  void clear() {
      blackMen = 0;
      blackKings = 0;
      redMen = 0;
      redKings = 0;
  }

  /// For debugging: A simple string representation of all core bitboards.
  @override
  String toString() {
    StringBuffer sb = StringBuffer();
    sb.writeln("Black Men:  ${blackMen.toRadixString(2).padLeft(64, '0')}");
    sb.writeln("BlackKings: ${blackKings.toRadixString(2).padLeft(64, '0')}");
    sb.writeln("Red Men:    ${redMen.toRadixString(2).padLeft(64, '0')}");
    sb.writeln("Red Kings:  ${redKings.toRadixString(2).padLeft(64, '0')}");
    sb.writeln("Occupied:   ${allOccupiedSquares.toRadixString(2).padLeft(64, '0')}");
    sb.writeln("Empty:      ${allEmptySquares.toRadixString(2).padLeft(64, '0')}");
    return sb.toString();
  }

  // You might add methods here to directly manipulate the bitboards, e.g.:
  // void setPiece(int r, int c, PieceType type, bool isKing) { ... }
  // void removePiece(int r, int c, PieceType type, bool isKing) { ... }
  // These would use the setBit/clearBit utilities and update the correct bitboard.
  // For example:
  void _updatePieceOnBoard(int r, int c, PieceType type, bool isKing, bool set) {
      final int index = rcToIndex(r,c);
      int Function(int, int) operation = set ? setBit : clearBit;

      if (type == PieceType.black) {
          if (isKing) blackKings = operation(blackKings, index);
          else blackMen = operation(blackMen, index);
      } else { // PieceType.red
          if (isKing) redKings = operation(redKings, index);
          else redMen = operation(redMen, index);
      }
  }
  void addPiece(int r, int c, PieceType type, bool isKing) => _updatePieceOnBoard(r, c, type, isKing, true);
  void removePiece(int r, int c, PieceType type, bool isKing) => _updatePieceOnBoard(r, c, type, isKing, false);
  
  // More specific removal if you don't know the exact type being removed, only its position
  void clearSquare(int r, int c) {
    final int index = rcToIndex(r, c);
    blackMen = clearBit(blackMen, index);
    blackKings = clearBit(blackKings, index);
    redMen = clearBit(redMen, index);
    redKings = clearBit(redKings, index);
  }
}

// Bit utility functions (can also be static methods within BitboardState or a BitUtils class)
// These should already be in your lib/utils/bit_utils.dart or similar based on prior steps.
// int setBit(int bitboard, int squareIndex) => bitboard | (1 << squareIndex);
// int clearBit(int bitboard, int squareIndex) => bitboard & (~(1 << squareIndex));
// bool isSet(int bitboard, int squareIndex) => (bitboard & (1 << squareIndex)) != 0;