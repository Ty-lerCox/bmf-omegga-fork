// Decompile a function at the provided address.
// @category Brickadia

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class GhidraDecompileFunction extends GhidraScript {

	@Override
	protected void run() throws Exception {
		if (getScriptArgs().length == 0) {
			printerr("usage: GhidraDecompileFunction <function-address>");
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

		DecompInterface decompiler = new DecompInterface();
		decompiler.openProgram(currentProgram);
		DecompileResults results = decompiler.decompileFunction(function, 120, monitor);
		if (!results.decompileCompleted()) {
			printerr("decompile failed: " + results.getErrorMessage());
			return;
		}

		printf("Function: %s @ %s\n\n", function.getName(true), function.getEntryPoint());
		printf("%s\n", results.getDecompiledFunction().getC());
	}
}
