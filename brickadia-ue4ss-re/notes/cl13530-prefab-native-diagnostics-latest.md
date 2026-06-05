# CL13530 Prefab Native Diagnostics

Generated: `2026-05-31T21:04:28.106Z`
Bridge: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799`
Players: `0`

## Hook State

- registered_kind ClientNotifyPrefabCaptureComplete=/Script/Brickadia.BRPlayerController:ClientNotifyPrefabCaptureComplete
- registered_kind ClientNotifyPrefabCaptureFailed=/Script/Brickadia.BRPlayerController:ClientNotifyPrefabCaptureFailed
- registered_kind ClientUploadPrefab=/Script/Brickadia.BRPlayerController:ClientUploadPrefab
- registered_kind HandleAttachedPlacement=/Script/Brickadia.BRTool_Placer:HandleAttachedPlacement
- registered_kind ServerModifyEntity=/Script/Brickadia.BRPlayerController:ServerModifyEntity
- registered_kind ServerPasteBrick=/Script/Brickadia.BRPlayerController:ServerPasteBrick
- registered_kind ServerPasteEntity=/Script/Brickadia.BRPlayerController:ServerPasteEntity
- registered_kind ServerPastePrefab=/Script/Brickadia.BRPlayerController:ServerPastePrefab
- registered_kind ServerPlaceCurrentPrefab=/Script/Brickadia.BRTool_Placer:ServerPlaceCurrentPrefab
- registered_kind ServerPlaceSimpleEntityVolume=/Script/Brickadia.BRTool_Placer:ServerPlaceSimpleEntityVolume
- registered_kind ServerUploadPrefab=/Script/Brickadia.BRPlayerController:ServerUploadPrefab
- registered_kind SetPlaceAsPhysicsAvailable=/Script/Brickadia.BRTool_Placer:SetPlaceAsPhysicsAvailable
- registered_kind SetPlaceAsPhysicsEnabled=/Script/Brickadia.BRTool_Placer:SetPlaceAsPhysicsEnabled
- capture_events=0
- last_capture=<none>

## ServerPastePrefab Replay Contract

Status: `matches-live-reflection`
Parameter buffer size: `0x40`

| Index | Name | Type | Offset | Size |
| --- | --- | --- | --- | --- |
| 1 | Hash | BRPrefabHash | `0x0` | `0x20` |
| 2 | bWithOwnership | bool | `0x20` | `0x1` |
| 3 | bInTemp | bool | `0x21` | `0x1` |
| 4 | PasteInfo | BRPrefabDetachedPasteInfo | `0x28` | `0x18` |
|  | PasteInfo.TargetObject | UObject* | `0x0` | `0x8` |
|  | PasteInfo.GridOffset | FIntVector | `0x8` | `0xC` |
|  | PasteInfo.PlacementOrientation | uint8/enum | `0x14` | `0x1` |

## Live Reflection: ServerPastePrefab

```text
Describe function object: ServerPastePrefab
hits=1
hit[1] addr=0x7DF46D78D750 full=UFunctionName#67096 outer=OuterName#343082 flags=0x240CC1 [Native|Net|NetServer|Reliable|Event] num_parms=4 parms_size=0x40 return_offset=0xFFFF
  param[1] FName#944454:StructProperty<UStruct@0x7DF46D7727B0> offset=0x0 size=0x20 flags=0x18001008000082 [Parm|Const|Ref|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D7727B0 size=0x20
    fields=0
  param[2] FName#949313:BoolProperty offset=0x20 size=0x1 flags=0x18001040000280 [Parm|Zero|POD|NoDtor] class_cast=0x28001
  param[3] FName#949308:BoolProperty offset=0x21 size=0x1 flags=0x18001040000280 [Parm|Zero|POD|NoDtor] class_cast=0x28001
  param[4] FName#949302:StructProperty<UStruct@0x7DF46D772320> offset=0x28 size=0x18 flags=0x10001008000082 [Parm|Const|Ref|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D772320 size=0x18
    field[1] FName#944188:ObjectPropertyBase<UStruct@0x7DF46D6A3000> offset=0x0 size=0x8 flags=0x11C001000000205 [Zero|NoDtor] class_cast=0x4018001
    field[2] FName#944182:StructProperty<UStruct@0x7DF46D705EC8> offset=0x8 size=0xC flags=0x18001040000205 [Zero|POD|NoDtor] class_cast=0x108001
      struct UStruct@0x7DF46D705EC8 size=0xC
      field[1] FName#4959:IntProperty offset=0x0 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
      field[2] FName#4961:IntProperty offset=0x4 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
      field[3] FName#4963:IntProperty offset=0x8 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[3] FName#944053:FieldClassCastFlags=0x1000000008001 offset=0x14 size=0x1 flags=0x18001040000205 [Zero|POD|NoDtor] class_cast=0x1000000008001
