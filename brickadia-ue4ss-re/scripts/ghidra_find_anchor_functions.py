# Find functions that reference important UTF-16 anchor strings.
# @category Brickadia

from ghidra.program.model.symbol import RefType


ANCHORS = [
    "StaticFindObjectFast",
    "FUObjectHashTables",
    "HashOuter",
]


def find_data_addresses_for_text(text):
    listing = currentProgram.getListing()
    matches = []
    data_iter = listing.getDefinedData(True)
    while data_iter.hasNext():
        data = data_iter.next()
        value = data.getValue()
        if value is None:
            continue
        rendered = str(value)
        if text in rendered:
            matches.append(data.getAddress())
    return matches


def root_function_name(address):
    fn = getFunctionContaining(address)
    if fn is None:
        return None
    return "{} @ {}".format(fn.getName(True), fn.getEntryPoint())


def print_anchor(anchor):
    addrs = find_data_addresses_for_text(anchor)
    print("== Anchor: {} ({}) ==".format(anchor, len(addrs)))
    for addr in addrs:
        print("string @ {}".format(addr))
        refs = getReferencesTo(addr)
        seen = set()
        for ref in refs:
            from_addr = ref.getFromAddress()
            fn_name = root_function_name(from_addr)
            key = (str(from_addr), fn_name)
            if key in seen:
                continue
            seen.add(key)
            print("  ref from {} -> {}".format(from_addr, fn_name or "no function"))
    print("")


print("Program: {}".format(currentProgram.getName()))
print("")
for anchor in ANCHORS:
    print_anchor(anchor)
