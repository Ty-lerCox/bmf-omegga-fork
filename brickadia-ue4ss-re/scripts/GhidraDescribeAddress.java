// Describe data, symbol, function, and printable bytes around an address.
// @category Brickadia

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryAccessException;
import ghidra.program.model.symbol.Symbol;

public class GhidraDescribeAddress extends GhidraScript {

    private String printableAscii(Address address, int maxLen) {
        Memory memory = currentProgram.getMemory();
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < maxLen; i++) {
            try {
                byte b = memory.getByte(address.add(i));
                if (b == 0) {
                    break;
                }
                int c = b & 0xff;
                if (c < 0x20 || c > 0x7e) {
                    break;
                }
                sb.append((char) c);
            } catch (MemoryAccessException e) {
                break;
            }
        }
        return sb.toString();
    }

    @Override
    protected void run() throws Exception {
        if (getScriptArgs().length < 1) {
            printerr("usage: GhidraDescribeAddress <address>");
            return;
        }

        Address address = toAddr(getScriptArgs()[0]);
        println("Address " + address);

        Symbol primary = getSymbolAt(address);
        if (primary != null) {
            println("  symbol: " + primary.getName(true));
        }

        Function function = getFunctionAt(address);
        if (function != null) {
            println("  function: " + function.getName(true) + " @ " + function.getEntryPoint());
        }

        Data containing = getDataContaining(address);
        if (containing != null) {
            println("  data containing: " + containing.getDataType().getDisplayName() + " @ " + containing.getAddress());
            println("  data value: " + containing.getDefaultValueRepresentation());
        }

        Data exact = getDataAt(address);
        if (exact != null && exact != containing) {
            println("  data at: " + exact.getDataType().getDisplayName() + " @ " + exact.getAddress());
            println("  exact value: " + exact.getDefaultValueRepresentation());
        }

        String ascii = printableAscii(address, 120);
        if (!ascii.isEmpty()) {
            println("  ascii: " + ascii);
        }
    }
}