```

## Prefab Upload RPC Contracts

ServerUploadPrefab: `matches-live-reflection`, parameter buffer size `0x20`.
ClientUploadPrefab: `matches-live-reflection`, parameter buffer size `0x21`.

| Function | Index | Name | Type | Offset | Size |
| --- | --- | --- | --- | --- | --- |
| ServerUploadPrefab | 1 | Hash | BRPrefabHash | `0x0` | `0x20` |
| ClientUploadPrefab | 1 | Hash | BRPrefabHash | `0x0` | `0x20` |
| ClientUploadPrefab | 2 | bAllowUpload | bool | `0x20` | `0x1` |

These RPCs are hash/cache driven. `ServerUploadPrefab` does not expose a raw archive-byte payload parameter.

### Live Reflection: ServerUploadPrefab

```text
Describe function object: ServerUploadPrefab
hits=1
hit[1] addr=0x7DF46D9CDB80 full=UFunctionName#60008 outer=OuterName#620996 flags=0x240CC1 [Native|Net|NetServer|Reliable|Event] num_parms=1 parms_size=0x20 return_offset=0xFFFF
  param[1] FName#1174531:StructProperty<UStruct@0x7DF46D7727B0> offset=0x0 size=0x20 flags=0x18001008000082 [Parm|Const|Ref|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D7727B0 size=0x20
    fields=0
```

### Live Reflection: ClientUploadPrefab

```text
Describe function object: ClientUploadPrefab
hits=1
hit[1] addr=0x7DF46D9CD720 full=UFunctionName#59942 outer=OuterName#620996 flags=0x1040CC1 [Native|Net|NetClient|Reliable|Event] num_parms=2 parms_size=0x21 return_offset=0xFFFF
  param[1] FName#1174531:StructProperty<UStruct@0x7DF46D7727B0> offset=0x0 size=0x20 flags=0x18001008000082 [Parm|Const|Ref|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D7727B0 size=0x20
    fields=0
  param[2] FName#1174537:BoolProperty offset=0x20 size=0x1 flags=0x18001040000280 [Parm|Zero|POD|NoDtor] class_cast=0x28001
