/* Message breakdowns are structured like this:

0xABCDEFGH

A - Message type,
B - Message size,
C - First nibble,
D - Second nibble
Etcetera.
*/

#define A_STATUS 0
// A - A_STATUS
// B - Length: 1
// C - Analogue pin number, starting at 0
// D - State as per A_SHORT, etc, below
#define A_RAW 1
// A - A_RAW
// B - Length: 2
// C - Analogue pin number, starting at 0
// DEF - Raw analogue value, 0-1023
#define D_STATUS 2
// A - D_STATUS
// B - Length: 1
// C - Digital pin number, starting at 0
// D - 0 or 1
#define CARD_NUM 3
// A - CARD_NUM
// B - Length: Varies
// C... - Raw card data.
#define D_SET 4
// A - D_SET
// B - Length: 1
// C - Digital pin number, starting at 0
// D - 0 or 1
#define D_PULSE 5
// A - D_PULSE
// B - Length: 1
// C - Digital pin number, starting at 0
// D - Padding: 0
// EFGHIJKL - unsigned long, pulse duration in milliseconds.
#define EEPROM_SET 6
// A - EEPROM_SET
// B - Length: Varies
// C - High byte of EEPROM address
// D - Low byte of EEPROM address
// E... - Value to write to EEPROM
#define MORE_MSG 7
// A - MORE_MSG
// B - Length: 0

// These aren't message types per se, they're analogue point states
#define A_SHORT 0
#define A_SECURE 1
#define A_TAMPER 2
#define A_OPEN 3
#define A_OPENCIRCUIT 4