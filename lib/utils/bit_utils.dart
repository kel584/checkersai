// lib/utils/bit_utils.dart

// Sets the bit for a given square (0-63) in a bitboard
int setBit(int bitboard, int squareIndex) {
  // Use BigInt for safe 64-bit operations, then convert back
  if (squareIndex < 0 || squareIndex > 63) {
    throw ArgumentError('Square index must be between 0 and 63, got: $squareIndex');
  }
  
  // For indices 0-30, we can use regular int operations
  if (squareIndex <= 30) {
    return bitboard | (1 << squareIndex);
  }
  
  // For indices 31-63, we need to be careful with bit operations
  // Create the bit mask using BigInt and convert back to int
  final BigInt mask = BigInt.one << squareIndex;
  final BigInt result = BigInt.from(bitboard) | mask;
  return result.toSigned(64).toInt();
}

// Clears the bit for a given square
int clearBit(int bitboard, int squareIndex) {
  if (squareIndex < 0 || squareIndex > 63) {
    throw ArgumentError('Square index must be between 0 and 63, got: $squareIndex');
  }
  
  // For indices 0-30, we can use regular int operations
  if (squareIndex <= 30) {
    return bitboard & (~(1 << squareIndex));
  }
  
  // For indices 31-63, use BigInt operations
  final BigInt mask = ~(BigInt.one << squareIndex);
  final BigInt result = BigInt.from(bitboard) & mask;
  return result.toSigned(64).toInt();
}

// Checks if a bit for a given square is set
bool isSet(int bitboard, int squareIndex) {
  if (squareIndex < 0 || squareIndex > 63) {
    throw ArgumentError('Square index must be between 0 and 63, got: $squareIndex');
  }
  
  // For indices 0-30, we can use regular int operations
  if (squareIndex <= 30) {
    return (bitboard & (1 << squareIndex)) != 0;
  }
  
  // For indices 31-63, use BigInt operations
  final BigInt mask = BigInt.one << squareIndex;
  final BigInt bb = BigInt.from(bitboard);
  return (bb & mask) != BigInt.zero;
}

// Converts row, col to square index (0-63)
int rcToIndex(int r, int c) {
  if (r < 0 || r > 7 || c < 0 || c > 7) {
    throw ArgumentError('Row and column must be between 0 and 7, got: r=$r, c=$c');
  }
  return r * 8 + c;
}

// Converts square index to row
int indexToRow(int index) {
  if (index < 0 || index > 63) {
    throw ArgumentError('Index must be between 0 and 63, got: $index');
  }
  return index ~/ 8;
}

// Converts square index to column
int indexToCol(int index) {
  if (index < 0 || index > 63) {
    throw ArgumentError('Index must be between 0 and 63, got: $index');
  }
  return index % 8;
}

// Helper function to count set bits (population count)
int popCount(int bitboard) {
  int count = 0;
  int n = bitboard;
  while (n != 0) {
    n &= (n - 1); // Clear the least significant set bit
    count++;
  }
  return count;
}

// Helper function to get the index of the least significant bit
int lsbIndex(int bitboard) {
  if (bitboard == 0) return -1;
  
  // Find the least significant bit using bitboard & -bitboard
  int lsb = bitboard & -bitboard;
  
  // Count trailing zeros to get the index
  int index = 0;
  while (lsb > 1) {
    lsb >>= 1;
    index++;
  }
  return index;
}

// Alternative LSB implementation that's more efficient
int lsbIndexFast(int bitboard) {
  if (bitboard == 0) return -1;
  
  // Use De Bruijn multiplication for fast bit scan
  // This is a well-known bit manipulation technique
  const int debruijn64 = 0x03f566f92930aa;
  const List<int> index64 = [
     0,  1, 12,  2, 13, 22, 17,  3, 14, 33, 23, 36, 18, 58, 28,  4,
    62, 15, 34, 26, 24, 48, 50, 37, 19, 55, 59, 52, 29, 44, 39,  5,
    63, 11, 21, 16, 32, 35, 57, 27, 61, 25, 47, 49, 54, 51, 43, 38,
    10, 20, 31, 56, 60, 46, 53, 42,  9, 30, 45, 41,  8, 40,  7,  6
  ];
  
  return index64[((bitboard & -bitboard) * debruijn64) >> 58];
}

// Print bitboard for debugging (8x8 grid)
String printBitboard(int bitboard) {
  final StringBuffer sb = StringBuffer();
  for (int r = 7; r >= 0; r--) { // Print from top to bottom
    for (int c = 0; c < 8; c++) {
      final int index = rcToIndex(r, c);
      sb.write(isSet(bitboard, index) ? '1' : '0');
      sb.write(' ');
    }
    sb.writeln();
  }
  return sb.toString();
}