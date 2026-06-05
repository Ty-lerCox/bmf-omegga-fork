// Dump xrefs for known CL12960 UTF-16 anchor addresses without scanning the whole program.
// @category Brickadia

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;

public class GhidraDumpAnchorXrefs extends GhidraScript {

	private static final String[][] ANCHORS = new String[][] {
		{ "StaticFindObjectFast", "0x145d372c0" },
		{ "FUObjectHashTables", "0x145d3eeae" },
		{ "HashOuter", "0x145d3ed64" }
	};

	private String describeFunction(Function function) {
		if (function == null) {
			return "no function";
		}
		return function.getName(true) + " @ " + function.getEntryPoint();
	}

	private void printAnchor(String name, String addressText) throws Exception {
		Address address = toAddr(addressText);
		printf("== Anchor: %s @ %s ==\n", name, address);
		Reference[] refs = getReferencesTo(address);
		if (refs.length == 0) {
			printf("  no references\n\n");
			return;
		}

		java.util.HashSet<String> seen = new java.util.HashSet<>();
		for (Reference ref : refs) {
			Address fromAddress = ref.getFromAddress();
			Function function = getFunctionContaining(fromAddress);
			String key = fromAddress.toString() + "|" + (function == null ? "" : function.getEntryPoint().toString());
			if (!seen.add(key)) {
				continue;
			}
			printf("  ref %s -> %s\n", fromAddress, describeFunction(function));
		}
		printf("\n");
	}

	@Override
	protected void run() throws Exception {
		printf("Program: %s\n\n", currentProgram.getName());
		for (String[] anchor : ANCHORS) {
			printAnchor(anchor[0], anchor[1]);
		}
	}
}
