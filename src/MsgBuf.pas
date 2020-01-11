unit MsgBuf;

interface

uses
  Default, SDK, SizeBuf, MathLib;

function MSG_ReadCoord: Single;
procedure MSG_BeginReading;
function MSG_ReadChar: LChar;
function MSG_ReadByte: Byte;
function MSG_ReadShort: Int16;
function MSG_ReadWord: UInt16;
function MSG_ReadLong: Int32;
function MSG_ReadFloat: Single;
function MSG_ReadBuffer(Size: UInt; Buffer: Pointer): Int32;
function MSG_ReadString: PLChar;
function MSG_ReadStringLine: PLChar;
function MSG_ReadAngle: Single;
function MSG_ReadHiResAngle: Single;
procedure MSG_ReadUserCmd(Dest, Source: PUserCmd);

implementation

uses Common, Delta, Memory, Network, SVDelta, SysMain;

var
 StringBuffer: array[1..8192] of LChar;
 StringLineBuffer: array[1..2048] of LChar;



function MSG_ReadCoord: Single;
begin
Result := MSG_ReadShort / 8;
end;

procedure MSG_BeginReading;
begin
gNetMessage.ReadCount := 0;
gNetMessage.BadRead := False;
end;

function MSG_ReadChar: LChar;
begin
if gNetMessage.ReadCount + SizeOf(Result) > gNetMessage.CurrentSize then
 begin
  gNetMessage.BadRead := True;
  Result := LChar(-1);
 end
else
 begin
  Result := PLChar(UInt(gNetMessage.Data) + gNetMessage.ReadCount)^;
  Inc(gNetMessage.ReadCount, SizeOf(Result));
 end;
end;

function MSG_ReadByte: Byte;
begin
if gNetMessage.ReadCount + SizeOf(Result) > gNetMessage.CurrentSize then
 begin
  gNetMessage.BadRead := True;
  Result := Byte(-1);
 end
else
 begin
  Result := PByte(UInt(gNetMessage.Data) + gNetMessage.ReadCount)^;
  Inc(gNetMessage.ReadCount, SizeOf(Result));
 end;
end;

function MSG_ReadShort: Int16;
begin
if gNetMessage.ReadCount + SizeOf(Result) > gNetMessage.CurrentSize then
 begin
  gNetMessage.BadRead := True;
  Result := -1;
 end
else
 begin
  Result := LittleShort(PInt16(UInt(gNetMessage.Data) + gNetMessage.ReadCount)^);
  Inc(gNetMessage.ReadCount, SizeOf(Result));
 end;
end;

function MSG_ReadWord: UInt16;
begin
if gNetMessage.ReadCount + SizeOf(Result) > gNetMessage.CurrentSize then
 begin
  gNetMessage.BadRead := True;
  Result := UInt16(-1);
 end
else
 begin
  Result := LittleShort(PUInt16(UInt(gNetMessage.Data) + gNetMessage.ReadCount)^);
  Inc(gNetMessage.ReadCount, SizeOf(Result));
 end;
end;

function MSG_ReadLong: Int32;
begin
if gNetMessage.ReadCount + SizeOf(Result) > gNetMessage.CurrentSize then
 begin
  gNetMessage.BadRead := True;
  Result := -1;
 end
else
 begin
  Result := LittleLong(PInt32(UInt(gNetMessage.Data) + gNetMessage.ReadCount)^);
  Inc(gNetMessage.ReadCount, SizeOf(Result));
 end;
end;

function MSG_ReadFloat: Single;
begin
if gNetMessage.ReadCount + SizeOf(Result) > gNetMessage.CurrentSize then
 begin
  gNetMessage.BadRead := True;
  Result := -1;
 end
else
 begin
  Result := LittleFloat(PSingle(UInt(gNetMessage.Data) + gNetMessage.ReadCount)^);
  Inc(gNetMessage.ReadCount, SizeOf(Result));
 end;
end;

function MSG_ReadBuffer(Size: UInt; Buffer: Pointer): Int32;
begin
if gNetMessage.ReadCount + Size > gNetMessage.CurrentSize then
 begin
  gNetMessage.BadRead := True;
  Result := -1;
 end
else
 begin
  Move(Pointer(UInt(gNetMessage.Data) + gNetMessage.ReadCount)^, Buffer^, Size);
  Inc(gNetMessage.ReadCount, Size);
  Result := 1;
 end;
end;

function MSG_ReadString: PLChar;
var
 I: UInt;
 C: LChar;
begin
for I := Low(StringBuffer) to High(StringBuffer) - 1 do
 begin
  C := MSG_ReadChar;
  if (C = #0) or (C = #$FF) then
   begin
    StringBuffer[I] := #0;
    Result := @StringBuffer;
    Exit;
   end
  else
   StringBuffer[I] := C;
 end;

StringBuffer[High(StringBuffer)] := #0;
Result := @StringBuffer;
end;

function MSG_ReadStringLine: PLChar;
var
 I: UInt;
 C: LChar;
begin
Result := @StringLineBuffer;

for I := Low(StringLineBuffer) to High(StringLineBuffer) - 1 do
 begin
  C := MSG_ReadChar;
  if (C = #0) or (C = #$A) or (C = #$FF) then
   begin
    gNetMessage.BadRead := False;
    StringLineBuffer[I] := #0;
    Exit;
   end
  else
   StringLineBuffer[I] := C;
 end;

StringLineBuffer[High(StringLineBuffer)] := #0;
end;

function MSG_ReadAngle: Single;
begin
Result := MSG_ReadByte * (360 / 256);
end;

function MSG_ReadHiResAngle: Single;
begin
Result := MSG_ReadShort * (360 / 65536);
end;

procedure MSG_ReadUserCmd(Dest, Source: PUserCmd);
begin
gNetMessage.StartBitReading;
UserCmdDelta.ParseDelta(gNetMessage, Source, Dest);
gNetMessage.EndBitReading;
COM_NormalizeAngles(Dest.ViewAngles);
end;

end.
