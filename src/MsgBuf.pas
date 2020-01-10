unit MsgBuf;

interface

uses
  Default, SDK, SizeBuf, MathLib;

function MSG_ReadBitAngle(Count: UInt): Single;
function MSG_CurrentBit: UInt;
function MSG_IsBitReading: Boolean;
procedure MSG_StartBitReading(var Buffer: TSizeBuf);
procedure MSG_EndBitReading(var Buffer: TSizeBuf);
function MSG_ReadOneBit: Int32;
function MSG_ReadBits(Count: UInt): UInt32;
function MSG_PeekBits(Count: UInt): UInt32;
function MSG_ReadSBits(Count: UInt): Int32;
function MSG_ReadBitString: PLChar;
procedure MSG_ReadBitData(Buffer: Pointer; Size: UInt);
function MSG_ReadBitCoord: Single;
procedure MSG_ReadBitVec3Coord(out P: TVec3);
function MSG_ReadCoord: Single;
procedure MSG_ReadVec3Coord(var Buffer: TSizeBuf; out P: TVec3);
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

var
 BFRead: record
  CurrentSize: UInt;
  Buffer: PSizeBuf; // +4
  ReadCount: UInt; // +8, not used
  ByteCount: UInt; // +12
  BitCount: UInt; // +16
  Data: Pointer; // +20
 end = ();

 MSG_ReadCount: UInt = 0;
 MSG_BadRead: Boolean = False;

implementation

uses Common, Delta, Memory, Network, SVDelta, SysMain;

const
 BitTable: array[0..32] of UInt32 =
           (1 shl 0, 1 shl 1, 1 shl 2, 1 shl 3,
            1 shl 4, 1 shl 5, 1 shl 6, 1 shl 7,
            1 shl 8, 1 shl 9, 1 shl 10, 1 shl 11,
            1 shl 12, 1 shl 13, 1 shl 14, 1 shl 15,
            1 shl 16, 1 shl 17, 1 shl 18, 1 shl 19,
            1 shl 20, 1 shl 21, 1 shl 22, 1 shl 23,
            1 shl 24, 1 shl 25, 1 shl 26, 1 shl 27,
            1 shl 28, 1 shl 29, 1 shl 30, $80000000,
            $00000000);

 RowBitTable: array[0..32] of UInt32 =
              (1 shl 0 - 1, 1 shl 1 - 1, 1 shl 2 - 1, 1 shl 3 - 1,
               1 shl 4 - 1, 1 shl 5 - 1, 1 shl 6 - 1, 1 shl 7 - 1,
               1 shl 8 - 1, 1 shl 9 - 1, 1 shl 10 - 1, 1 shl 11 - 1,
               1 shl 12 - 1, 1 shl 13 - 1, 1 shl 14 - 1, 1 shl 15 - 1,
               1 shl 16 - 1, 1 shl 17 - 1, 1 shl 18 - 1, 1 shl 19 - 1,
               1 shl 20 - 1, 1 shl 21 - 1, 1 shl 22 - 1, 1 shl 23 - 1,
               1 shl 24 - 1, 1 shl 25 - 1, 1 shl 26 - 1, 1 shl 27 - 1,
               1 shl 28 - 1, 1 shl 29 - 1, 1 shl 30 - 1, $80000000 - 1,
               $FFFFFFFF);


var
 BitReadBuffer: array[1..8192] of LChar;
 StringBuffer: array[1..8192] of LChar;
 StringLineBuffer: array[1..2048] of LChar;


function MSG_ReadBitAngle(Count: UInt): Single;
var
 X: UInt;
begin
X := 1 shl Count;
if X > 0 then
 Result := MSG_ReadBits(Count) * 360 / X
else
 begin
  MSG_ReadBits(Count);
  Result := 0;
 end;
end;

function MSG_CurrentBit: UInt32;
begin
if BFRead.Buffer <> nil then
 Result := BFRead.BitCount + (BFRead.ByteCount shl 3)
else
 Result := MSG_ReadCount shl 3;
end;

function MSG_IsBitReading: Boolean;
begin
Result := BFRead.Buffer <> nil;
end;

procedure MSG_StartBitReading(var Buffer: TSizeBuf);
begin
BFRead.CurrentSize := MSG_ReadCount + 1;
BFRead.Buffer := @Buffer;
BFRead.ReadCount := MSG_ReadCount;
BFRead.ByteCount := 0;
BFRead.BitCount := 0;
BFRead.Data := Pointer(UInt(Buffer.Data) + MSG_ReadCount);

if BFRead.CurrentSize > Buffer.CurrentSize then
 MSG_BadRead := True;
end;