```

## Live Reflection: ServerPlaceCurrentPrefab

```text
Describe function object: ServerPlaceCurrentPrefab
hits=1
hit[1] addr=0x7DF46DA11B20 full=UFunctionName#69636 outer=OuterName#382591 flags=0xA20CC0 [Native|Net|NetServer|Reliable|Event] num_parms=11 parms_size=0xDF return_offset=0xFFFF
  param[1] FName#781020:StructProperty<UStruct@0x7DF46D840DE0> offset=0x0 size=0x80 flags=0x10009008000082 [Parm|Const|Ref|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D840DE0 size=0x80
    field[1] FName#41950:FieldClassCastFlags=0x1000000008001 offset=0x0 size=0x1 flags=0x18001040000200 [Zero|POD|NoDtor] class_cast=0x1000000008001
    field[2] FName#1050090:ObjectPropertyBase<UStruct@0x7DF46D6A3400> offset=0x8 size=0x8 flags=0x11C001000080208 [Zero|NoDtor] class_cast=0x4018001
    field[3] FName#1050080:StructProperty<UStruct@0x7DF46D707B58> offset=0x10 size=0x60 flags=0x18001040000000 [POD|NoDtor] class_cast=0x108001
      struct UStruct@0x7DF46D707B58 size=0x60
      field[1] FName#1003:StructProperty<UStruct@0x7DF46D705688> offset=0x0 size=0x20 flags=0x18001041000005 [POD|NoDtor] class_cast=0x108001
        struct UStruct@0x7DF46D705688 size=0x20
        field[1] FName#4959:FieldClassCastFlags=0x101008001 offset=0x0 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
        field[2] FName#4961:FieldClassCastFlags=0x101008001 offset=0x8 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
        field[3] FName#4963:FieldClassCastFlags=0x101008001 offset=0x10 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
        field[4] FName#4957:FieldClassCastFlags=0x101008001 offset=0x18 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
      field[2] FName#79599:StructProperty<UStruct@0x7DF46D703338> offset=0x20 size=0x18 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x108001
        struct UStruct@0x7DF46D703338 size=0x18
        field[1] FName#4959:FieldClassCastFlags=0x101008001 offset=0x0 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
        field[2] FName#4961:FieldClassCastFlags=0x101008001 offset=0x8 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
        field[3] FName#4963:FieldClassCastFlags=0x101008001 offset=0x10 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
      field[3] FName#79606:StructProperty<UStruct@0x7DF46D703338> offset=0x40 size=0x18 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x108001
        struct UStruct@0x7DF46D703338 size=0x18
        field[1] FName#4959:FieldClassCastFlags=0x101008001 offset=0x0 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
        field[2] FName#4961:FieldClassCastFlags=0x101008001 offset=0x8 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
        field[3] FName#4963:FieldClassCastFlags=0x101008001 offset=0x10 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
    field[4] FName#1050071:StructProperty<UStruct@0x7DF46D773FE0> offset=0x70 size=0x8 flags=0x18001000000000 [NoDtor] class_cast=0x108001
      struct UStruct@0x7DF46D773FE0 size=0x8
      fields=0
  param[2] FName#692675:StructProperty<UStruct@0x7DF46D705EC8> offset=0x80 size=0xC flags=0x18001048000282 [Parm|Const|Ref|Zero|POD|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D705EC8 size=0xC
    field[1] FName#4959:IntProperty offset=0x0 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[2] FName#4961:IntProperty offset=0x4 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[3] FName#4963:IntProperty offset=0x8 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
  param[3] FName#1185236:StructProperty<UStruct@0x7DF46D703338> offset=0x90 size=0x18 flags=0x18001048000282 [Parm|Const|Ref|Zero|POD|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D703338 size=0x18
    field[1] FName#4959:FieldClassCastFlags=0x101008001 offset=0x0 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
    field[2] FName#4961:FieldClassCastFlags=0x101008001 offset=0x8 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
    field[3] FName#4963:FieldClassCastFlags=0x101008001 offset=0x10 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
  param[4] FName#672557:FieldClassCastFlags=0x1000000008001 offset=0xA8 size=0x1 flags=0x18001040000280 [Parm|Zero|POD|NoDtor] class_cast=0x1000000008001
  param[5] FName#1049952:StructProperty<UStruct@0x7DF46D705EC8> offset=0xAC size=0xC flags=0x18001048000282 [Parm|Const|Ref|Zero|POD|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D705EC8 size=0xC
    field[1] FName#4959:IntProperty offset=0x0 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[2] FName#4961:IntProperty offset=0x4 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[3] FName#4963:IntProperty offset=0x8 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
  param[6] FName#956618:StructProperty<UStruct@0x7DF46D705EC8> offset=0xB8 size=0xC flags=0x18001048000282 [Parm|Const|Ref|Zero|POD|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D705EC8 size=0xC
    field[1] FName#4959:IntProperty offset=0x0 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[2] FName#4961:IntProperty offset=0x4 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[3] FName#4963:IntProperty offset=0x8 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
  param[7] FName#1049946:StructProperty<UStruct@0x7DF46D705EC8> offset=0xC4 size=0xC flags=0x18001048000282 [Parm|Const|Ref|Zero|POD|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D705EC8 size=0xC
    field[1] FName#4959:IntProperty offset=0x0 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[2] FName#4961:IntProperty offset=0x4 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[3] FName#4963:IntProperty offset=0x8 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
  param[8] FName#1049939:StructProperty<UStruct@0x7DF46D705EC8> offset=0xD0 size=0xC flags=0x18001048000282 [Parm|Const|Ref|Zero|POD|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D705EC8 size=0xC
    field[1] FName#4959:IntProperty offset=0x0 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[2] FName#4961:IntProperty offset=0x4 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[3] FName#4963:IntProperty offset=0x8 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
  param[9] FName#1185229:BoolProperty offset=0xDC size=0x1 flags=0x18001040000280 [Parm|Zero|POD|NoDtor] class_cast=0x28001
  param[10] FName#1185222:BoolProperty offset=0xDD size=0x1 flags=0x18001040000280 [Parm|Zero|POD|NoDtor] class_cast=0x28001
  param[11] FName#1049182:BoolProperty offset=0xDE size=0x1 flags=0x18001040000280 [Parm|Zero|POD|NoDtor] class_cast=0x28001
