// Can be in bitboard_state.dart or a new lib/utils/bit_utils.dart

// Sets the bit for a given square (0-63) in a bitboard
int setBit(int bitboard, int squareIndex) {
  return bitboard | (1 << squareIndex);
}

// Clears the bit for a given square
int clearBit(int bitboard, int squareIndex) {
  return bitboard & (~(1 << squareIndex));
}

// Checks if a bit for a given square is set
bool isSet(int bitboard, int squareIndex) {
  return (bitboard & (1 << squareIndex)) != 0;
}

// Converts row, col to square index (0-63)
int rcToIndex(int r, int c) => r * 8 + c;