procedure MSG_EndBitReading(var Buffer: TSizeBuf);
begin
if BFRead.CurrentSize > Buffer.CurrentSize then
 MSG_BadRead := True;

MSG_ReadCount := BFRead.CurrentSize;
BFRead.Buffer := nil;
BFRead.ReadCount := 0;
BFRead.ByteCount := 0;
BFRead.BitCount := 0;
BFRead.Data := nil;
end;

function MSG_ReadOneBit: Int32;
begin
if MSG_BadRead then
 Result := 1
else
 begin
  if BFRead.BitCount > 7 then
   begin
    Inc(BFRead.CurrentSize);
    Inc(BFRead.ByteCount);
    Inc(UInt(BFRead.Data));
    BFRead.BitCount := 0;
   end;

  if BFRead.CurrentSize > BFRead.Buffer.CurrentSize then
   begin
    MSG_BadRead := True;
    Result := 1;
   end
  else
   begin
    Result := UInt32((BitTable[BFRead.BitCount] and PByte(BFRead.Data)^) <> 0);
    Inc(BFRead.BitCount);
   end;
 end;
end;

function MSG_ReadBits(Count: UInt): UInt32;
var
 BitCount, ByteCount: UInt;
 B: UInt32;
begin
if MSG_BadRead then
 Result := 1
else
 begin
  if BFRead.BitCount > 7 then
   begin
    Inc(BFRead.CurrentSize);
    Inc(BFRead.ByteCount);
    Inc(UInt(BFRead.Data));
    BFRead.BitCount := 0;
   end;

  BitCount := BFRead.BitCount + Count;
  if BitCount <= 32 then
   begin
    Result := RowBitTable[Count] and (PUInt32(BFRead.Data)^ shr BFRead.BitCount);
    if (BitCount and 7) > 0 then
     begin
      BFRead.BitCount := BitCount and 7;
      ByteCount := BitCount shr 3;
     end
    else
     begin
      BFRead.BitCount := 8;
      ByteCount := (BitCount shr 3) - 1;
     end;

    Inc(BFRead.CurrentSize, ByteCount);
    Inc(BFRead.ByteCount, ByteCount);
    Inc(UInt(BFRead.Data), ByteCount);
   end
  else
   begin
    B := PUInt32(BFRead.Data)^ shr BFRead.BitCount;
    Inc(UInt(BFRead.Data), 4);
    Result := ((RowBitTable[BitCount and 7] and PUInt32(BFRead.Data)^) shl (32 - BFRead.BitCount)) or B;

    Inc(BFRead.CurrentSize, 4);
    Inc(BFRead.ByteCount, 4);
    BFRead.BitCount := BitCount and 7;
   end;

  if BFRead.CurrentSize > BFRead.Buffer.CurrentSize then
   begin
    MSG_BadRead := True;
    Result := 1;
   end;
 end;
end;

function MSG_PeekBits(Count: UInt): UInt32;
var
 Data: array[1..SizeOf(BFRead)] of Byte;
begin
Move(BFRead, Data, SizeOf(Data));
Result := MSG_ReadBits(Count);
Move(Data, BFRead, SizeOf(Data));
end;

function MSG_ReadSBits(Count: UInt): Int32;
var
 B: Int32;
begin
if Count = 0 then
 Sys_Error('MSG_ReadSBits: Invalid bit count.');

B := MSG_ReadOneBit;
Result := MSG_ReadBits(Count - 1);
if B >= 1 then
 Result := -Result;
end;

function MSG_ReadBitString: PLChar;
var
 B: UInt32;
 I: UInt;
begin
BitReadBuffer[Low(BitReadBuffer)] := #0;
for I := Low(BitReadBuffer) to High(BitReadBuffer) - 1 do
 begin
  B := MSG_ReadBits(8);
  if (B = 0) or MSG_BadRead then
   begin
    BitReadBuffer[I] := #0;
    Result := @BitReadBuffer;
    Exit;
   end
  else
   BitReadBuffer[I] := LChar(B);
 end;

BitReadBuffer[High(BitReadBuffer)] := #0;
Result := @BitReadBuffer;
end;

procedure MSG_ReadBitData(Buffer: Pointer; Size: UInt);
var
 I: Int;
begin
for I := 0 to Size - 1 do
 PByte(UInt(Buffer) + UInt(I))^ := MSG_ReadBits(8);
end;

function MSG_ReadBitCoord: Single;
var
 IntData, FracData: Int32;
 SignBit: Boolean;
begin
IntData := MSG_ReadOneBit;
FracData := MSG_ReadOneBit;

