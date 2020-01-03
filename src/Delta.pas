unit Delta;

interface

uses SysUtils, Default;

const
  DT_BYTE = 1 shl 0;
  DT_SHORT = 1 shl 1;
  DT_FLOAT = 1 shl 2;
  DT_INTEGER = 1 shl 3;
  DT_ANGLE = 1 shl 4;
  DT_TIMEWINDOW_8 = 1 shl 5;
  DT_TIMEWINDOW_BIG = 1 shl 6;
  DT_STRING = 1 shl 7;

  DT_SIGNED = 1 shl 31;

type
  PDelta = ^TDelta;

  TDeltaEncoder = procedure(Delta: PDelta; OS, NS: Pointer); cdecl;

  PDeltaEncoderEntry = ^TDeltaEncoderEntry; // 12. Confirmed.
  TDeltaEncoderEntry = record
    Prev: PDeltaEncoderEntry;
    Name: PLChar; // through StrDup
    Func: TDeltaEncoder;
  end;

  PDeltaReg = ^TDeltaReg;
  TDeltaReg = record
    Prev: PDeltaReg;
    Name: PLChar;
    FileName: PLChar;
    Delta: PDelta;
  end;

  PDeltaField = ^TDeltaField; // Size is 68. Confirmed.
  TDeltaField = record
    FieldType: UInt32;          // 0. Confirmed.
    Name: array[1..32] of LChar; // 4. Confirmed. A field name.
    Offset: UInt32;             // 36. Confirmed. Offset (unsigned).
    FieldSize: UInt16;                 // 40. Sets to "1" when parsing.
    Bits: UInt32;               // 44. Confirmed. How many bits are in offset value.
    Scale: Single;              // 48. Should really be a scale.
    PScale: Single;             // 52. Another scale.
    Flags: set of (ffReady, __ffPadding = 15);    // 56. Unsure about this.
                                                //     Is 16-bit, actually.
    SendCount: UInt32;          // 60. How many times we should "send" this field.
    RecvCount: UInt32;          // 64. Delta_Parse increments it.
    TotalScale: Single;         // 68. Custom field.
  end;
  TDeltaFieldArray = array[0..0] of TDeltaField;
  // dp @ metadelta; dp @ static delta constants
  // {$IF SizeOf(TDeltaField) <> 68} {$MESSAGE WARN 'Structure size mismatch @ TDeltaField.'} {$DEFINE MSME} {$IFEND}

  TDelta = record
    Active: Boolean;    // 0: If active, fields are written out.
    NumFields: Int32; // 4: Number of delta fields. Signed.
    Name: array[1..32] of LChar; // 8. Confirmed.
    ConditionalEncoder: TDeltaEncoder; // 40. Confirmed.
    Fields: ^TDeltaFieldArray; // 44: Pointer to a field array.
  end;

  PDeltaOffset = ^TDeltaOffset;
  TDeltaOffset = record
    Name: PLChar;
    Offset: UInt32;
  end;

  PDeltaOffsetArray = ^TDeltaOffsetArray;
  TDeltaOffsetArray = array[0..0] of TDeltaOffset;

  PDeltaLinkedField = ^TDeltaLinkedField;
  TDeltaLinkedField = record
    Prev: PDeltaLinkedField;
    Field: PDeltaField;
  end;

  TDeltaFuncs = record helper for TDelta
    class function FindField(const D: TDelta; Name: PLChar): PDeltaField; static;
    class function FindFieldIndex(const D: TDelta; Name: PLChar): Int; static;
    class procedure SetField(var D: TDelta; Name: PLChar); static;
    class procedure UnsetField(var D: TDelta; Name: PLChar); static;
    class procedure SetFieldByIndex(var D: TDelta; Index: UInt); static;
    class procedure UnsetFieldByIndex(var D: TDelta; Index: UInt); static;
    class procedure ClearFlags(var D: TDelta); static;
    class function TestDelta(OS, NS: Pointer; var Delta: TDelta): UInt; static;
    class function CountSendFields(var Delta: TDelta): UInt; static;
    class procedure MarkSendFields(OS, NS: Pointer; var Delta: TDelta); static;
    class procedure SetSendFlagBits(const Delta: TDelta; Dest: Pointer; out BytesWritten: UInt); static;
    class procedure WriteMarkedFields(OS, NS: Pointer; const Delta: TDelta); static;
    class function CheckDelta(OS, NS: Pointer; var Delta: TDelta): UInt; static;
    class procedure WriteMarkedDelta(OS, NS: Pointer; ForceUpdate: Boolean; var Delta: TDelta; Fields: UInt; Func: TProcedure); static;
    class procedure WriteDelta(OS, NS: Pointer; ForceUpdate: Boolean; var Delta: TDelta; Func: TProcedure); static;
    class function ParseDelta(OS, NS: Pointer; var Delta: TDelta): Int; static;
    class procedure FreeDescription(var D: PDelta); static;
    class function FindDefinition(Name: PLChar; out Count: UInt): PDeltaOffsetArray; static;
    class procedure AddDefinition(Name: PLChar; Data: PDeltaOffsetArray; Count: UInt); static;
    class procedure ClearDefinitions; static;
    class procedure SkipDescription(var F: Pointer); static;
    class function ParseOneField(var F: Pointer; out LinkBase: PDeltaLinkedField; Count: UInt; Base: PDeltaOffsetArray): Boolean; static;
    class function ParseDescription(Name: PLChar; var Delta: PDelta; F: Pointer): Boolean; static;
    class procedure AddEncoder(Name: PLChar; Func: TDeltaEncoder); static;
    class procedure ClearEncoders; static;
    class function LookupEncoder(Name: PLChar): TDeltaEncoder; static;
    class function CountLinks(P: PDeltaLinkedField): UInt; static;
    class procedure ReverseLinks(var P: PDeltaLinkedField); static;
    class procedure ClearLinks(var P: PDeltaLinkedField); static;
    class function BuildFromLinks(var LF: PDeltaLinkedField): PDelta; static;
    class function FindOffset(Count: UInt; Base: PDeltaOffsetArray; Name: PLChar): UInt32; static;
    class function ParseType(var FieldType: UInt32; var F: Pointer): Boolean; static;
    class function ParseField(Count: UInt; Base: PDeltaOffsetArray; LF: PDeltaLinkedField; var F: Pointer): Boolean; static;
    class procedure InitEncoders; static;
    class function Load(Name: PLChar; var Delta: PDelta; FileName: PLChar): Boolean; static;
    class function LookupRegistration(Name: PLChar): PDelta; static;
    class function Register(Name, FileName: PLChar): PDelta; static;
    class procedure ClearRegistrations; static;

    class procedure ClearStats_F; cdecl; static;
    class procedure DumpStats_F; cdecl; static;

    class procedure Init; static;
    class procedure Shutdown; static;
  end;

  PDeltaDefinition = ^TDeltaDefinition; // 16, confirmed.
  TDeltaDefinition = record
    Prev: PDeltaDefinition;
    Name: PLChar;
    Count: UInt32;
    Offsets: PDeltaOffsetArray;
  end;

