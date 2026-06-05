// Find instruction references into one or more candidate address ranges.
// @category Brickadia

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.symbol.Reference;

public class GhidraFindRangeRefs extends GhidraScript {

    private static final long[][] RANGES = new long[][] {
        { 0x147054000L, 0x147054800L, 0x147054000L },
        { 0x14752f180L, 0x14752f980L, 0x14752f180L },
    };

    private boolean inRange(Address address, long start, long endExclusive) {
        long offset = address.getOffset();
        return offset >= start && offset < endExclusive;
    }

    @Override
    protected void run() throws Exception {
        for (long[] range : RANGES) {
            long start = range[0];
            long endExclusive = range[1];
            long label = range[2];
            println(String.format("Range %x-%x (label %x)", start, endExclusive, label));

            int count = 0;
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
                            println("    function: "
                                + (function == null ? "no function"
                                    : function.getName(true) + " @ " + function.getEntryPoint()));
                            matched = true;
                            count++;
                            break;
                        }
                    }
                    if (matched) {
                        break;
                    }
                }
                instruction = instruction.getNext();
            }

            if (count == 0) {
                println("  no instruction references found");
            }
            println();
        }
    }
}