if (IntData <> 0) or (FracData <> 0) then
 begin
  SignBit := MSG_ReadOneBit <> 0;
  if IntData <> 0 then
   IntData := MSG_ReadBits(12);
  if FracData <> 0 then
   FracData := MSG_ReadBits(3);

  Result := FracData * 0.125 + IntData;
  if SignBit then
   Result := -Result;
 end
else
 Result := 0;
end;

procedure MSG_ReadBitVec3Coord(out P: TVec3);
var
 X, Y, Z: Boolean;
begin
X := MSG_ReadOneBit <> 0;
Y := MSG_ReadOneBit <> 0;
Z := MSG_ReadOneBit <> 0;

if X then
 P[0] := MSG_ReadBitCoord
else
 P[0] := 0;

if Y then
 P[1] := MSG_ReadBitCoord
else
 P[1] := 0;

if Z then
 P[2] := MSG_ReadBitCoord
else
 P[2] := 0;
end;

function MSG_ReadCoord: Single;
begin
Result := MSG_ReadShort / 8;
end;

procedure MSG_ReadVec3Coord(var Buffer: TSizeBuf; out P: TVec3);
begin
if MSG_IsBitReading then
 MSG_ReadBitVec3Coord(P)
else
 begin
  MSG_StartBitReading(Buffer);
  MSG_ReadBitVec3Coord(P);
  MSG_EndBitReading(Buffer);
 end;
end;

procedure MSG_BeginReading;
begin
MSG_ReadCount := 0;
MSG_BadRead := False;
end;

function MSG_ReadChar: LChar;
begin
if MSG_ReadCount + SizeOf(Result) > gNetMessage.CurrentSize then
 begin
  MSG_BadRead := True;
  Result := LChar(-1);
 end
else
 begin
  Result := PLChar(UInt(gNetMessage.Data) + MSG_ReadCount)^;
  Inc(MSG_ReadCount, SizeOf(Result));
 end;
end;

function MSG_ReadByte: Byte;
begin
if MSG_ReadCount + SizeOf(Result) > gNetMessage.CurrentSize then
 begin
  MSG_BadRead := True;
  Result := Byte(-1);
 end
else
 begin
  Result := PByte(UInt(gNetMessage.Data) + MSG_ReadCount)^;
  Inc(MSG_ReadCount, SizeOf(Result));
 end;
end;

function MSG_ReadShort: Int16;
begin
if MSG_ReadCount + SizeOf(Result) > gNetMessage.CurrentSize then
 begin
  MSG_BadRead := True;
  Result := -1;
 end
else
 begin
  Result := LittleShort(PInt16(UInt(gNetMessage.Data) + MSG_ReadCount)^);
  Inc(MSG_ReadCount, SizeOf(Result));
 end;
end;

function MSG_ReadWord: UInt16;
begin
if MSG_ReadCount + SizeOf(Result) > gNetMessage.CurrentSize then
 begin
  MSG_BadRead := True;
  Result := UInt16(-1);
 end
else
 begin
  Result := LittleShort(PUInt16(UInt(gNetMessage.Data) + MSG_ReadCount)^);
  Inc(MSG_ReadCount, SizeOf(Result));
 end;
end;

function MSG_ReadLong: Int32;
begin
if MSG_ReadCount + SizeOf(Result) > gNetMessage.CurrentSize then
 begin
  MSG_BadRead := True;
  Result := -1;
 end
else
 begin
  Result := LittleLong(PInt32(UInt(gNetMessage.Data) + MSG_ReadCount)^);
  Inc(MSG_ReadCount, SizeOf(Result));
 end;
end;

function MSG_ReadFloat: Single;
begin
if MSG_ReadCount + SizeOf(Result) > gNetMessage.CurrentSize then
 begin
  MSG_BadRead := True;
  Result := -1;
 end
else
 begin
  Result := LittleFloat(PSingle(UInt(gNetMessage.Data) + MSG_ReadCount)^);
  Inc(MSG_ReadCount, SizeOf(Result));
 end;
end;

function MSG_ReadBuffer(Size: UInt; Buffer: Pointer): Int32;
begin
if MSG_ReadCount + Size > gNetMessage.CurrentSize then
 begin
  MSG_BadRead := True;
  Result := -1;
 end
else
 begin
  Move(Pointer(UInt(gNetMessage.Data) + MSG_ReadCount)^, Buffer^, Size);
  Inc(MSG_ReadCount, Size);
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
    MSG_BadRead := False;
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
MSG_StartBitReading(gNetMessage);
UserCmdDelta.ParseDelta(Source, Dest);
MSG_EndBitReading(gNetMessage);
COM_NormalizeAngles(Dest.ViewAngles);
end;

initialization
 //MemSet(BFWrite, SizeOf(BFWrite), 0);
 MemSet(BFRead, SizeOf(BFRead), 0);

finalization

end.
