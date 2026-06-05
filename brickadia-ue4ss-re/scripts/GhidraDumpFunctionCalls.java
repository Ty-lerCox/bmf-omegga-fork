// Dump direct calls within a function and its callers.
// @category Brickadia

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.RefType;

public class GhidraDumpFunctionCalls extends GhidraScript {

	private String describeFunction(Function function) {
		if (function == null) {
			return "no function";
		}
		return function.getName(true) + " @ " + function.getEntryPoint();
	}

	@Override
	protected void run() throws Exception {
		if (getScriptArgs().length == 0) {
			printerr("usage: GhidraDumpFunctionCalls <function-address>");
			return;
		}

		Address entry = toAddr(getScriptArgs()[0]);
		Function function = getFunctionAt(entry);
		if (function == null) {
			function = getFunctionContaining(entry);
		}
		if (function == null) {
			printerr("no function for " + entry);
			return;
		}

		printf("Function: %s\n", describeFunction(function));
		printf("Body min=%s max=%s\n\n", function.getBody().getMinAddress(), function.getBody().getMaxAddress());

		printf("== Direct calls ==\n");
		Instruction instruction = getInstructionAt(function.getEntryPoint());
		while (instruction != null && function.getBody().contains(instruction.getAddress())) {
			if ("CALL".equals(instruction.getMnemonicString())) {
				Address target = instruction.getFlows().length > 0 ? instruction.getFlows()[0] : null;
				Function targetFunction = target == null ? null : getFunctionAt(target);
				printf("  %s -> %s", instruction.getAddress(), target == null ? "no target" : target.toString());
				if (targetFunction != null) {
					printf(" (%s)", describeFunction(targetFunction));
				}
				printf("\n");
			}
			instruction = instruction.getNext();
		}
		printf("\n");

		printf("== Callers ==\n");
		for (Reference ref : getReferencesTo(function.getEntryPoint())) {
			if (!ref.getReferenceType().isCall()) {
				continue;
			}
			Function caller = getFunctionContaining(ref.getFromAddress());
			printf("  %s <- %s\n", ref.getFromAddress(), describeFunction(caller));
		}
	}
}
