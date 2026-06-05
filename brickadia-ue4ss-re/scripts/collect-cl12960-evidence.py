import argparse
import json
import re
import subprocess
from pathlib import Path

import pefile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BUNDLE = "CL12960"
BUNDLE_ROOT = ROOT / "bundles" / DEFAULT_BUNDLE
VTABLE_LAYOUT = BUNDLE_ROOT / "VTableLayout.ini"
DEFAULT_EXE = Path(
    r"C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\BrickadiaServer-Win64-Shipping.exe"
)
DEFAULT_PDB = Path(
    r"C:\Users\tycox\OneDrive\Documents\Downloads\older data from discord server\BrickadiaSteam-Win64-Shipping.pdb"
)
DEFAULT_RESOURCES_CONVOS = Path(
    r"C:\Users\tycox\OneDrive\Documents\Downloads\older data from discord server\Resources Convos.txt"
)
DEFAULT_UE4SS_LOG = Path(
    r"C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log"
)
DEFAULT_UE4SS_MODS_TXT = Path(
    r"C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\Mods\mods.txt"
)
DEFAULT_BASELINE_PROOF_OUT = ROOT / "probes" / "CL12960" / "output" / "baseline-proof.jsonl"
DEFAULT_BASELINE_UNWRAP_PROOF_OUT = ROOT / "probes" / "CL12960" / "output" / "baseline-proof-unwrap.jsonl"
DEFAULT_BASELINE_FINDFIRSTOF_PROOF_OUT = ROOT / "probes" / "CL12960" / "output" / "baseline-proof-findfirstof.jsonl"
DEFAULT_BASELINE_STATICFINDOBJECT_PROOF_OUT = ROOT / "probes" / "CL12960" / "output" / "baseline-proof-staticfindobject.jsonl"
DEFAULT_CHAT_PROOF_OUT = ROOT / "probes" / "CL12960" / "output" / "baseline-chat-proof.jsonl"
DEFAULT_COUNTER_BROADCAST_DEMO_LOG = Path(
    r"C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-counter-broadcast-demo\mod.log"
)
DEFAULT_COUNTER_BROADCAST_CHAT_TRACE = Path(
    r"C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-counter-broadcast-demo\chat-trace.log"
)
DEFAULT_COUNTER_BROADCAST_LIVE_INFO = ROOT / "notes" / "counter-broadcast-demo-live.json"
DEFAULT_GHIDRA_ANCHOR_XREFS = ROOT / "notes" / "ghidra-anchor-xrefs-latest.txt"
DEFAULT_GHIDRA_ADDRESS_XREFS = ROOT / "notes" / "ghidra-address-xrefs-latest.txt"
DEFAULT_GHIDRA_HASHOUTER_DECOMPILE = ROOT / "notes" / "ghidra-decompile-latest.txt"
DEFAULT_GHIDRA_HASHOUTER_DECOMPILE_FALLBACKS = [
    ROOT / "notes" / "ghidra-decompile-14053c060.txt",
    ROOT / "notes" / "ghidra-decompile-14053c2d0.txt",
    ROOT / "notes" / "ghidra-decompile-14053a860.txt",
]
DEFAULT_UNREAL_INITIALIZER_CPP = Path(
    r"C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS\deps\first\Unreal\src\UnrealInitializer.cpp"
)
DEFAULT_UNREAL_SIGNATURES_CPP = Path(
    r"C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS\deps\first\Unreal\src\Signatures.cpp"
)
DEFAULT_UNREAL_SOURCE_ROOT = Path(
    r"C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS\deps\first\Unreal"
)
DEFAULT_UNREAL_FFRAME_CPP = Path(
    r"C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS\deps\first\Unreal\src\FFrame.cpp"
)
GENERATED_VTABLE_ROOT = Path(
    r"C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS\deps\first\Unreal\generated_include\FunctionBodies"
)
UE_BASELINE_SUFFIX = "5_05"
PATTERNSLEUTH = Path(
    r"C:\Users\tycox\Tools\reverse-engineering\patternsleuth\target\release\patternsleuth.exe"
)
LLVM_PDBUTIL = Path(
    r"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\Llvm\x64\bin\llvm-pdbutil.exe"
)