```

## ServerPlaceCurrentPrefab Replay Contract

Status: `matches-live-reflection`
Parameter buffer size: `0xDF`

| Index | Name | Type | Offset | Size | Replay offset behavior |
| --- | --- | --- | --- | --- | --- |
| 1 | PlacementState | placement-state struct | `0x0` | `0x80` |  |
| 2 | PrimaryGrid | FIntVector | `0x80` | `0xC` | adjusted by replay delta |
| 3 | PlacementVector | placement vector struct | `0x90` | `0x18` |  |
| 4 | Orientation | uint8/enum | `0xA8` | `0x1` |  |
| 5 | ExtraGrid5 | FIntVector | `0xAC` | `0xC` | adjusted by replay delta |
| 6 | ExtraGrid6 | FIntVector | `0xB8` | `0xC` | adjusted by replay delta |
| 7 | ExtraGrid7 | FIntVector | `0xC4` | `0xC` | adjusted by replay delta |
| 8 | ExtraGrid8 | FIntVector | `0xD0` | `0xC` | adjusted by replay delta |
| 9 | Bool9 | bool | `0xDC` | `0x1` |  |
| 10 | Bool10 | bool | `0xDD` | `0x1` |  |
| 11 | Bool11 | bool | `0xDE` | `0x1` |  |

Additional replay-adjusted vector fields:
- PlacementState.Transform.Translation
- PlacementVector

## Live Reflection: ServerPlaceSimpleEntityVolume

```text
Describe function object: ServerPlaceSimpleEntityVolume
hits=1
hit[1] addr=0x7DF46DA11CE0 full=UFunctionName#69664 outer=OuterName#382591 flags=0xA20CC0 [Native|Net|NetServer|Reliable|Event] num_parms=10 parms_size=0xE4 return_offset=0xFFFF
  param[1] FName#781020:StructProperty<UStruct@0x7DF46D840DE0> offset=0x0 size=0x80 flags=0x10009008000082 [Parm|Const|Ref|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D840DE0 size=0x80
    field[1] FName#41950:FieldClassCastFlags=0x1000000008001 offset=0x0 size=0x1 flags=0x18001040000200 [Zero|POD|NoDtor] class_cast=0x1000000008001
    field[2] FName#1050090:ObjectPropertyBase<UStruct@0x7DF46D6A3400> offset=0x8 size=0x8 flags=0x11C001000080208 [Zero|NoDtor] class_cast=0x4018001
    field[3] FName#1050080:StructProperty<UStruct@0x7DF46D707B58> offset=0x10 size=0x60 flags=0x18001040000000 [POD|NoDtor] class_cast=0x108001
      struct UStruct@0x7DF46D707B58 size=0x60
      field[1] FName#1003:StructProperty<UStruct@0x7DF46D705688> offset=0x0 size=0x20 flags=0x18001041000005 [POD|NoDtor] class_cast=0x108001
        struct UStruct@0x7DF46D705688 size=0x20
        field[1] FName#4959:FieldClassCastFlags=0x101008001 offset=0x0 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
        field[2] FName#4961:FieldClassCastFlags=0x101008001 offset=0x8 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
        field[3] FName#4963:FieldClassCastFlags=0x101008001 offset=0x10 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
        field[4] FName#4957:FieldClassCastFlags=0x101008001 offset=0x18 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
      field[2] FName#79599:StructProperty<UStruct@0x7DF46D703338> offset=0x20 size=0x18 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x108001
        struct UStruct@0x7DF46D703338 size=0x18
        field[1] FName#4959:FieldClassCastFlags=0x101008001 offset=0x0 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
        field[2] FName#4961:FieldClassCastFlags=0x101008001 offset=0x8 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
        field[3] FName#4963:FieldClassCastFlags=0x101008001 offset=0x10 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
      field[3] FName#79606:StructProperty<UStruct@0x7DF46D703338> offset=0x40 size=0x18 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x108001
        struct UStruct@0x7DF46D703338 size=0x18
        field[1] FName#4959:FieldClassCastFlags=0x101008001 offset=0x0 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
        field[2] FName#4961:FieldClassCastFlags=0x101008001 offset=0x8 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
        field[3] FName#4963:FieldClassCastFlags=0x101008001 offset=0x10 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
    field[4] FName#1050071:StructProperty<UStruct@0x7DF46D773FE0> offset=0x70 size=0x8 flags=0x18001000000000 [NoDtor] class_cast=0x108001
      struct UStruct@0x7DF46D773FE0 size=0x8
      fields=0
  param[2] FName#944463:ObjectPropertyBase<UStruct@0x7DF46D67A600> offset=0x80 size=0x8 flags=0x18001000000280 [Parm|Zero|NoDtor] class_cast=0x4018001
  param[3] FName#1048873:StructProperty<UStruct@0x7DF46D703C38> offset=0x88 size=0x4 flags=0x18001048000282 [Parm|Const|Ref|Zero|POD|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D703C38 size=0x4
    field[1] FName#4915:ByteProperty offset=0x0 size=0x1 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008041
    field[2] FName#4925:ByteProperty offset=0x1 size=0x1 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008041
    field[3] FName#4947:ByteProperty offset=0x2 size=0x1 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008041
    field[4] FName#4913:ByteProperty offset=0x3 size=0x1 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008041
  param[4] FName#692675:StructProperty<UStruct@0x7DF46D705EC8> offset=0x8C size=0xC flags=0x18001048000282 [Parm|Const|Ref|Zero|POD|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D705EC8 size=0xC
    field[1] FName#4959:IntProperty offset=0x0 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[2] FName#4961:IntProperty offset=0x4 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[3] FName#4963:IntProperty offset=0x8 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
  param[5] FName#1185236:StructProperty<UStruct@0x7DF46D703338> offset=0x98 size=0x18 flags=0x18001048000282 [Parm|Const|Ref|Zero|POD|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D703338 size=0x18
    field[1] FName#4959:FieldClassCastFlags=0x101008001 offset=0x0 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
    field[2] FName#4961:FieldClassCastFlags=0x101008001 offset=0x8 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
    field[3] FName#4963:FieldClassCastFlags=0x101008001 offset=0x10 size=0x8 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x101008001
  param[6] FName#672557:FieldClassCastFlags=0x1000000008001 offset=0xB0 size=0x1 flags=0x18001040000280 [Parm|Zero|POD|NoDtor] class_cast=0x1000000008001
  param[7] FName#1049952:StructProperty<UStruct@0x7DF46D705EC8> offset=0xB4 size=0xC flags=0x18001048000282 [Parm|Const|Ref|Zero|POD|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D705EC8 size=0xC
    field[1] FName#4959:IntProperty offset=0x0 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[2] FName#4961:IntProperty offset=0x4 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[3] FName#4963:IntProperty offset=0x8 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
  param[8] FName#956618:StructProperty<UStruct@0x7DF46D705EC8> offset=0xC0 size=0xC flags=0x18001048000282 [Parm|Const|Ref|Zero|POD|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D705EC8 size=0xC
    field[1] FName#4959:IntProperty offset=0x0 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[2] FName#4961:IntProperty offset=0x4 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[3] FName#4963:IntProperty offset=0x8 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
  param[9] FName#1049946:StructProperty<UStruct@0x7DF46D705EC8> offset=0xCC size=0xC flags=0x18001048000282 [Parm|Const|Ref|Zero|POD|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D705EC8 size=0xC
    field[1] FName#4959:IntProperty offset=0x0 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[2] FName#4961:IntProperty offset=0x4 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[3] FName#4963:IntProperty offset=0x8 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
  param[10] FName#1049939:StructProperty<UStruct@0x7DF46D705EC8> offset=0xD8 size=0xC flags=0x18001048000282 [Parm|Const|Ref|Zero|POD|NoDtor] class_cast=0x108001
    struct UStruct@0x7DF46D705EC8 size=0xC
    field[1] FName#4959:IntProperty offset=0x0 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[2] FName#4961:IntProperty offset=0x4 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
    field[3] FName#4963:IntProperty offset=0x8 size=0x4 flags=0x18001041000205 [Zero|POD|NoDtor] class_cast=0x1008081
