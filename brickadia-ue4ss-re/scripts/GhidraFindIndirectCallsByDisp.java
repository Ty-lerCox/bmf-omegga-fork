// Find indirect CALL/JMP instructions using a specific displacement inside an address range.
// @category Brickadia

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.scalar.Scalar;

public class GhidraFindIndirectCallsByDisp extends GhidraScript {

    private boolean isCandidateMnemonic(Instruction instruction) {
        String mnemonic = instruction.getMnemonicString();
        return "CALL".equals(mnemonic) || "JMP".equals(mnemonic);
    }

    private boolean operandMentionsDisp(Instruction instruction, long displacement) {
        if (instruction.getNumOperands() < 1) {
            return false;
        }

        for (Object object : instruction.getOpObjects(0)) {
            if (object instanceof Scalar scalar) {
                long value = scalar.getSignedValue();
                if (value == displacement) {
                    return true;
                }
            }
        }

        String rendered = instruction.getDefaultOperandRepresentation(0);
        if (rendered == null) {
            return false;
        }

        String lower = rendered.toLowerCase();
        String hex = String.format("0x%x", displacement).toLowerCase();
        String plain = Long.toString(displacement);
        return lower.contains(hex) || lower.contains("+" + plain) || lower.contains("-" + plain);
    }

    @Override
    protected void run() throws Exception {
        if (getScriptArgs().length < 3) {
            printerr("usage: GhidraFindIndirectCallsByDisp <rangeStart> <rangeEnd> <displacement>");
            return;
        }

        Address rangeStart = toAddr(getScriptArgs()[0]);
        Address rangeEnd = toAddr(getScriptArgs()[1]);
        long displacement = Long.decode(getScriptArgs()[2]);

        Instruction instruction = getInstructionAt(rangeStart);
        int matches = 0;
        while (instruction != null && instruction.getAddress().compareTo(rangeEnd) <= 0) {
            if (isCandidateMnemonic(instruction) && operandMentionsDisp(instruction, displacement)) {
                Function function = getFunctionContaining(instruction.getAddress());
                println(instruction.getAddress() + " :: " + instruction);
                println(
                    "  function: "
                        + (function == null
                            ? "no function"
                            : function.getName(true) + " @ " + function.getEntryPoint())
                );
                matches++;
            }
            instruction = instruction.getNext();
        }

        println("matches=" + matches);
    }
}
