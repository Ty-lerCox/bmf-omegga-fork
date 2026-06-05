// List all references to a specific address.
// @category Brickadia

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.MemoryAccessException;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;

public class GhidraListReferencesToAddress extends GhidraScript {

    private String describeDataAt(Address address) {
        Data data = getDataContaining(address);
        if (data == null) {
            return "no data";
        }
        return data.getClass().getSimpleName() + " @" + data.getAddress();
    }

    private String describeByte(Address address) {
        try {
            return String.format(" byte=%02x", currentProgram.getMemory().getByte(address) & 0xff);
        } catch (MemoryAccessException e) {
            return "";
        }
    }

    @Override
    protected void run() throws Exception {
        if (getScriptArgs().length < 1) {
            printerr("usage: GhidraListReferencesToAddress <address>");
            return;
        }

        Address target = toAddr(getScriptArgs()[0]);
        println("Target " + target);

        ReferenceIterator refs = currentProgram.getReferenceManager().getReferencesTo(target);
        int count = 0;

        while (refs.hasNext()) {
            Reference ref = refs.next();
            Address from = ref.getFromAddress();
            Function function = getFunctionContaining(from);
            Data data = getDataContaining(from);

            String owner;
            if (function != null) {
                owner = "function: " + function.getName(true) + " @ " + function.getEntryPoint();
            } else if (data != null) {
                owner = "data: " + data.getDataType().getDisplayName() + " @ " + data.getAddress();
            } else {
                owner = "owner: none";
            }

            println("  from " + from + " type=" + ref.getReferenceType() + describeByte(from));
            println("    " + owner);
            count++;
        }

        if (count == 0) {
            println("  no references found");
        }
    }
}
