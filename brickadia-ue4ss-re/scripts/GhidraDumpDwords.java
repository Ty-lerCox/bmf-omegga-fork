// Dump dword values from an address range and interpret plausible RVAs.
// @category Brickadia

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class GhidraDumpDwords extends GhidraScript {

    private static final long IMAGE_BASE = 0x140000000L;

    @Override
    protected void run() throws Exception {
        if (getScriptArgs().length < 2) {
            printerr("usage: GhidraDumpDwords <address> <count>");
            return;
        }

        Address address = toAddr(getScriptArgs()[0]);
        int count = Integer.decode(getScriptArgs()[1]);

        for (int i = 0; i < count; i++) {
            Address current = address.add((long) i * 4L);
            long raw = Integer.toUnsignedLong(getInt(current));
            StringBuilder line = new StringBuilder();
            line.append(current).append(" -> ").append(String.format("%08x", raw));

            if (raw >= 0x1000 && raw < 0x10000000L) {
                Address candidate = toAddr(IMAGE_BASE + raw);
                line.append(" candidate=").append(candidate);
                Function function = getFunctionAt(candidate);
                if (function != null) {
                    line.append(" (")
                        .append(function.getName(true))
                        .append(" @ ")
                        .append(function.getEntryPoint())
                        .append(")");
                }
            }

            println(line.toString());
        }
    }
}
