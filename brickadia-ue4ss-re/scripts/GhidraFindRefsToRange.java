// Find instruction operand refs into a caller-supplied address range.
// @category Brickadia

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.symbol.Reference;

public class GhidraFindRefsToRange extends GhidraScript {

    private boolean inRange(Address address, Address start, Address endExclusive) {
        return address.compareTo(start) >= 0 && address.compareTo(endExclusive) < 0;
    }

    @Override
    protected void run() throws Exception {
        if (getScriptArgs().length < 2) {
            printerr("usage: GhidraFindRefsToRange <start> <endExclusive>");
            return;
        }

        Address start = toAddr(getScriptArgs()[0]);
        Address endExclusive = toAddr(getScriptArgs()[1]);
        int matches = 0;

        println("Range " + start + "-" + endExclusive);

        Instruction instruction = getFirstInstruction();
        while (instruction != null) {
            boolean matched = false;
            for (int operandIndex = 0; operandIndex < instruction.getNumOperands(); operandIndex++) {
                Reference[] refs = instruction.getOperandReferences(operandIndex);
                for (Reference ref : refs) {
                    Address to = ref.getToAddress();
                    if (to != null && inRange(to, start, endExclusive)) {
                        Function function = getFunctionContaining(instruction.getAddress());
                        println("  " + instruction.getAddress() + " :: " + instruction);
                        println("    operand " + operandIndex + " -> " + to);
                        println(
                            "    function: "
                                + (function == null
                                    ? "no function"
                                    : function.getName(true) + " @ " + function.getEntryPoint())
                        );
                        matches++;
                        matched = true;
                        break;
                    }
                }
                if (matched) {
                    break;
                }
            }
            instruction = instruction.getNext();
        }

        if (matches == 0) {
            println("  no instruction references found");
        }
    }
}
