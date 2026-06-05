# Dump candidate symbols/functions for the current hook-foundation targets.
# @category Brickadia

from ghidra.program.model.symbol import SymbolType


TARGET_PATTERNS = [
    "ProcessEvent",
    "LoadMap",
    "InitGameState",
    "BeginPlay",
]


def matches(name):
    lowered = name.lower()
    return any(pattern.lower() in lowered for pattern in TARGET_PATTERNS)


def format_address(address):
    if address is None:
        return "None"
    return str(address)


def collect_function_rows():
    rows = []
    fm = currentProgram.getFunctionManager()
    functions = fm.getFunctions(True)
    while functions.hasNext():
        fn = functions.next()
        name = fn.getName(True)
        if matches(name):
            rows.append(
                {
                    "kind": "function",
                    "name": name,
                    "entry": format_address(fn.getEntryPoint()),
                    "signature": str(fn.getSignature()),
                }
            )
    return rows


def collect_symbol_rows():
    rows = []
    table = currentProgram.getSymbolTable()
    for symbol in table.getAllSymbols(True):
        name = symbol.getName(True)
        if not matches(name):
            continue

        rows.append(
            {
                "kind": "symbol",
                "name": name,
                "address": format_address(symbol.getAddress()),
                "type": str(symbol.getSymbolType()),
            }
        )
    return rows


def print_rows(title, rows, fields):
    print("== {} ({}) ==".format(title, len(rows)))
    for row in sorted(rows, key=lambda item: tuple(item.get(field, "") for field in fields)):
        rendered = ", ".join("{}={}".format(field, row.get(field, "")) for field in fields)
        print(rendered)
    print("")


function_rows = collect_function_rows()
symbol_rows = collect_symbol_rows()

print("Program: {}".format(currentProgram.getName()))
print("")
print_rows("Functions", function_rows, ["name", "entry", "signature"])
print_rows("Symbols", symbol_rows, ["name", "address", "type"])
