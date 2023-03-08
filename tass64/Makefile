TASS64 = 64tass
TASS64_OPTS = -Wno-wrap-addr --verbose-list
DD = dd
DD_OPTS = skip=49144 count=16384 bs=1
HEXDUMP = hexdump
HEXDUMP_OPTS = -v -e '1/1 "%02x " "\n"'

all: 6502_functional_test.hex 6502_decimal_test.hex 65C02_extended_opcodes_test.hex 65C02_decimal_test.hex 65CE02_opcodes_test.hex

6502_functional_test.hex: 6502_functional_test.asm
	$(TASS64) $(TASS64_OPTS) 6502_functional_test.asm -o 6502_functional_test.prg -L 6502_functional_test.lst
	$(DD) $(DD_OPTS) if=6502_functional_test.prg of=6502_functional_test.bin
	$(HEXDUMP) $(HEXDUMP_OPTS) 6502_functional_test.bin > 6502_functional_test.hex

6502_decimal_test.hex: 6502_decimal_test.asm
	$(TASS64) $(TASS64_OPTS) -Dcputype=0 6502_decimal_test.asm -o 6502_decimal_test.prg -L 6502_decimal_test.lst
	$(DD) $(DD_OPTS) if=6502_decimal_test.prg of=6502_decimal_test.bin
	$(HEXDUMP) $(HEXDUMP_OPTS) 6502_decimal_test.bin > 6502_decimal_test.hex

65C02_extended_opcodes_test.hex: 65C02_extended_opcodes_test.asm
	$(TASS64) $(TASS64_OPTS) 65C02_extended_opcodes_test.asm -o 65C02_extended_opcodes_test.prg -L 65C02_extended_opcodes_test.lst
	$(DD) $(DD_OPTS) if=65C02_extended_opcodes_test.prg of=65C02_extended_opcodes_test.bin
	$(HEXDUMP) $(HEXDUMP_OPTS) 65C02_extended_opcodes_test.bin > 65C02_extended_opcodes_test.hex

65C02_decimal_test.hex: 6502_decimal_test.asm
	$(TASS64) $(TASS64_OPTS) -Dcputype=1 6502_decimal_test.asm -o 65C02_decimal_test.prg -L 65C02_decimal_test.lst
	$(DD) $(DD_OPTS) if=65C02_decimal_test.prg of=65C02_decimal_test.bin
	$(HEXDUMP) $(HEXDUMP_OPTS) 65C02_decimal_test.bin > 65C02_decimal_test.hex

65CE02_opcodes_test.hex: 65CE02_opcodes_test.asm
	$(TASS64) $(TASS64_OPTS) 65CE02_opcodes_test.asm -o 65CE02_opcodes_test.prg -L 65CE02_opcodes_test.lst
	$(DD) $(DD_OPTS) if=65CE02_opcodes_test.prg of=65CE02_opcodes_test.bin
	$(HEXDUMP) $(HEXDUMP_OPTS) 65CE02_opcodes_test.bin > 65CE02_opcodes_test.hex

clean:
	-rm -f *.hex *.bin *.prg *.lst
