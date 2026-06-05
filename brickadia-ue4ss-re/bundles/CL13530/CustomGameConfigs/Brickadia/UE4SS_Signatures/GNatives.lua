-- Brickadia CL12960 baseline note:
-- The stock UE4SS GNatives resolvers currently fail on this build:
--   * GNativesPatterns
--   * GNativesViaSkipFunction
--   * UObjectSkipFunction
--   * FFrameStep / FFrameStepExplicitProperty / FFrameStepViaExec
--
-- Confirmed live dispatch path on CL12960:
--   * 0x1404ded5d: LEA R15,[rip+...] -> 0x14768d760
--   * 0x1404ded70: MOV RCX,[RDI+0x18]      ; UObject* Context
--   * 0x1404ded78: MOV [RDI+0x20],RDX      ; advance FFrame::Code
--   * 0x1404ded7c: MOVZX EAX,byte ptr [RAX]
--   * 0x1404ded7f: MOV RAX,qword ptr [R15 + RAX*0x8]
--   * 0x1404ded89: CALL qword ptr [__guard_dispatch_icall]
--
-- This is the real script/native opcode table used by the patched UE4SS path.
-- The table itself lives in the zero-init tail of .data, so derive the address
-- from the LEA in the dispatch site instead of trying to read table contents
-- from the file image directly.
function Register()
    return "4C 8D 3D ?? ?? ?? ?? 4C 8D 74 24 20 0F 1F 80 00 00 00 00 48 8B 4F 18 48 8D 50 01 48 89 57 20 0F B6 00 49 8B 04 C7 48 89 FA 4D 89 F0 FF 15 ?? ?? ?? ??"
end

function OnMatchFound(matchAddress)
    local nextInstr = matchAddress + 7
    local offset = matchAddress + 3
    local dataMoved = nextInstr + DerefToInt32(offset)

    return dataMoved
end
