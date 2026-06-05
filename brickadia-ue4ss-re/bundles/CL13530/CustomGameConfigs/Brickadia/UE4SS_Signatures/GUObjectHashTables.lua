-- Brickadia CL12960 baseline note:
-- The stock FUObjectHashTablesGet resolver currently fails on this build.
--
-- Confirmed current-build nearby anchors:
--   * GUObjectArray                 = 0x14768f038
--   * FUObjectArrayAllocate...      = 0x1404f7cb0
--   * FUObjectArrayFree...          = 0x1404f8020
--   * UTF-16 "FUObjectHashTables"   = 0x145d3eeae
--   * UTF-16 "HashOuter"            = 0x145d3ed64
--
-- Patternsleuth's direct FUObjectHashTablesGet resolver finds no candidate on
-- CL12960, so this stays unresolved until the getter is confirmed statically
-- and then checked dynamically during object lookup.
--
-- Important: returning nil here is fatal in UE4SS's Lua override loader, while
-- the underlying FUObjectHashTables::Get() result is not currently consumed by
-- the patched UE4SS runtime during startup. Keep startup alive by routing this
-- through the normal scan path with a known-absent anchor instead of returning
-- nil directly. That preserves an explicit "not found" signal without turning
-- the whole baseline into an early fatal.
function Register()
    -- UTF-16LE bytes for the longer stock stats anchor that is absent on CL12960:
    -- "Hash efficiency statistics for the Outer Object Hash"
    return "48 00 61 00 73 00 68 00 20 00 65 00 66 00 66 00 69 00 63 00 69 00 65 00 6E 00 63 00 79 00 20 00 73 00 74 00 61 00 74 00 69 00 73 00 74 00 69 00 63 00 73 00 20 00 66 00 6F 00 72 00 20 00 74 00 68 00 65 00 20 00 4F 00 75 00 74 00 65 00 72 00 20 00 4F 00 62 00 6A 00 65 00 63 00 74 00 20 00 48 00 61 00 73 00 68 00"
end

function OnMatchFound(matchAddress)
    return matchAddress
end