HOOK_TARGETS = [
    ("UObject", "ProcessEvent", "ProcessEvent address"),
    ("UEngine", "LoadMap", "GameEngine::LoadMap address"),
    ("AGameModeBase", "InitGameState", "GameModeBase::InitGameState address"),
    ("AActor", "BeginPlay", "AActor::BeginPlay address"),
]

SUCCESS_RESOLVERS = [
    "FNameCtorWchar",
    "FNameToString",
    "StaticConstructObjectInternal",
    "ConsoleManagerSingleton",
    "UGameEngineTick",
    "GUObjectArray",
    "FUObjectArrayAllocateUObjectIndex",
    "FUObjectArrayFreeUObjectIndex",
]

BLOCKED_RESOLVERS = [
    "FUObjectHashTablesGet",
    "StaticFindObjectFast",
    "GNatives",
    "UObjectSkipFunction",
    "GNativesViaSkipFunction",
    "GNativesPatterns",
    "FFrameStep",
    "FFrameStepExplicitProperty",
    "FFrameStepViaExec",
]

UTF16_ANCHORS = [
    "StaticFindObjectFast",
    "FUObjectHashTables",
    "HashOuter",
]

OLD_PDB_QUERIES = [
    "StaticFindObjectFastSafe",
    "StaticFindObjectChecked",
    "StaticFindObjectSafe",
    "FUObjectHashTables::~FUObjectHashTables",
    "UObject::ProcessConsoleExec",
]