var
 RegList: PDeltaReg = nil;

implementation

uses
  Common, Console, Memory, MsgBuf, SVMain, SysMain, SDK;

type
 TSendFlagArray = array[0..1] of UInt32;

var
 EncoderList: PDeltaEncoderEntry = nil;
 DefList: PDeltaDefinition = nil;

const
 DT_ClientData_T: array[1..56] of TDeltaOffset =
 ((Name: 'origin[0]'; Offset: 0),
  (Name: 'origin[1]'; Offset: 4),
  (Name: 'origin[2]'; Offset: 8),
  (Name: 'velocity[0]'; Offset: 12),
  (Name: 'velocity[1]'; Offset: 16),
  (Name: 'velocity[2]'; Offset: 20),
  (Name: 'viewmodel'; Offset: 24),
  (Name: 'punchangle[0]'; Offset: 28),
  (Name: 'punchangle[1]'; Offset: 32),
  (Name: 'punchangle[2]'; Offset: 36),
  (Name: 'flags'; Offset: 40),
  (Name: 'waterlevel'; Offset: 44),
  (Name: 'watertype'; Offset: 48),
  (Name: 'view_ofs[0]'; Offset: 52),
  (Name: 'view_ofs[1]'; Offset: 56),
  (Name: 'view_ofs[2]'; Offset: 60),
  (Name: 'health'; Offset: 64),
  (Name: 'bInDuck'; Offset: 68),
  (Name: 'weapons'; Offset: 72),
  (Name: 'flTimeStepSound'; Offset: 76),
  (Name: 'flDuckTime'; Offset: 80),
  (Name: 'flSwimTime'; Offset: 84),
  (Name: 'waterjumptime'; Offset: 88),
  (Name: 'maxspeed'; Offset: 92),
  (Name: 'fov'; Offset: 96),
  (Name: 'weaponanim'; Offset: 100),
  (Name: 'm_iId'; Offset: 104),
  (Name: 'ammo_shells'; Offset: 108),
  (Name: 'ammo_nails'; Offset: 112),
  (Name: 'ammo_cells'; Offset: 116),
  (Name: 'ammo_rockets'; Offset: 120),
  (Name: 'm_flNextAttack'; Offset: 124),
  (Name: 'tfstate'; Offset: 128),
  (Name: 'pushmsec'; Offset: 132),
  (Name: 'deadflag'; Offset: 136),
  (Name: 'physinfo'; Offset: 140),
  (Name: 'iuser1'; Offset: 396),
  (Name: 'iuser2'; Offset: 400),
  (Name: 'iuser3'; Offset: 404),
  (Name: 'iuser4'; Offset: 408),
  (Name: 'fuser1'; Offset: 412),
  (Name: 'fuser2'; Offset: 416),
  (Name: 'fuser3'; Offset: 420),
  (Name: 'fuser4'; Offset: 424),
  (Name: 'vuser1[0]'; Offset: 428),
  (Name: 'vuser1[1]'; Offset: 432),
  (Name: 'vuser1[2]'; Offset: 436),
  (Name: 'vuser2[0]'; Offset: 440),
  (Name: 'vuser2[1]'; Offset: 444),
  (Name: 'vuser2[2]'; Offset: 448),
  (Name: 'vuser3[0]'; Offset: 452),
  (Name: 'vuser3[1]'; Offset: 456),
  (Name: 'vuser3[2]'; Offset: 460),
  (Name: 'vuser4[0]'; Offset: 464),
  (Name: 'vuser4[1]'; Offset: 468),
  (Name: 'vuser4[2]'; Offset: 472));

 DT_WeaponData_T: array[1..22] of TDeltaOffset =
 ((Name: 'm_iId'; Offset: 0),
  (Name: 'm_iClip'; Offset: 4),
  (Name: 'm_flNextPrimaryAttack'; Offset: 8),
  (Name: 'm_flNextSecondaryAttack'; Offset: 12),
  (Name: 'm_flTimeWeaponIdle'; Offset: 16),
  (Name: 'm_fInReload'; Offset: 20),
  (Name: 'm_fInSpecialReload'; Offset: 24),
  (Name: 'm_flNextReload'; Offset: 28),
  (Name: 'm_flPumpTime'; Offset: 32),
  (Name: 'm_fReloadTime'; Offset: 36),
  (Name: 'm_fAimedDamage'; Offset: 40),
  (Name: 'm_fNextAimBonus'; Offset: 44),
  (Name: 'm_fInZoom'; Offset: 48),
  (Name: 'm_iWeaponState'; Offset: 52),
  (Name: 'iuser1'; Offset: 56),
  (Name: 'iuser2'; Offset: 60),
  (Name: 'iuser3'; Offset: 64),
  (Name: 'iuser4'; Offset: 68),
  (Name: 'fuser1'; Offset: 72),
  (Name: 'fuser2'; Offset: 76),
  (Name: 'fuser3'; Offset: 80),
  (Name: 'fuser4'; Offset: 84));

 DT_UserCmd_T: array[1..16] of TDeltaOffset =
 ((Name: 'lerp_msec'; Offset: 0),
  (Name: 'msec'; Offset: 2),
  (Name: 'viewangles[0]'; Offset: 4),
  (Name: 'viewangles[1]'; Offset: 8),
  (Name: 'viewangles[2]'; Offset: 12),
  (Name: 'forwardmove'; Offset: 16),
  (Name: 'sidemove'; Offset: 20),
  (Name: 'upmove'; Offset: 24),
  (Name: 'lightlevel'; Offset: 28),
  (Name: 'buttons'; Offset: 30),
  (Name: 'impulse'; Offset: 32),
  (Name: 'weaponselect'; Offset: 33),
  (Name: 'impact_index'; Offset: 36),
  (Name: 'impact_position[0]'; Offset: 40),
  (Name: 'impact_position[1]'; Offset: 44),
  (Name: 'impact_position[2]'; Offset: 48));

 DT_EntityState_T: array[1..87] of TDeltaOffset =
 (
  (Name: 'origin[0]'; Offset: 16),
  (Name: 'origin[1]'; Offset: 20),
  (Name: 'origin[2]'; Offset: 24),
  (Name: 'angles[0]'; Offset: 28),
  (Name: 'angles[1]'; Offset: 32),
  (Name: 'angles[2]'; Offset: 36),
  (Name: 'modelindex'; Offset: 40),
  (Name: 'sequence'; Offset: 44),
  (Name: 'frame'; Offset: 48),
  (Name: 'colormap'; Offset: 52),
  (Name: 'skin'; Offset: 56),
  (Name: 'solid'; Offset: 58),
  (Name: 'effects'; Offset: 60),
  (Name: 'scale'; Offset: 64),
  (Name: 'eflags'; Offset: 68),
  (Name: 'rendermode'; Offset: 72),
  (Name: 'renderamt'; Offset: 76),
  (Name: 'rendercolor.r'; Offset: 80),
  (Name: 'rendercolor.g'; Offset: 81),
  (Name: 'rendercolor.b'; Offset: 82),
  (Name: 'renderfx'; Offset: 84),
  (Name: 'movetype'; Offset: 88),
  (Name: 'animtime'; Offset: 92),
  (Name: 'framerate'; Offset: 96),
  (Name: 'body'; Offset: 100),
  (Name: 'controller[0]'; Offset: 104),
  (Name: 'controller[1]'; Offset: 105),
  (Name: 'controller[2]'; Offset: 106),
  (Name: 'controller[3]'; Offset: 107),
  (Name: 'blending[0]'; Offset: 108),
  (Name: 'blending[1]'; Offset: 109),
  (Name: 'velocity[0]'; Offset: 112),
  (Name: 'velocity[1]'; Offset: 116),
  (Name: 'velocity[2]'; Offset: 120),
  (Name: 'mins[0]'; Offset: 124),
  (Name: 'mins[1]'; Offset: 128),
  (Name: 'mins[2]'; Offset: 132),
  (Name: 'maxs[0]'; Offset: 136),
  (Name: 'maxs[1]'; Offset: 140),
  (Name: 'maxs[2]'; Offset: 144),
  (Name: 'aiment'; Offset: 148),
  (Name: 'owner'; Offset: 152),
  (Name: 'friction'; Offset: 156),
  (Name: 'gravity'; Offset: 160),
  (Name: 'team'; Offset: 164),
  (Name: 'playerclass'; Offset: 168),
  (Name: 'health'; Offset: 172),
  (Name: 'spectator'; Offset: 176),
  (Name: 'weaponmodel'; Offset: 180),
  (Name: 'gaitsequence'; Offset: 184),
  (Name: 'basevelocity[0]'; Offset: 188),
  (Name: 'basevelocity[1]'; Offset: 192),
  (Name: 'basevelocity[2]'; Offset: 196),
  (Name: 'usehull'; Offset: 200),
  (Name: 'oldbuttons'; Offset: 204),
  (Name: 'onground'; Offset: 208),
  (Name: 'iStepLeft'; Offset: 212),
  (Name: 'flFallVelocity'; Offset: 216),

  (Name: 'weaponanim'; Offset: 224),
  (Name: 'startpos[0]'; Offset: 228),
  (Name: 'startpos[1]'; Offset: 232),
  (Name: 'startpos[2]'; Offset: 236),
  (Name: 'endpos[0]'; Offset: 240),
  (Name: 'endpos[1]'; Offset: 244),
  (Name: 'endpos[2]'; Offset: 248),
  (Name: 'impacttime'; Offset: 252),
  (Name: 'starttime'; Offset: 256),
  (Name: 'iuser1'; Offset: 260),
  (Name: 'iuser2'; Offset: 264),
  (Name: 'iuser3'; Offset: 268),
  (Name: 'iuser4'; Offset: 272),
  (Name: 'fuser1'; Offset: 276),
  (Name: 'fuser2'; Offset: 280),
  (Name: 'fuser3'; Offset: 284),
  (Name: 'fuser4'; Offset: 288),
  (Name: 'vuser1[0]'; Offset: 292),
  (Name: 'vuser1[1]'; Offset: 296),
  (Name: 'vuser1[2]'; Offset: 300),
  (Name: 'vuser2[0]'; Offset: 304),
  (Name: 'vuser2[1]'; Offset: 308),
  (Name: 'vuser2[2]'; Offset: 312),
  (Name: 'vuser3[0]'; Offset: 316),
  (Name: 'vuser3[1]'; Offset: 320),
  (Name: 'vuser3[2]'; Offset: 324),
  (Name: 'vuser4[0]'; Offset: 328),
  (Name: 'vuser4[1]'; Offset: 332),
  (Name: 'vuser4[2]'; Offset: 336));

 DT_Event_T: array[1..14] of TDeltaOffset =
 ((Name: 'entindex'; Offset: 4),
  (Name: 'origin[0]'; Offset: 8),
  (Name: 'origin[1]'; Offset: 12),
  (Name: 'origin[2]'; Offset: 16),
  (Name: 'angles[0]'; Offset: 20),
  (Name: 'angles[1]'; Offset: 24),
  (Name: 'angles[2]'; Offset: 28),
  (Name: 'ducking'; Offset: 44),
  (Name: 'fparam1'; Offset: 48),
  (Name: 'fparam2'; Offset: 52),
  (Name: 'iparam1'; Offset: 56),
  (Name: 'iparam2'; Offset: 60),
  (Name: 'bparam1'; Offset: 64),
  (Name: 'bparam2'; Offset: 68));

 DT_MetaDelta_T: array[1..8] of TDeltaOffset =
 ((Name: 'fieldType'; Offset: 0),
  (Name: 'fieldName'; Offset: 4),
  (Name: 'fieldOffset'; Offset: 36),
  (Name: 'fieldSize'; Offset: 40),
  (Name: 'significant_bits'; Offset: 44),
  (Name: 'premultiply'; Offset: 48),
  (Name: 'postmultiply'; Offset: 52),
  (Name: 'flags'; Offset: 56));


