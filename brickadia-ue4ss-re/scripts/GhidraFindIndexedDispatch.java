// Find indexed dispatch sites that look like script VM opcode dispatch.
// @category Brickadia

import java.util.ArrayList;
import java.util.List;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.lang.OperandType;
import ghidra.program.model.scalar.Scalar;

public class GhidraFindIndexedDispatch extends GhidraScript {

    private static final int WINDOW_BACK = 16;

    private boolean isCallOrJump(Instruction instruction) {
        String mnemonic = instruction.getMnemonicString();
        return "CALL".equals(mnemonic) || "JMP".equals(mnemonic);
    }

    private boolean operandLooksIndexedMem(Instruction instruction) {
        if (instruction.getNumOperands() < 1) {
            return false;
        }
        String rendered = instruction.getDefaultOperandRepresentation(0);
        if (rendered == null) {
            return false;
        }
        String lower = rendered.toLowerCase();
        return lower.contains("[") && (lower.contains("*0x8") || lower.contains("*8"));
    }

    private Long extractScale(Instruction instruction) {
        if (instruction.getNumOperands() < 1) {
            return null;
        }
        String rendered = instruction.getDefaultOperandRepresentation(0);
        if (rendered != null) {
            String lower = rendered.toLowerCase();
            if (lower.contains("*0x8") || lower.contains("*8")) {
                return 8L;
            }
            if (lower.contains("*0x4") || lower.contains("*4")) {
                return 4L;
            }
            if (lower.contains("*0x2") || lower.contains("*2")) {
                return 2L;
            }
        }
        for (Object object : instruction.getOpObjects(0)) {
            if (object instanceof Scalar scalar) {
                long value = scalar.getUnsignedValue();
                if (value == 2 || value == 4 || value == 8) {
                    return value;
                }
            }
        }
        return null;
    }

    private Address extractRipTarget(Instruction instruction) {
        if (!"LEA".equals(instruction.getMnemonicString()) || instruction.getNumOperands() < 2) {
            return null;
        }
        int type = instruction.getOperandType(1);
        if ((type & OperandType.ADDRESS) == 0 || (type & OperandType.DYNAMIC) == 0) {
            return null;
        }
        Reference[] refs = instruction.getOperandReferences(1);
        if (refs.length == 0) {
            return null;
        }
        return refs[0].getToAddress();
    }

    private boolean looksLikeByteLoad(Instruction instruction) {
        if (!"MOVZX".equals(instruction.getMnemonicString()) || instruction.getNumOperands() < 2) {
            return false;
        }
        int type = instruction.getOperandType(1);
        if ((type & OperandType.ADDRESS) == 0 || (type & OperandType.DYNAMIC) == 0) {
            return false;
        }
        Object[] opObjects = instruction.getOpObjects(1);
        for (Object object : opObjects) {
            if (object instanceof Scalar scalar && scalar.getUnsignedValue() == 1) {
                return true;
            }
        }
        String rendered = instruction.getDefaultOperandRepresentation(1);
        return rendered != null && rendered.toLowerCase().contains("byte ptr");
    }

    @Override
    protected void run() throws Exception {
        List<Instruction> matches = new ArrayList<>();
        Instruction instruction = getFirstInstruction();
        while (instruction != null) {
            if (isCallOrJump(instruction) && operandLooksIndexedMem(instruction)) {
                Long scale = extractScale(instruction);
                if (scale != null && scale == 8) {
                    matches.add(instruction);
                }
            }
            instruction = instruction.getNext();
        }

        println("Indexed call/jump candidates (scale=8): " + matches.size());
        println();

        for (Instruction dispatch : matches) {
            Function function = getFunctionContaining(dispatch.getAddress());
            println("Dispatch: " + dispatch.getAddress() + " :: " + dispatch);
            println("Function: " + (function == null ? "no function" : function.getName(true) + " @ " + function.getEntryPoint()));

            Instruction cursor = dispatch;
            Address ripTarget = null;
            Instruction lea = null;
            Instruction byteLoad = null;
            List<Instruction> window = new ArrayList<>();

            for (int i = 0; i < WINDOW_BACK && cursor != null; i++) {
                window.add(0, cursor);
                if (cursor != dispatch) {
                    Address maybeTarget = extractRipTarget(cursor);
                    if (maybeTarget != null && ripTarget == null) {
                        ripTarget = maybeTarget;
                        lea = cursor;
                    }
                    if (looksLikeByteLoad(cursor) && byteLoad == null) {
                        byteLoad = cursor;
                    }
                }
                cursor = cursor.getPrevious();
            }

            println("  RIP table load: " + (lea == null ? "none" : lea.getAddress() + " -> " + ripTarget));
            println("  Byte load: " + (byteLoad == null ? "none" : byteLoad.getAddress() + " :: " + byteLoad));
            println("  Window:");
            for (Instruction line : window) {
                println("    " + line.getAddress() + ": " + line);
            }
            println();
        }
    }
}
