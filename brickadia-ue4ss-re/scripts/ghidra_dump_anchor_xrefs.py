# Dump xrefs for known CL12960 UTF-16 anchor addresses without scanning the whole program.
# @category Brickadia

ANCHORS = [
    ("StaticFindObjectFast", "0x145d372c0"),
    ("FUObjectHashTables", "0x145d3eeae"),
    ("HashOuter", "0x145d3ed64"),
]


def root_function(address):
    fn = getFunctionContaining(address)
    if fn is None:
        return None
    return fn


def describe_function(fn):
    if fn is None:
        return "no function"
    return "{} @ {}".format(fn.getName(True), fn.getEntryPoint())


def print_anchor(name, address_text):
    addr = toAddr(address_text)
    print("== Anchor: {} @ {} ==".format(name, addr))
    refs = getReferencesTo(addr)
    seen = set()
    count = 0
    for ref in refs:
        from_addr = ref.getFromAddress()
        fn = root_function(from_addr)
        key = (str(from_addr), fn.getEntryPoint().toString() if fn else None)
        if key in seen:
            continue
        seen.add(key)
        count += 1
        print("  ref {} -> {}".format(from_addr, describe_function(fn)))
    if count == 0:
        print("  no references")
    print("")


print("Program: {}".format(currentProgram.getName()))
print("")
for name, address_text in ANCHORS:
    print_anchor(name, address_text)
