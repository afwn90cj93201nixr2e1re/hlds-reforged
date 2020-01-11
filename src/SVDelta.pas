unit SVDelta;

interface

uses Default, SDK, Client, Delta, SizeBuf;

procedure SV_InitDeltas;
procedure SV_WriteDeltaDescriptionsToClient(var SB: TSizeBuf);

procedure SV_ParseDelta(var C: TClient);

var
 PlayerDelta, EntityDelta, CustomEntityDelta, ClientDelta, WeaponDelta, EventDelta, UserCmdDelta: PDelta;

implementation

uses Console, Host, Memory, MsgBuf, SysMain, Network;

const
 MetaDeltaDescription: array[1..7] of TDeltaField =
  ((FieldType: DT_INTEGER; Name: ('f', 'i', 'e', 'l', 'd', 'T', 'y', 'p', 'e', #0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0);
    Offset: 0; FieldSize: 1; Bits: 32; Scale: 1; PScale: 1; Flags: []; SendCount: 0; RecvCount: 0),
   (FieldType: DT_STRING;  Name: ('f', 'i', 'e', 'l', 'd', 'N', 'a', 'm', 'e', #0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0);
    Offset: 4; FieldSize: 1; Bits: 1; Scale: 1; PScale: 1; Flags: []; SendCount: 0; RecvCount: 0),
   (FieldType: DT_INTEGER; Name: ('f', 'i', 'e', 'l', 'd', 'O', 'f', 'f', 's', 'e', 't', #0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0);
    Offset: 36; FieldSize: 1; Bits: 16; Scale: 1; PScale: 1; Flags: []; SendCount: 0; RecvCount: 0),
   (FieldType: DT_INTEGER; Name: ('f', 'i', 'e', 'l', 'd', 'S', 'i', 'z', 'e', #0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0);
    Offset: 40; FieldSize: 1; Bits: 8; Scale: 1; PScale: 1; Flags: []; SendCount: 0; RecvCount: 0),
   (FieldType: DT_INTEGER; Name: ('s', 'i', 'g', 'n', 'i', 'f', 'i', 'c', 'a', 'n', 't', '_', 'b', 'i', 't', 's', #0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0);
    Offset: 44; FieldSize: 1; Bits: 8; Scale: 1; PScale: 1; Flags: []; SendCount: 0; RecvCount: 0),
   (FieldType: DT_FLOAT;   Name: ('p', 'r', 'e', 'm', 'u', 'l', 't', 'i', 'p', 'l', 'y', #0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0);
    Offset: 48; FieldSize: 1; Bits: 32; Scale: 4000; PScale: 1; Flags: []; SendCount: 0; RecvCount: 0),
   (FieldType: DT_FLOAT;   Name: ('p', 'o', 's', 't', 'm', 'u', 'l', 't', 'i', 'p', 'l', 'y', #0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0,#0);
    Offset: 52; FieldSize: 1; Bits: 32; Scale: 4000; PScale: 1; Flags: []; SendCount: 0; RecvCount: 0));

var
 MetaDelta: TDelta = (Active: False; NumFields: 7; ConditionalEncoder: nil; Fields: @MetaDeltaDescription);

procedure SV_InitDeltas;
begin
ClientDelta := TDelta.Register('clientdata_t', 'delta.lst');
EntityDelta := TDelta.Register('entity_state_t', 'delta.lst');
PlayerDelta := TDelta.Register('entity_state_player_t', 'delta.lst');
CustomEntityDelta := TDelta.Register('custom_entity_state_t', 'delta.lst');
UserCmdDelta := TDelta.Register('usercmd_t', 'delta.lst');
WeaponDelta := TDelta.Register('weapon_data_t', 'delta.lst');
EventDelta := TDelta.Register('event_t', 'delta.lst');
DPrint('Delta descriptions initialized.');
end;

procedure SV_WriteDeltaDescriptionsToClient(var SB: TSizeBuf);
var
 OS: TDeltaField;
 P: PDeltaReg;
 I: Int;
begin
MemSet(OS, SizeOf(OS), 0);
P := RegList;
while P <> nil do
 begin
  SB.Write<UInt8>(SVC_DELTADESCRIPTION);
  SB.WriteString(P.Name);
  SB.StartBitWriting;
  SB.WriteBits(P.Delta.NumFields, 16);
  for I := 0 to P.Delta.NumFields - 1 do
   MetaDelta.WriteDelta(SB, @OS, @P.Delta.Fields[I], True, nil);
  SB.EndBitWriting;

  P := P.Prev;
 end;
end;

procedure SV_ParseDelta(var C: TClient);
begin
C.UpdateMask := gNetMessage.ReadByte;
if gNetMessage.BadRead then
 C.UpdateMask := -1;
end;

end.