```

## ServerPlaceSimpleEntityVolume Replay Contract

Status: `matches-live-reflection`
Parameter buffer size: `0xE4`

| Index | Name | Type | Offset | Size | Replay offset behavior |
| --- | --- | --- | --- | --- | --- |
| 1 | PlacementState | placement-state struct | `0x0` | `0x80` |  |
| 2 | EntityClass | UObject* | `0x80` | `0x8` |  |
| 3 | OrientationBytes | 4-byte orientation/flags struct | `0x88` | `0x4` |  |
| 4 | PrimaryGrid | FIntVector | `0x8C` | `0xC` | adjusted by replay delta |
| 5 | PlacementVector | placement vector struct | `0x98` | `0x18` |  |
| 6 | BoolLikeParam | bool | `0xB0` | `0x1` |  |
| 7 | ExtraGrid7 | FIntVector | `0xB4` | `0xC` | adjusted by replay delta |
| 8 | ExtraGrid8 | FIntVector | `0xC0` | `0xC` | adjusted by replay delta |
| 9 | ExtraGrid9 | FIntVector | `0xCC` | `0xC` | adjusted by replay delta |
| 10 | ExtraGrid10 | FIntVector | `0xD8` | `0xC` | adjusted by replay delta |

Additional replay-adjusted vector fields:
- PlacementState.Transform.Translation
- PlacementVector

## Physics Side-Channel Function Reflection

SetPlaceAsPhysicsAvailable: `matches-live-reflection`, parameter buffer size `0x1`.
SetPlaceAsPhysicsEnabled: `matches-live-reflection`, parameter buffer size `0x1`.
ServerModifyEntity: `matches-live-reflection`, parameter buffer size `0x18`.

These are captured for diagnosis. `SetPlaceAsPhysics*` are not replayable prefab placements.

## Last Native Capture

```text
Prefab native capture: none
```

## Capture Files

- Latest detail: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799\prefab-native-last.txt` (missing)
- Capture log: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799\prefab-native-captures.ndjson` (0 records)