class function TDeltaFuncs.FindField(const D: TDelta; Name: PLChar): PDeltaField;
var
 I: Int;
begin
for I := 0 to D.NumFields - 1 do
 if StrIComp(@D.Fields[I].Name, Name) = 0 then
  begin
   Result := @D.Fields[I];
   Exit;
  end;

Print(['Delta_FindField: Warning - couldn''t find "', Name, '".']);
Result := nil;
end;

class function TDeltaFuncs.FindFieldIndex(const D: TDelta; Name: PLChar): Int;
var
 I: Int;
begin
for I := 0 to D.NumFields - 1 do
 if StrIComp(@D.Fields[I].Name, Name) = 0 then
  begin
   Result := I;
   Exit;
  end;

Print(['Delta_FindFieldIndex: Warning - couldn''t find "', Name, '".']);
Result := -1;
end;

class procedure TDeltaFuncs.SetField(var D: TDelta; Name: PLChar);
var
 F: PDeltaField;
begin
F := TDelta.FindField(D, Name);
if F <> nil then
 Include(F.Flags, ffReady);
end;

class procedure TDeltaFuncs.UnsetField(var D: TDelta; Name: PLChar);
var
 F: PDeltaField;
begin
F := TDelta.FindField(D, Name);
if F <> nil then
 Exclude(F.Flags, ffReady);
