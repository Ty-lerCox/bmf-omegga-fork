// Dump qword values from an address range.
// @category Brickadia

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class GhidraDumpQwords extends GhidraScript {

    @Override
    protected void run() throws Exception {
        if (getScriptArgs().length < 2) {
            printerr("usage: GhidraDumpQwords <address> <count>");
            return;
        }

        Address address = toAddr(getScriptArgs()[0]);
        int count = Integer.decode(getScriptArgs()[1]);

        for (int i = 0; i < count; i++) {
            Address current = address.add((long) i * 8L);
            long value = getLong(current);
            Address valueAddr = toAddr(value);
            Function function = getFunctionAt(valueAddr);
            String label = "";

            if (function != null) {
                label = " (" + function.getName(true) + " @ " + function.getEntryPoint() + ")";
            } else {
                var data = getDataAt(valueAddr);
                if (data != null) {
                    label = " (data " + data.getAddress() + ")";
                }
            }

            println(current + " -> " + valueAddr + label);
        }
    }
}