def run(cmd):
    return subprocess.run(
        cmd,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def read_text_flexible(path: Path):
    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "utf-16", "utf-16-le", "utf-16-be", "utf-8"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def file_offset_to_va(pe, file_offset):
    for section in pe.sections:
        start = section.PointerToRawData
        end = start + section.SizeOfRawData
        if start <= file_offset < end:
            rva = section.VirtualAddress + (file_offset - start)
            return {
                "section": section.Name.rstrip(b"\0").decode("ascii", "ignore"),
                "file_offset": hex(file_offset),
                "rva": hex(rva),
                "va": hex(pe.OPTIONAL_HEADER.ImageBase + rva),
            }
    return None


def file_offset_to_va_int(pe, file_offset):
    match = file_offset_to_va(pe, file_offset)
    if not match:
        return None
    return int(match["va"], 16)


def get_section(pe, name):
    wanted = name.encode("ascii")
    for section in pe.sections:
        if section.Name.rstrip(b"\0") == wanted:
            return section
    return None


def section_va_range(pe, section):
    start = pe.OPTIONAL_HEADER.ImageBase + section.VirtualAddress
    size = max(section.SizeOfRawData, section.Misc_VirtualSize)
    return start, start + size


def function_range_for_va(pe, va):
    try:
        pe.parse_data_directories(
            directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_EXCEPTION"]]
        )
    except Exception:
        return None

    rva = va - pe.OPTIONAL_HEADER.ImageBase
    for entry in getattr(pe, "DIRECTORY_ENTRY_EXCEPTION", []):
        begin = entry.struct.BeginAddress
        end = entry.struct.EndAddress
        if begin <= rva < end:
            base = pe.OPTIONAL_HEADER.ImageBase
            return base + begin, base + end
    return None


def probable_rip_instruction_start(buf, disp_off):
    starts = []
    if disp_off >= 3:
        starts.append((disp_off - 3, 3))
    if disp_off >= 2:
        starts.append((disp_off - 2, 2))

    rip_opcodes = {0x03, 0x39, 0x3B, 0x80, 0x83, 0x89, 0x8B, 0x8D, 0xFF}
    for start, prefix_len in starts:
        if start < 0 or start + prefix_len > len(buf):
            continue
        if prefix_len == 3:
            rex = buf[start]
            opcode = buf[start + 1]
            modrm = buf[start + 2]
            if 0x40 <= rex <= 0x4F and opcode in rip_opcodes and (modrm & 0xC7) == 0x05:
                return start
        else:
            opcode = buf[start]
            modrm = buf[start + 1]
            if opcode in rip_opcodes and (modrm & 0xC7) == 0x05:
                return start
    return None


def find_rip_refs_to_va(buf, base_va, target_va):
    refs = []
    for disp_off in range(0, max(0, len(buf) - 4)):
        start = probable_rip_instruction_start(buf, disp_off)
        if start is None:
            continue
        disp = int.from_bytes(buf[disp_off : disp_off + 4], "little", signed=True)
        computed = base_va + disp_off + 4 + disp
        if computed == target_va:
            refs.append(base_va + start)
    return refs


def find_rex_rip_refs_to_va(buf, base_va, target_va):
    refs = []
    rip_opcodes = (0x03, 0x39, 0x3B, 0x80, 0x83, 0x89, 0x8B, 0x8D, 0xFF)
    for rex in range(0x40, 0x50):
        for opcode in rip_opcodes:
            needle = bytes((rex, opcode))
            start = buf.find(needle)
            while start != -1:
                if start + 7 <= len(buf):
                    modrm = buf[start + 2]
                    if (modrm & 0xC7) == 0x05:
                        disp_off = start + 3
                        disp = int.from_bytes(
                            buf[disp_off : disp_off + 4],
                            "little",
                            signed=True,
                        )
                        computed = base_va + disp_off + 4 + disp
                        if computed == target_va:
                            refs.append(base_va + start)
                start = buf.find(needle, start + 1)
    return sorted(set(refs))


def collect_rip_data_targets(buf, base_va, data_start, data_end):
    targets = []
    for disp_off in range(0, max(0, len(buf) - 4)):
        if probable_rip_instruction_start(buf, disp_off) is None:
            continue
        disp = int.from_bytes(buf[disp_off : disp_off + 4], "little", signed=True)
        target = base_va + disp_off + 4 + disp
        if data_start <= target < data_end:
            targets.append(target)
    return targets


def cluster_targets(targets, max_gap=0x400):
    clusters = []
    for target in sorted(set(targets)):
        if not clusters or target - clusters[-1][-1] > max_gap:
            clusters.append([target])
        else:
            clusters[-1].append(target)
    return clusters


def choose_hash_table_root(cluster):
    target_set = set(cluster)
    structured = [
        target
        for target in target_set
        if target + 0x28 in target_set and target + 0x30 in target_set
    ]
    if structured:
        return min(structured)
    return min(cluster) if cluster else None


def collect_hash_table_binary_findings(exe: Path):
    findings = {}
    if not exe.exists():
        return findings

    pe = pefile.PE(str(exe), fast_load=False)
    raw = exe.read_bytes()
    text_section = get_section(pe, ".text")
    data_section = get_section(pe, ".data")
    if text_section is None or data_section is None:
        return findings

    hash_outer_off = raw.find("HashOuter".encode("utf-16le"))
    hash_outer_va = file_offset_to_va_int(pe, hash_outer_off) if hash_outer_off != -1 else None
    if hash_outer_va is None:
        return findings

    text_va, _ = section_va_range(pe, text_section)
    data_start, data_end = section_va_range(pe, data_section)
    text = raw[
        text_section.PointerToRawData : text_section.PointerToRawData
        + text_section.SizeOfRawData
    ]
    hash_outer_refs = find_rex_rip_refs_to_va(text, text_va, hash_outer_va)
    if not hash_outer_refs:
        return findings

    anchor_ref = hash_outer_refs[0]
    function_range = function_range_for_va(pe, anchor_ref)
    if not function_range:
        return findings

    function_start, function_end = function_range
    function_raw_start = text_section.PointerToRawData + (function_start - text_va)
    function_raw_end = text_section.PointerToRawData + (function_end - text_va)
    function_bytes = raw[function_raw_start:function_raw_end]
    data_targets = collect_rip_data_targets(
        function_bytes,
        function_start,
        data_start,
        data_end,
    )
    clusters = cluster_targets(data_targets)
    best_cluster = max(clusters, key=len) if clusters else []
    root_global = choose_hash_table_root(best_cluster)
    companion_cluster = [
        target
        for target in sorted(best_cluster)
        if root_global and root_global <= target <= root_global + 0x300
    ]
    singleton_ref_count = data_targets.count(root_global) if root_global else 0

    findings.update(
        {
            "hash_tables_anchor_function": (
                f"0x{function_start:x}..0x{function_end:x} "
                f"(HashOuter xref 0x{anchor_ref:x})"
            ),
            "hash_tables_root_global": f"0x{root_global:x}" if root_global else None,
            "hash_tables_singleton_ref_count": singleton_ref_count,
            "hash_tables_direct_global_access": bool(
                root_global
                and root_global + 0x28 in best_cluster
                and root_global + 0x30 in best_cluster
            ),
            "hash_tables_companion_globals": [
                f"0x{target:x}" for target in companion_cluster[:16]
            ],
        }
    )
    return findings


def scan_utf16_anchors(exe):
    pe = pefile.PE(str(exe), fast_load=False)
    data = exe.read_bytes()
    anchors = []
    for text in UTF16_ANCHORS:
        encoded = text.encode("utf-16le")
        idx = data.find(encoded)
        anchors.append(
            {
                "text": text,
                "match": file_offset_to_va(pe, idx) if idx != -1 else None,
            }
        )
    return anchors


def scan_patternsleuth(exe, resolvers):
    cmd = [str(PATTERNSLEUTH), "scan", "--path", str(exe)]
    for resolver in resolvers:
        cmd.extend(["--resolver", resolver])
    cmd.append("--summary")
    result = run(cmd)
    return {
        "command": cmd,
        "exit_code": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }


def parse_resolver_addresses(stdout):
    matches = re.findall(r"\b([A-Za-z0-9_]+)\(([0-9a-fA-F]+)\)", stdout)
    return {name: f"0x{value.lower()}" for name, value in matches}


def parse_vtable_sections(vtable_layout):
    sections = {}
    current = None
    for raw_line in vtable_layout.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith(";"):
            continue
        match = re.match(r"^\[(.+)\]$", line)
        if match:
            current = match.group(1)
            sections[current] = []
            continue
        if current:
            sections[current].append(line)
    return sections


def extract_generated_offset(class_name, function_name):
    generated_file = GENERATED_VTABLE_ROOT / f"{UE_BASELINE_SUFFIX}_VTableOffsets_{class_name}_FunctionBody.cpp"
    if not generated_file.exists():
        return None

    text = generated_file.read_text(encoding="utf-8", errors="replace")
    match = re.search(
        rf'{re.escape(class_name)}::VTableLayoutMap\.emplace\(STR\("{re.escape(function_name)}"\), (0x[0-9A-Fa-f]+)\);',
        text,
    )
    if not match:
        return None
    return {
        "generated_file": str(generated_file),
        "offset": match.group(1).lower(),
    }


def extract_seed_vtable_variance_note(resources_convos: Path):
    if not resources_convos.exists():
        return None

    lines = resources_convos.read_text(encoding="utf-8", errors="replace").splitlines()
    phrase = "Brickadia only has one extra vfunc in UObject and two in UEngine"
    for index, line in enumerate(lines, start=1):
        if phrase in line:
            return {
                "path": str(resources_convos),
                "line": index,
                "text": line.strip(),
                "supports_stock_defaults_outside_uobject_uengine": True,
            }
    return None


def collect_hook_foundation(vtable_layout, ue4ss_log, resources_convos):
    sections = parse_vtable_sections(vtable_layout)
    log_text = ue4ss_log.read_text(encoding="utf-8", errors="replace") if ue4ss_log.exists() else ""
    seed_vtable_note = extract_seed_vtable_variance_note(resources_convos)
    fatal_line = None
    callback_gc_invalid_line = None
    for line in log_text.splitlines():
        if "Fatal Error:" in line:
            fatal_line = line.strip()
            break
    for line in log_text.splitlines():
        if "[FCallbackGarbageCollector] Freed invalid callbacks!" in line:
            callback_gc_invalid_line = line.strip()
            break

    targets = {}
    for class_name, function_name, runtime_marker in HOOK_TARGETS:
        explicit_ordinal = None
        if class_name in sections and function_name in sections[class_name]:
            explicit_ordinal = sections[class_name].index(function_name)
        generated_default = extract_generated_offset(class_name, function_name)
        seed_supported_default = (
            seed_vtable_note is not None
            and seed_vtable_note.get("supports_stock_defaults_outside_uobject_uengine", False)
            and class_name not in ("UObject", "UEngine")
            and explicit_ordinal is None
            and generated_default is not None
        )

        runtime_address = None
        runtime_line = None
        for line in log_text.splitlines():
            if runtime_marker in line:
                runtime_line = line.strip()
                address_match = re.search(r"(0x[0-9A-Fa-f]+)", line)
                runtime_address = address_match.group(1).lower() if address_match else None
                break

        targets[f"{class_name}::{function_name}"] = {
            "class": class_name,
            "function": function_name,
            "custom_layout_section_present": class_name in sections,
            "custom_layout_explicit_override": explicit_ordinal is not None,
            "custom_layout_ordinal": explicit_ordinal,
            "generated_ue5_5_default": generated_default,
            "seed_note_supports_stock_default": seed_supported_default,
            "runtime_log_address": runtime_address,
            "runtime_log_line": runtime_line,
            "status": (
                "runtime_confirmed"
                if runtime_address
                else "custom_override_only"
                if explicit_ordinal is not None
                else "seed_supported_default"
                if seed_supported_default
                else "stock_default_only"
            ),
        }

    return {
        "ue_baseline_suffix": UE_BASELINE_SUFFIX,
        "custom_vtable_layout": str(vtable_layout),
        "seed_vtable_variance_note": seed_vtable_note,
        "runtime_log": str(ue4ss_log),
        "startup_fatal_line": fatal_line,
        "callback_gc_invalid_line": callback_gc_invalid_line,
        "targets": targets,
    }


def collect_lua_scan_addresses(ue4ss_log: Path):
    addresses = {}
    if not ue4ss_log.exists():
        return addresses

    name_map = {
        "FName::ToString": "FNameToString",
        "GNatives": "GNatives",
        "GUObjectArray": "GUObjectArray",
    }

    text = ue4ss_log.read_text(encoding="utf-8", errors="replace")
    for raw_line in text.splitlines():
        line = raw_line.strip()
        match = re.search(
            r"\]\s*(.+?) address:\s*(0x[0-9A-Fa-f]+)\s*<-\s*Lua Script",
            line,
        )
        if not match:
            continue
        source_name = match.group(1).strip()
        resolver_name = name_map.get(source_name)
        if not resolver_name:
            continue
        addresses[resolver_name] = {
            "address": match.group(2).lower(),
            "line": line,
            "source": "Lua Script",
        }

    return addresses


def collect_runtime_mods(mods_txt: Path):
    enabled = []
    if mods_txt.exists():
        for raw_line in mods_txt.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw_line.strip()
            if not line or line.startswith(";") or ":" not in line:
                continue
            name, enabled_flag = [part.strip() for part in line.split(":", 1)]
            if enabled_flag == "1":
                enabled.append(name)

    return {
        "mods_txt": str(mods_txt),
        "enabled": enabled,
    }


def collect_jsonl_output(proof_out: Path):
    payload = {
        "path": str(proof_out),
        "exists": proof_out.exists(),
        "entries": [],
        "parse_errors": [],
    }

    if not proof_out.exists():
        return payload

    for line_number, raw_line in enumerate(
        proof_out.read_text(encoding="utf-8", errors="replace").splitlines(),
        start=1,
    ):
        line = raw_line.strip()
        if not line:
            continue

        try:
            payload["entries"].append(json.loads(line))
        except json.JSONDecodeError as exc:
            payload["parse_errors"].append(
                {
                    "line": line_number,
                    "error": str(exc),
                    "raw": line,
                }
            )

    return payload


def collect_counter_broadcast_demo(mod_log: Path, chat_trace: Path, live_info: Path):
    payload = {
        "mod_log": {
            "path": str(mod_log),
            "exists": mod_log.exists(),
            "submitted_requests": [],
            "accepted_requests": [],
        },
        "chat_trace": {
            "path": str(chat_trace),
            "exists": chat_trace.exists(),
            "typed_successes": [],
        },
        "live_info": {
            "path": str(live_info),
            "exists": live_info.exists(),
            "payload": None,
            "parse_error": None,
        },
    }

    if mod_log.exists():
        for raw_line in mod_log.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw_line.strip()
            if not line:
                continue

            submitted_match = re.search(
                r"submitted bridge chat\.broadcast request id=(\d+) message=(.+)$",
                line,
            )
            if submitted_match:
                payload["mod_log"]["submitted_requests"].append(
                    {
                        "request_id": int(submitted_match.group(1)),
                        "message": submitted_match.group(2).strip(),
                        "line": line,
                    }
                )
                continue

            accepted_match = re.search(
                r"broadcast #(\d+) accepted by bridge method=([^\s]+) detail=(.+)$",
                line,
            )
            if accepted_match:
                payload["mod_log"]["accepted_requests"].append(
                    {
                        "sequence": int(accepted_match.group(1)),
                        "method": accepted_match.group(2).strip(),
                        "detail": accepted_match.group(3).strip(),
                        "line": line,
                    }
                )

    if chat_trace.exists():
        for raw_line in chat_trace.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw_line.strip()
            if not line:
                continue

            success_match = re.search(
                r"fast call-by-name succeeded\s+(.+?)\s+->\s+([A-Za-z0-9_]+)\s+\"(.*)\"\s+executor=\s*(.+)$",
                line,
            )
            if success_match:
                payload["chat_trace"]["typed_successes"].append(
                    {
                        "source": success_match.group(1).strip(),
                        "function_name": success_match.group(2).strip(),
                        "message": success_match.group(3),
                        "executor": success_match.group(4).strip(),
                        "line": line,
                    }
                )

    if live_info.exists():
        try:
            payload["live_info"]["payload"] = json.loads(
                read_text_flexible(live_info)
            )
        except json.JSONDecodeError as exc:
            payload["live_info"]["parse_error"] = str(exc)

    return payload


def collect_manual_re_findings(exe: Path):
    findings = {
        "hash_tables_anchor_function": None,
        "hash_tables_root_global": None,
        "hash_tables_singleton_ref_count": 0,
        "hash_tables_direct_global_access": False,
        "hash_tables_companion_globals": [],
        "sources": {
            "binary": str(exe),
            "anchor_xrefs": str(DEFAULT_GHIDRA_ANCHOR_XREFS),
            "address_xrefs": str(DEFAULT_GHIDRA_ADDRESS_XREFS),
            "hashouter_decompile": str(DEFAULT_GHIDRA_HASHOUTER_DECOMPILE),
        },
    }

    binary_findings = collect_hash_table_binary_findings(exe)
    for key, value in binary_findings.items():
        findings[key] = value

    if findings["hash_tables_anchor_function"]:
        return findings

    if DEFAULT_GHIDRA_ANCHOR_XREFS.exists():
        text = read_text_flexible(DEFAULT_GHIDRA_ANCHOR_XREFS)
        match = re.search(
            r"Anchor:\s+HashOuter\s+@.*?ref\s+[0-9a-fA-F]+\s+->\s+([^\r\n]+)",
            text,
            re.S,
        )
        if match:
            findings["hash_tables_anchor_function"] = match.group(1).strip()

    if DEFAULT_GHIDRA_ADDRESS_XREFS.exists():
        text = read_text_flexible(DEFAULT_GHIDRA_ADDRESS_XREFS)
        match = re.search(
            r"Address:\s+14768f1f8\s+==(?P<body>.*?)(?:Address:\s+[0-9a-fA-F]+\s+==|\Z)",
            text,
            re.S,
        )
        if match:
            ref_count = len(
                re.findall(r"\bref\s+[0-9a-fA-F]+\s+->", match.group("body"))
            )
            findings["hash_tables_root_global"] = "0x14768f1f8"
            findings["hash_tables_singleton_ref_count"] = ref_count

    decompile_candidates = [DEFAULT_GHIDRA_HASHOUTER_DECOMPILE, *DEFAULT_GHIDRA_HASHOUTER_DECOMPILE_FALLBACKS]
    for decompile_path in decompile_candidates:
        if not decompile_path.exists():
            continue
        text = read_text_flexible(decompile_path)
        has_root = "DAT_14768f1f8" in text
        has_companion = any(
            marker in text
            for marker in (
                "DAT_14768f220",
                "DAT_14768f228",
                "DAT_14768f410",
                "DAT_14768f418",
                "DAT_14768f420",
                "DAT_14768f430",
                "DAT_14768f448",
            )
        )
        if has_root and has_companion:
            findings["hash_tables_direct_global_access"] = True
            findings["sources"]["hashouter_decompile"] = str(decompile_path)
            break

    return findings


def collect_patched_runtime_findings():
    findings = {
        "fuobject_hash_tables_get_scan_config_present": False,
        "fuobject_hash_tables_get_result_field_present": False,
        "fuobject_hash_tables_get_runtime_assignment_present": False,
        "fuobject_hash_tables_get_override_hook_present": False,
        "gnatives_runtime_assignment_present": False,
        "static_find_object_fast_runtime_reference_present": False,
        "uobject_skip_function_runtime_reference_present": False,
        "fframe_step_runtime_source_impl_present": False,
        "fframe_step_runtime_binary_reference_present": False,
        "sources": {
            "unreal_initializer_cpp": str(DEFAULT_UNREAL_INITIALIZER_CPP),
            "signatures_cpp": str(DEFAULT_UNREAL_SIGNATURES_CPP),
            "unreal_source_root": str(DEFAULT_UNREAL_SOURCE_ROOT),
            "fframe_cpp": str(DEFAULT_UNREAL_FFRAME_CPP),
        },
    }

    if DEFAULT_UNREAL_INITIALIZER_CPP.exists():
        text = DEFAULT_UNREAL_INITIALIZER_CPP.read_text(encoding="utf-8", errors="replace")
        findings["fuobject_hash_tables_get_scan_config_present"] = (
            "config.fuobject_hash_tables_get" in text
        )
        findings["fuobject_hash_tables_get_result_field_present"] = (
            "void* fuobject_hash_tables_get{};" in text
        )
        findings["fuobject_hash_tables_get_runtime_assignment_present"] = bool(
            re.search(r"results\.fuobject_hash_tables_get\b", text)
        )
        findings["gnatives_runtime_assignment_present"] = (
            "GNatives_Internal = reinterpret_cast<FNativeFuncPtr*>(results.gnatives);" in text
        )

    if DEFAULT_UNREAL_SIGNATURES_CPP.exists():
        text = DEFAULT_UNREAL_SIGNATURES_CPP.read_text(encoding="utf-8", errors="replace")
        findings["fuobject_hash_tables_get_override_hook_present"] = (
            "config.ScanOverrides.fuobject_hash_tables_get" in text
        )

    if DEFAULT_UNREAL_FFRAME_CPP.exists():
        text = DEFAULT_UNREAL_FFRAME_CPP.read_text(encoding="utf-8", errors="replace")
        findings["fframe_step_runtime_source_impl_present"] = (
            "void FFrame::Step(UObject* Context, void* RESULT_DECL)" in text
        )
        findings["fframe_step_runtime_binary_reference_present"] = (
            "FFrameStep" in text or "StepViaExec" in text or "StepExplicitProperty" in text
        )

    if DEFAULT_UNREAL_SOURCE_ROOT.exists():
        source_texts = []
        for path in DEFAULT_UNREAL_SOURCE_ROOT.rglob("*"):
            if path.suffix.lower() not in {".cpp", ".hpp", ".h", ".cc", ".cxx"}:
                continue
            try:
                source_texts.append(path.read_text(encoding="utf-8", errors="replace"))
            except OSError:
                continue
        combined = "\n".join(source_texts)
        findings["static_find_object_fast_runtime_reference_present"] = (
            "StaticFindObjectFast" in combined
        )
        findings["uobject_skip_function_runtime_reference_present"] = (
            "UObjectSkipFunction" in combined or "SkipFunction(" in combined
        )

    return findings


def query_old_pdb(pdb):
    cmd = [str(LLVM_PDBUTIL), "dump", "--publics", "--public-extras", str(pdb)]
    result = run(cmd)
    records = []
    if result.returncode != 0:
      return {"command": cmd, "exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr, "records": records}

    for line in result.stdout.splitlines():
        for query in OLD_PDB_QUERIES:
            if query in line:
                records.append(line.strip())
    return {
        "command": cmd,
        "exit_code": result.returncode,
        "stdout": "",
        "stderr": result.stderr,
        "records": records,
    }


def parse_args():
    parser = argparse.ArgumentParser(
        description="Collect baseline evidence for a Brickadia UE4SS compatibility bundle."
    )
    parser.add_argument("exe", nargs="?", default=str(DEFAULT_EXE))
    parser.add_argument("pdb", nargs="?", default=str(DEFAULT_PDB))
    parser.add_argument("--bundle", default=DEFAULT_BUNDLE)
    parser.add_argument("--proof-root")
    return parser.parse_args()


def main():
    args = parse_args()
    exe = Path(args.exe)
    pdb = Path(args.pdb)
    bundle = args.bundle
    bundle_root = ROOT / "bundles" / bundle
    vtable_layout = bundle_root / "VTableLayout.ini"
    proof_root = Path(args.proof_root) if args.proof_root else ROOT / "probes" / bundle / "output"
    baseline_proof_out = proof_root / "baseline-proof.jsonl"
    baseline_unwrap_proof_out = proof_root / "baseline-proof-unwrap.jsonl"
    baseline_findfirstof_proof_out = proof_root / "baseline-proof-findfirstof.jsonl"
    baseline_staticfindobject_proof_out = proof_root / "baseline-proof-staticfindobject.jsonl"
    chat_proof_out = proof_root / "baseline-chat-proof.jsonl"

    payload = {
        "bundle_id": bundle,
        "target": {
            "exe": str(exe),
            "pdb_seed": str(pdb),
        },
        "patternsleuth_success": scan_patternsleuth(exe, SUCCESS_RESOLVERS),
        "patternsleuth_blocked": scan_patternsleuth(exe, BLOCKED_RESOLVERS),
        "utf16_anchors": scan_utf16_anchors(exe),
        "old_pdb_publics": query_old_pdb(pdb) if pdb.exists() else None,
        "hook_foundation": collect_hook_foundation(vtable_layout, DEFAULT_UE4SS_LOG, DEFAULT_RESOURCES_CONVOS),
        "lua_scan_addresses": collect_lua_scan_addresses(DEFAULT_UE4SS_LOG),
        "runtime_mods": collect_runtime_mods(DEFAULT_UE4SS_MODS_TXT),
        "baseline_object_proof": collect_jsonl_output(baseline_proof_out),
        "baseline_object_unwrap_proof": collect_jsonl_output(baseline_unwrap_proof_out),
        "baseline_findfirstof_proof": collect_jsonl_output(baseline_findfirstof_proof_out),
        "baseline_staticfindobject_proof": collect_jsonl_output(baseline_staticfindobject_proof_out),
        "chat_proof": collect_jsonl_output(chat_proof_out),
        "counter_broadcast_demo": collect_counter_broadcast_demo(
            DEFAULT_COUNTER_BROADCAST_DEMO_LOG,
            DEFAULT_COUNTER_BROADCAST_CHAT_TRACE,
            DEFAULT_COUNTER_BROADCAST_LIVE_INFO,
        ),
        "manual_re_findings": collect_manual_re_findings(exe),
        "patched_runtime_findings": collect_patched_runtime_findings(),
    }
    payload["resolved_addresses"] = parse_resolver_addresses(
        payload["patternsleuth_success"]["stdout"]
    )
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