end;

class procedure TDeltaFuncs.SetFieldByIndex(var D: TDelta; Index: UInt);
begin
Include(D.Fields[Index].Flags, ffReady);
end;

class procedure TDeltaFuncs.UnsetFieldByIndex(var D: TDelta; Index: UInt);
begin
Exclude(D.Fields[Index].Flags, ffReady);
end;

class procedure TDeltaFuncs.ClearFlags(var D: TDelta);
var
 I: Int;
begin
for I := 0 to D.NumFields - 1 do
 D.Fields[I].Flags := [];
end;

class function TDeltaFuncs.TestDelta(OS, NS: Pointer; var Delta: TDelta): UInt;
var
 I, LastIndex: Int;
 F: PDeltaField;
 B: Boolean;
 Bits, FT: UInt;
begin
Bits := 0;
LastIndex := -1;

for I := 0 to Delta.NumFields - 1 do
 begin
  F := @Delta.Fields[I];
  FT := F.FieldType and not DT_SIGNED;
  case FT of
   DT_TIMEWINDOW_8, DT_TIMEWINDOW_BIG, DT_FLOAT, DT_INTEGER, DT_ANGLE:
    B := PUInt32(UInt(OS) + F.Offset)^ = PUInt32(UInt(NS) + F.Offset)^;
   DT_BYTE:
    B := PByte(UInt(OS) + F.Offset)^ = PByte(UInt(NS) + F.Offset)^;
   DT_SHORT:
    B := PUInt16(UInt(OS) + F.Offset)^ = PUInt16(UInt(NS) + F.Offset)^;
   DT_STRING:
    B := StrIComp(PLChar(UInt(OS) + F.Offset), PLChar(UInt(NS) + F.Offset)) = 0;
   else
    begin
     B := True;
     Print(['Delta_TestDelta: Bad field type "', FT, '".']);
    end;
  end;

  if not B then
   begin
    LastIndex := I;
    if FT = DT_STRING then
     Inc(Bits, (StrLen(PLChar(UInt(NS) + F.Offset)) + 1) * 8)
    else
     Inc(Bits, F.Bits);
   end;
 end;

if LastIndex <> -1 then
 Inc(Bits, (LastIndex and not 7) + 8);

Result := Bits;
end;

class function TDeltaFuncs.CountSendFields(var Delta: TDelta): UInt;
var
 I: Int;
begin
Result := 0;

for I := 0 to Delta.NumFields - 1 do
 if ffReady in Delta.Fields[I].Flags then
  begin
   Inc(Delta.Fields[I].SendCount);
   Inc(Result);
  end;
end;

class procedure TDeltaFuncs.MarkSendFields(OS, NS: Pointer; var Delta: TDelta);
var
 I: Int;
 F: PDeltaField;
 B: Boolean;
begin
for I := 0 to Delta.NumFields - 1 do
 begin
  F := @Delta.Fields[I];
  case F.FieldType and not DT_SIGNED of
   DT_TIMEWINDOW_8, DT_TIMEWINDOW_BIG, DT_FLOAT, DT_INTEGER, DT_ANGLE:
    B := PUInt32(UInt(OS) + F.Offset)^ <> PUInt32(UInt(NS) + F.Offset)^;
   DT_BYTE:
    B := PByte(UInt(OS) + F.Offset)^ <> PByte(UInt(NS) + F.Offset)^;
   DT_SHORT:
    B := PUInt16(UInt(OS) + F.Offset)^ <> PUInt16(UInt(NS) + F.Offset)^;
   DT_STRING:
    B := StrIComp(PLChar(UInt(OS) + F.Offset), PLChar(UInt(NS) + F.Offset)) <> 0;
   else
    begin
     B := False;
     Print(['Delta_MarkSendFields: Bad field type "', F.FieldType and not DT_SIGNED, '".']);
    end;
  end;

  if B then
   Include(F.Flags, ffReady);
 end;

if @Delta.ConditionalEncoder <> nil then
 Delta.ConditionalEncoder(@Delta, OS, NS);
end;

class procedure TDeltaFuncs.SetSendFlagBits(const Delta: TDelta; Dest: Pointer; out BytesWritten: UInt);
var
 ID, I: Int;
 P: PUInt32;
begin
MemSet(Dest^, 8, 0);
ID := -1;
for I := Delta.NumFields - 1 downto 0 do
 if ffReady in Delta.Fields[I].Flags then
  begin
   if ID = -1 then
    ID := I;
   P := PUInt32(UInt(Dest) + 4 * UInt(I > 31));
   P^ := P^ or UInt(1 shl (I and 31));
  end;

if ID = -1 then
 BytesWritten := 0
else
 BytesWritten := (UInt(ID) shr 3) + 1;
end;

class procedure TDeltaFuncs.WriteMarkedFields(OS, NS: Pointer; const Delta: TDelta);
var
 I: Int;
 F: PDeltaField;
 Signed: Boolean;
