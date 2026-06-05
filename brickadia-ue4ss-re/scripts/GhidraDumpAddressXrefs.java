// Dump xrefs for one or more explicit addresses.
// @category Brickadia

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;

public class GhidraDumpAddressXrefs extends GhidraScript {

	private String describeFunction(Function function) {
		if (function == null) {
			return "no function";
		}
		return function.getName(true) + " @ " + function.getEntryPoint();
	}

	@Override
	protected void run() throws Exception {
		if (getScriptArgs().length == 0) {
			printerr("usage: GhidraDumpAddressXrefs <address> [address...]");
			return;
		}

		for (String addressText : getScriptArgs()) {
			Address address = toAddr(addressText);
			printf("== Address: %s ==\n", address);
			Reference[] refs = getReferencesTo(address);
			if (refs.length == 0) {
				printf("  no references\n\n");
				continue;
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
	}
}
