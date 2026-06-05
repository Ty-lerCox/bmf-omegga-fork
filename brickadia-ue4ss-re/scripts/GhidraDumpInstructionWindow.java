// Dump instructions around a target address.
// @category Brickadia

import java.util.ArrayList;
import java.util.List;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;

public class GhidraDumpInstructionWindow extends GhidraScript {

    @Override
    protected void run() throws Exception {
        if (getScriptArgs().length < 2) {
            printerr("usage: GhidraDumpInstructionWindow <address> <radius>");
            return;
        }

        Instruction center = getInstructionAt(toAddr(getScriptArgs()[0]));
        int radius = Integer.decode(getScriptArgs()[1]);
        if (center == null) {
            printerr("no instruction at address");
            return;
        }

        List<Instruction> window = new ArrayList<>();
        Instruction cursor = center;
        for (int i = 0; i < radius && cursor.getPrevious() != null; i++) {
            cursor = cursor.getPrevious();
        }

        for (int i = 0; i <= radius * 2 && cursor != null; i++) {
            window.add(cursor);
            cursor = cursor.getNext();
        }

        Function function = getFunctionContaining(center.getAddress());
        println(
            "Function: "
                + (function == null ? "no function" : function.getName(true) + " @ " + function.getEntryPoint())
        );
        for (Instruction instruction : window) {
            String marker = instruction.getAddress().equals(center.getAddress()) ? ">> " : "   ";
            println(marker + instruction.getAddress() + ": " + instruction);
        }
    }
}