begin
for I := 0 to Delta.NumFields - 1 do
 begin
  F := @Delta.Fields[I];
  if ffReady in F.Flags then
   begin
    Signed := (F.FieldType and DT_SIGNED) > 0;
    case F.FieldType and not DT_SIGNED of
     DT_FLOAT:
      if Signed then
       if F.Scale <> 1 then
        MSG_WriteSBits(Trunc(PSingle(UInt(NS) + F.Offset)^ * F.Scale), F.Bits)
       else
        MSG_WriteSBits(Trunc(PSingle(UInt(NS) + F.Offset)^), F.Bits)
      else
       if F.Scale <> 1 then
        MSG_WriteBits(Trunc(PSingle(UInt(NS) + F.Offset)^ * F.Scale), F.Bits)
       else
        MSG_WriteBits(Trunc(PSingle(UInt(NS) + F.Offset)^), F.Bits);
     DT_ANGLE:
      MSG_WriteBitAngle(PSingle(UInt(NS) + F.Offset)^, F.Bits);
     DT_TIMEWINDOW_8:
      MSG_WriteSBits(Trunc(SV.Time * 100) - Trunc(PSingle(UInt(NS) + F.Offset)^ * 100), 8);
     DT_TIMEWINDOW_BIG:
      MSG_WriteSBits(Trunc(SV.Time * F.Scale) - Trunc(PSingle(UInt(NS) + F.Offset)^ * F.Scale), F.Bits);
     DT_BYTE:
      if Signed then
       MSG_WriteSBits(Int8(Trunc(PInt8(UInt(NS) + F.Offset)^ * F.Scale)), F.Bits)
      else
       MSG_WriteBits(UInt8(Trunc(PUInt8(UInt(NS) + F.Offset)^ * F.Scale)), F.Bits);
     DT_SHORT:
      if Signed then
       MSG_WriteSBits(Int16(Trunc(PInt16(UInt(NS) + F.Offset)^ * F.Scale)), F.Bits)
      else
       MSG_WriteBits(UInt16(Trunc(PUInt16(UInt(NS) + F.Offset)^ * F.Scale)), F.Bits);
     DT_INTEGER:
      if Signed then
       if F.Scale <> 1 then
        MSG_WriteSBits(Trunc(PInt32(UInt(NS) + F.Offset)^ * F.Scale), F.Bits)
       else
        MSG_WriteSBits(PInt32(UInt(NS) + F.Offset)^, F.Bits)
      else
       if F.Scale <> 1 then
        MSG_WriteBits(Trunc(PUInt32(UInt(NS) + F.Offset)^ * F.Scale), F.Bits)
       else
        MSG_WriteBits(PUInt32(UInt(NS) + F.Offset)^, F.Bits);
     DT_STRING:
      MSG_WriteBitString(PLChar(UInt(NS) + F.Offset));
     else
      Print(['Delta_WriteMarkedFields: Bad field type "', F.FieldType and not DT_SIGNED, '".']);
    end;
   end;
 end;
end;

class function TDeltaFuncs.CheckDelta(OS, NS: Pointer; var Delta: TDelta): UInt;
begin
TDelta.ClearFlags(Delta);
TDelta.MarkSendFields(OS, NS, Delta);
Result := TDelta.CountSendFields(Delta);
end;

class procedure TDeltaFuncs.WriteMarkedDelta(OS, NS: Pointer; ForceUpdate: Boolean; var Delta: TDelta; Fields: UInt; Func: TProcedure);
var
 I: Int;
 BytesWritten: UInt;
 C: array[1..8] of Byte;
begin
if (Fields > 0) or ForceUpdate then
 begin
  TDelta.SetSendFlagBits(Delta, @C, BytesWritten);
  if @Func <> nil then
   Func;
  MSG_WriteBits(BytesWritten, 3);
  for I := 1 to BytesWritten do
   MSG_WriteBits(C[I], 8);
  TDelta.WriteMarkedFields(OS, NS, Delta);
 end;
end;

class procedure TDeltaFuncs.WriteDelta(OS, NS: Pointer; ForceUpdate: Boolean; var Delta: TDelta; Func: TProcedure);
begin
TDelta.WriteMarkedDelta(OS, NS, ForceUpdate, Delta, TDelta.CheckDelta(OS, NS, Delta), Func);
end;

class function TDeltaFuncs.ParseDelta(OS, NS: Pointer; var Delta: TDelta): Int;
var
 CB, ByteCount: UInt;
 I: Int;
 C: array[1..8] of Byte;
 F: PDeltaField;
 Signed: Boolean;
 CH: LChar;
 P: PLChar;
 FT: UInt32;
begin
CB := MSG_CurrentBit;
MemSet(C, SizeOf(C), 0);

ByteCount := MSG_ReadBits(3);
for I := 1 to ByteCount do
 C[I] := MSG_ReadBits(8);

for I := 0 to Delta.NumFields - 1 do
 begin
  F := @Delta.Fields[I];
  FT := F.FieldType and not DT_SIGNED;
  if (PUInt32(UInt(@C) + 4 * UInt(I > 31))^ and (1 shl (I and 31))) > 0 then
   begin
    Signed := (F.FieldType and DT_SIGNED) > 0;
    Inc(F.RecvCount);
    case FT of
     DT_FLOAT:
      if Signed then
       PSingle(UInt(NS) + F.Offset)^ := MSG_ReadSBits(F.Bits) * F.TotalScale
      else
       PSingle(UInt(NS) + F.Offset)^ := MSG_ReadBits(F.Bits) * F.TotalScale;
     DT_ANGLE:
      PSingle(UInt(NS) + F.Offset)^ := MSG_ReadBitAngle(F.Bits);
     DT_TIMEWINDOW_8:
      PSingle(UInt(NS) + F.Offset)^ := (SV.Time * 100 - MSG_ReadSBits(8)) * (1 / 100);
     DT_TIMEWINDOW_BIG:
      PSingle(UInt(NS) + F.Offset)^ := (SV.Time * F.Scale - MSG_ReadSBits(F.Bits)) / F.Scale;
     DT_BYTE:
      if Signed then
       PInt8(UInt(NS) + F.Offset)^ := Trunc(Int8(MSG_ReadSBits(F.Bits)) * F.TotalScale)
      else
       PUInt8(UInt(NS) + F.Offset)^ := Trunc(UInt8(MSG_ReadBits(F.Bits)) * F.TotalScale);
     DT_SHORT:
      if Signed then
       PInt16(UInt(NS) + F.Offset)^ := Trunc(Int16(MSG_ReadSBits(F.Bits)) * F.TotalScale)
      else
       PUInt16(UInt(NS) + F.Offset)^ := Trunc(UInt16(MSG_ReadBits(F.Bits)) * F.TotalScale);
     DT_INTEGER:
      if Signed then
       if F.TotalScale <> 1 then
        PInt32(UInt(NS) + F.Offset)^ := Trunc(Int32(MSG_ReadSBits(F.Bits)) * F.TotalScale)
       else
        PInt32(UInt(NS) + F.Offset)^ := Int32(MSG_ReadSBits(F.Bits))
      else
       if F.TotalScale <> 1 then
        PUInt32(UInt(NS) + F.Offset)^ := Trunc(UInt32(MSG_ReadBits(F.Bits)) * F.TotalScale)
       else
        PUInt32(UInt(NS) + F.Offset)^ := UInt32(MSG_ReadBits(F.Bits));
     DT_STRING:
      begin
       P := PLChar(UInt(NS) + F.Offset);
       repeat
        CH := LChar(MSG_ReadBits(8));
        P^ := CH;
        Inc(UInt(P));
       until CH = #0;
      end;
     else
      Print(['Delta_ParseDelta: Unparseable field type "', FT, '".']);
    end;
   end
  else
   case FT of
    DT_FLOAT, DT_INTEGER, DT_ANGLE, DT_TIMEWINDOW_8, DT_TIMEWINDOW_BIG:
     PUInt32(UInt(NS) + F.Offset)^ := PUInt32(UInt(OS) + F.Offset)^;
    DT_BYTE:
     PUInt8(UInt(NS) + F.Offset)^ := PUInt8(UInt(OS) + F.Offset)^;
    DT_SHORT:
     PUInt16(UInt(NS) + F.Offset)^ := PUInt16(UInt(OS) + F.Offset)^;
    DT_STRING:
     StrCopy(PLChar(UInt(NS) + F.Offset), PLChar(UInt(OS) + F.Offset));
    else
     Print(['Delta_ParseDelta: Unparseable field type "', FT, '".']);
   end;
 end;

Result := MSG_CurrentBit - CB;
end;

class procedure TDeltaFuncs.AddEncoder(Name: PLChar; Func: TDeltaEncoder);
var
 P: PDeltaEncoderEntry;
begin
P := Mem_Alloc(SizeOf(P^));
P.Prev := EncoderList;
P.Name := Mem_StrDup(Name);
P.Func := @Func;
EncoderList := P;
end;

class procedure TDeltaFuncs.ClearEncoders;
var
 P, P2: PDeltaEncoderEntry;
begin
P := EncoderList;
while P <> nil do
 begin
  P2 := P.Prev;
  Mem_Free(P.Name);
  Mem_Free(P);
  P := P2;
 end;

EncoderList := nil;
end;

class function TDeltaFuncs.LookupEncoder(Name: PLChar): TDeltaEncoder;
var
 P: PDeltaEncoderEntry;
begin
P := EncoderList;
while P <> nil do
 if StrIComp(P.Name, Name) = 0 then
  begin
   Result := @P.Func;
   Exit;
  end
 else
  P := P.Prev;

Result := nil;
end;

class function TDeltaFuncs.CountLinks(P: PDeltaLinkedField): UInt;
begin
Result := 0;

while P <> nil do
 begin
  P := P.Prev;
  Inc(Result);
 end;
end;

class procedure TDeltaFuncs.ReverseLinks(var P: PDeltaLinkedField);
var
 L, P2, P3: PDeltaLinkedField;
begin
L := nil;
P2 := P;
while P2 <> nil do
 begin
  P3 := P2.Prev;
  P2.Prev := L;
  L := P2;
  P2 := P3;
 end;

P := L;
end;

class procedure TDeltaFuncs.ClearLinks(var P: PDeltaLinkedField);
var
 P2, P3: PDeltaLinkedField;
begin
P2 := P;
while P2 <> nil do
 begin
  P3 := P2.Prev;
  Mem_Free(P2.Field);
  Mem_Free(P2);
  P2 := P3;
 end;

P := nil;
end;

class function TDeltaFuncs.BuildFromLinks(var LF: PDeltaLinkedField): PDelta;
var
 D: PDelta;
 I: Int;
 P: PDeltaLinkedField;
begin
D := Mem_ZeroAlloc(SizeOf(TDelta));
TDelta.ReverseLinks(LF);
D.NumFields := TDelta.CountLinks(LF);
D.Fields := Mem_ZeroAlloc(D.NumFields * SizeOf(TDeltaField));

P := LF;
for I := 0 to D.NumFields - 1 do
 begin
  Move(P.Field^, D.Fields[I], SizeOf(TDeltaField));
  P := P.Prev;
 end;

TDelta.ClearLinks(LF);
D.Active := True;
Result := D;
end;

class function TDeltaFuncs.FindOffset(Count: UInt; Base: PDeltaOffsetArray; Name: PLChar): UInt32;
var
 I: Int;
begin
for I := 0 to Count - 1 do
 if StrIComp(Name, Base[I].Name) = 0 then
  begin
   Result := Base[I].Offset;
   Exit;
  end;

Sys_Error(['Delta_FindOffset: Couldn''t find offset for "', Name, '".']);
Result := 0;
end;

class function TDeltaFuncs.ParseType(var FieldType: UInt32; var F: Pointer): Boolean;
begin
while True do
 begin
  repeat
   F := COM_Parse(F);
   if COM_Token[Low(COM_Token)] = #0 then
    begin
     Print('Delta_ParseType: Expecting fieldtype info.');
     Result := False;
     Exit;
    end;
  until StrComp(@COM_Token, '|') <> 0;

  if StrComp(@COM_Token, ',') = 0 then
   Break;

  if StrIComp(@COM_Token, 'DT_SIGNED') = 0 then
   FieldType := FieldType or UInt32(DT_SIGNED)
  else
   if StrIComp(@COM_Token, 'DT_BYTE') = 0 then
    FieldType := FieldType or DT_BYTE
   else
    if StrIComp(@COM_Token, 'DT_SHORT') = 0 then
     FieldType := FieldType or DT_SHORT
    else
     if StrIComp(@COM_Token, 'DT_FLOAT') = 0 then
      FieldType := FieldType or DT_FLOAT
     else
      if StrIComp(@COM_Token, 'DT_INTEGER') = 0 then
       FieldType := FieldType or DT_INTEGER
      else
       if StrIComp(@COM_Token, 'DT_ANGLE') = 0 then
        FieldType := FieldType or DT_ANGLE
       else
        if StrIComp(@COM_Token, 'DT_TIMEWINDOW_8') = 0 then
         FieldType := FieldType or DT_TIMEWINDOW_8
        else
         if StrIComp(@COM_Token, 'DT_TIMEWINDOW_BIG') = 0 then
          FieldType := FieldType or DT_TIMEWINDOW_BIG
         else
          if StrIComp(@COM_Token, 'DT_STRING') = 0 then
           FieldType := FieldType or DT_STRING
          else
           Sys_Error(['Delta_ParseField: Unknown token "', PLChar(@COM_Token), '".']);
 end;

Result := True;
end;

class function TDeltaFuncs.ParseField(Count: UInt; Base: PDeltaOffsetArray; LF: PDeltaLinkedField; var F: Pointer): Boolean;
var
 Post: Boolean;
 DF: PDeltaField;
begin
if StrIComp(@COM_Token, 'DEFINE_DELTA') <> 0 then
 begin
  if StrIComp(@COM_Token, 'DEFINE_DELTA_POST') <> 0 then
   Sys_Error(['Delta_ParseField: Expecting DEFINE_*, got "', PLChar(@COM_Token), '".']);
  Post := True;
 end
else
 Post := False;

F := COM_Parse(F);
if StrComp(@COM_Token, '(') <> 0 then
 Sys_Error(['Delta_ParseField: Expecting "(", got "', PLChar(@COM_Token), '".']);

F := COM_Parse(F);
if COM_Token[Low(COM_Token)] = #0 then
 Sys_Error('Delta_ParseField: Expecting fieldname.');

DF := LF.Field;
StrLCopy(@DF.Name, @COM_Token, SizeOf(DF.Name) - 1);
DF.Offset := TDelta.FindOffset(Count, Base, @COM_Token);

F := COM_Parse(F);
if TDelta.ParseType(DF.FieldType, F) then
 begin
  F := COM_Parse(F);
  DF.FieldSize := 1;
  DF.Bits := StrToInt(@COM_Token);
  F := COM_Parse(F);
  F := COM_Parse(F);
  DF.Scale := StrToFloatDef(PLChar(@COM_Token), 0);
  if DF.Scale = 0 then
   Sys_Error('Delta_ParseField: Bad scale specified.');

  if Post then
   begin
    F := COM_Parse(F);
    F := COM_Parse(F);
    DF.PScale := StrToFloatDef(PLChar(@COM_Token), 0);
   end
  else
   DF.PScale := 1;

  DF.TotalScale := DF.PScale / DF.Scale;

  F := COM_Parse(F);
  if StrComp(@COM_Token, ')') <> 0 then
   Sys_Error(['Delta_ParseField: Expecting ")", got "', PLChar(@COM_Token), '".'])
  else
   begin
    F := COM_Parse(F);
    if StrComp(@COM_Token, ',') <> 0 then
     COM_UngetToken;
   end;

  Result := True;
 end
else
 Result := False;
end;

class procedure TDeltaFuncs.FreeDescription(var D: PDelta);
begin
if D <> nil then
 begin
  if D.Active and (D.Fields <> nil) then
   Mem_Free(D.Fields);
  Mem_Free(D);
  D := nil;
 end;
end;

class function TDeltaFuncs.FindDefinition(Name: PLChar; out Count: UInt): PDeltaOffsetArray;
var
 P: PDeltaDefinition;
begin
P := DefList;
while P <> nil do
 if StrIComp(Name, P.Name) = 0 then
  begin
   Result := P.Offsets;
   Count := P.Count;
   Exit;
  end
 else
  P := P.Prev;

Result := nil;
Count := 0;
end;

class procedure TDeltaFuncs.AddDefinition(Name: PLChar; Data: PDeltaOffsetArray; Count: UInt);
var
 D: PDeltaDefinition;
begin
D := DefList;
while (D <> nil) and (StrIComp(Name, D.Name) <> 0) do
 D := D.Prev;

if D = nil then
 begin
  D := Mem_ZeroAlloc(SizeOf(D^));
  D.Prev := DefList;
  D.Name := Mem_StrDup(Name);
  DefList := D;
 end;

D.Count := Count;
D.Offsets := Data;
end;

class procedure TDeltaFuncs.ClearDefinitions;
var
 P, P2: PDeltaDefinition;
begin
P := DefList;
while P <> nil do
 begin
  P2 := P.Prev;
  Mem_Free(P.Name);
  Mem_Free(P);
  P := P2;
 end;

DefList := nil;
end;

class procedure TDeltaFuncs.SkipDescription(var F: Pointer);
begin
F := COM_Parse(F);
repeat
 F := COM_Parse(F);
 if COM_Token[Low(COM_Token)] = #0 then
  Sys_Error('Delta_SkipDescription: Error during description skip.');
until StrComp(@COM_Token, '}') = 0;
end;

class function TDeltaFuncs.ParseOneField(var F: Pointer; out LinkBase: PDeltaLinkedField; Count: UInt; Base: PDeltaOffsetArray): Boolean;
var
 X: TDeltaLinkedField;
 P: PDeltaLinkedField;
begin
Result := True;

while True do
 begin
  if StrComp(@COM_Token, '}') = 0 then
   begin
    COM_UngetToken;
    Exit;
   end;

  F := COM_Parse(F);
  if COM_Token[Low(COM_Token)] = #0 then
   Exit;

  X.Prev := nil;
  X.Field := Mem_ZeroAlloc(SizeOf(X.Field^));
  if not TDelta.ParseField(Count, Base, @X, F) then
   Break;

  P := Mem_ZeroAlloc(SizeOf(P^));
  P.Field := X.Field;
  P.Prev := LinkBase;
  LinkBase := P;
 end;

Result := False;
end;

class function TDeltaFuncs.ParseDescription(Name: PLChar; var Delta: PDelta; F: Pointer): Boolean;
var
 Def: PDeltaOffsetArray;
 DefCount: UInt;
 LinkBase: PDeltaLinkedField;
 Encoder: array[1..32] of LChar;
begin
if @Delta = nil then
 Sys_Error('Delta_ParseDescription: Invalid description.')
else
 if F = nil then
  Sys_Error('Delta_ParseDescription called with no data stream.');

LinkBase := nil;
Delta := nil;
Encoder[Low(Encoder)] := #0;

while True do
 begin
  F := COM_Parse(F);
  if COM_Token[Low(COM_Token)] = #0 then
   Break
  else
   if StrIComp(@COM_Token, Name) <> 0 then
    TDelta.SkipDescription(F)
   else
    begin
     Def := TDelta.FindDefinition(@COM_Token, DefCount);
     if Def = nil then
      Sys_Error(['Delta_ParseDescription: Unknown data type - "', PLChar(@COM_Token), '".']);

     F := COM_Parse(F);
     if COM_Token[Low(COM_Token)] = #0 then
      Sys_Error('Delta_ParseDescription: Unknown encoder. Valid values are:' + sLineBreak +
                'none,' + sLineBreak + 'gamedll funcname,' + sLineBreak + 'clientdll funcname')
     else
      if StrIComp(@COM_Token, 'none') <> 0 then
       begin
        F := COM_Parse(F);
        if COM_Token[Low(COM_Token)] = #0 then
         Sys_Error('Delta_ParseDescription: Expecting encoder.');

        StrLCopy(@Encoder, @COM_Token, SizeOf(Encoder) - 1);
       end;

     while True do
      begin
       F := COM_Parse(F);
       if (COM_Token[Low(COM_Token)] = #0) or (StrComp(@COM_Token, '}') = 0) then
        Break
       else
        if StrComp(@COM_Token, '{') <> 0 then
         begin
          Print(['Delta_ParseDescription: Expecting "{", got "', PLChar(@COM_Token), '".']);
          Result := False;
          Exit;
         end
        else
         if not TDelta.ParseOneField(F, LinkBase, DefCount, Def) then
          begin
           Result := False;
           Exit;
          end;
      end;
    end;
 end;

Delta := TDelta.BuildFromLinks(LinkBase);
if Encoder[Low(Encoder)] > #0 then
 begin
  StrCopy(@Delta.Name, @Encoder);
  Delta.ConditionalEncoder := nil;
 end;

Result := True;
end;

class function TDeltaFuncs.Load(Name: PLChar; var Delta: PDelta; FileName: PLChar): Boolean;
var
 P: Pointer;
begin
P := COM_LoadFile(FileName, FILE_ALLOC_MEMORY, nil);
if P = nil then
 begin
  Sys_Error(['Delta_Load: Couldn''t load file "', FileName, '".']);
  Result := False;
 end
else
 begin
  Result := TDelta.ParseDescription(Name, Delta, P);
  COM_FreeFile(P);
 end;
end;

class function TDeltaFuncs.LookupRegistration(Name: PLChar): PDelta;
var
 P: PDeltaReg;
begin
P := RegList;
while P <> nil do
 if StrIComp(P.Name, Name) = 0 then
  begin
   Result := P.Delta;
   Exit;
  end
 else
  P := P.Prev;

Result := nil;
end;

class function TDeltaFuncs.Register(Name, FileName: PLChar): PDelta;
var
 D: PDelta;
 P: PDeltaReg;
begin
if not TDelta.Load(Name, D, FileName) then
 Sys_Error(['Delta_Register: Error parsing "', Name, '" in "', FileName, '".']);

P := Mem_Alloc(SizeOf(P^));
P.Prev := RegList;
P.Name := Mem_StrDup(Name);
P.FileName := Mem_StrDup(FileName);
P.Delta := D;
RegList := P;
Result := D;
end;

class procedure TDeltaFuncs.InitEncoders;
var
 P: PDeltaReg;
 D: PDelta;
begin
P := RegList;
while P <> nil do
 begin
  D := P.Delta;
  if D.Name[Low(D.Name)] > #0 then
   D.ConditionalEncoder := TDelta.LookupEncoder(@D.Name);

  P := P.Prev;
 end;
end;

class procedure TDeltaFuncs.ClearRegistrations;
var
 P, P2: PDeltaReg;
begin
P := RegList;
while P <> nil do
 begin
  P2 := P.Prev;
  if P.Delta <> nil then
   TDelta.FreeDescription(P.Delta);

  Mem_Free(P.Name);
  Mem_Free(P.FileName);
  Mem_Free(P);
  P := P2;
 end;

RegList := nil;
end;

class procedure TDeltaFuncs.ClearStats_F; cdecl;
var
 P: PDeltaReg;
 D: PDelta;
 I: Int;
begin
P := RegList;
while P <> nil do
 begin
  D := P.Delta;
  if D <> nil then
   for I := 0 to D.NumFields - 1 do
    begin
     D.Fields[I].SendCount := 0;
     D.Fields[I].RecvCount := 0;
    end;

  P := P.Prev;
 end;

Print('Delta stats cleared.');
end;

class procedure TDeltaFuncs.DumpStats_F; cdecl;
var
 P: PDeltaReg;
 D: PDelta;
 F: PDeltaField;
 I: Int;
 S: PLChar;
 L: UInt;
begin
if Cmd_Argc = 2 then
 begin
  S := Cmd_Argv(1);
  L := StrLen(S);
 end
else
 begin
  S := nil;
  L := 0;
 end;

P := RegList;
while P <> nil do
 begin
  D := P.Delta;
  if (D <> nil) and ((S = nil) or (StrLComp(P.Name, S, L) = 0)) then
   begin
    Print(['Stats for "', P.Name, '":']);
    for I := 0 to D.NumFields - 1 do
     begin
      F := @D.Fields[I];
      Print(['#', I + 1, ' (', PLChar(@F.Name), '): send ', F.SendCount, ' recv ', F.RecvCount]);
     end;
    Print('');
   end;
  
  P := P.Prev;
 end;
end;

class procedure TDeltaFuncs.Init;
begin
  Cmd_AddCommand('delta_stats', @TDelta.DumpStats_F);
  Cmd_AddCommand('delta_clear', @TDelta.ClearStats_F);
  TDelta.AddDefinition('clientdata_t', @DT_ClientData_T, High(DT_ClientData_T));
  TDelta.AddDefinition('weapon_data_t', @DT_WeaponData_T, High(DT_WeaponData_T));
  TDelta.AddDefinition('usercmd_t', @DT_UserCmd_T, High(DT_UserCmd_T));
  TDelta.AddDefinition('entity_state_t', @DT_EntityState_T, High(DT_EntityState_T));
  TDelta.AddDefinition('entity_state_player_t', @DT_EntityState_T, High(DT_EntityState_T));
  TDelta.AddDefinition('custom_entity_state_t', @DT_EntityState_T, High(DT_EntityState_T));
  TDelta.AddDefinition('event_t', @DT_Event_T, High(DT_Event_T));
end;

class procedure TDeltaFuncs.Shutdown;
begin
  TDelta.ClearEncoders;
  TDelta.ClearDefinitions;
  TDelta.ClearRegistrations;
end;

end.
