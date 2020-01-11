unit SizeBuf;

interface

uses
  Default, MathLib;

type
  PSizeBuf = ^TSizeBuf;
  TSizeBuf = record
  public
    BFWrite: record
      Count: UInt;
      Data: Pointer;
      Active: Boolean;
    end;

    BFRead: record
      CurrentSize: UInt;
      ReadCount: UInt; // +8, not used
      ByteCount: UInt; // +12
      BitCount: UInt; // +16
      Data: Pointer; // +20
      Active: Boolean;
    end;

  public
    ReadCount: UInt;
    BadRead: Boolean;

  public
    Data: Pointer;
    MaxSize: UInt32;
    CurrentSize: UInt32;
    AllowOverflow: Boolean;
    Overflowed: Boolean;

  public
    procedure Alloc(AName: PLChar; ASize: UInt);
    procedure Clear;
    function GetSpace(Length: UInt): Pointer;
    procedure Write(AData: Pointer; ASize: UInt); overload;
    procedure Write<T>(Value: T); overload;
    procedure WriteString(S: PLChar);
    procedure WriteAngle(F: Single);
    procedure WriteHiResAngle(F: Single);
    procedure WriteCoord(F: Single);

  public
    procedure StartBitWriting;
    procedure WriteOneBit(B: Byte);
    function IsBitWriting: Boolean;
    procedure EndBitWriting;
    procedure WriteBits(B: UInt32; Count: UInt);
    procedure WriteSBits(B: Int32; Count: UInt);
    procedure WriteBitString(S: PLChar);
    procedure WriteBitData(Buffer: Pointer; Size: UInt);
    procedure WriteBitAngle(F: Single; Count: UInt);
    procedure WriteBitCoord(F: Single);
    procedure WriteBitVec3Coord(const P: TVec3);
    procedure WriteVec3Coord(const P: TVec3);

  public
    procedure StartBitReading;
    procedure EndBitReading;
    function ReadOneBit: Int32;
    function ReadBits(Count: UInt): UInt32;
    function ReadSBits(Count: UInt): Int32;
    function ReadBitAngle(Count: UInt): Single;
    function CurrentBit: UInt;
    function IsBitReading: Boolean;
    function ReadBitString: PLChar;
    procedure ReadBitData(Buffer: Pointer; Size: UInt);
    function ReadBitCoord: Single;
    procedure ReadBitVec3Coord(out P: TVec3);
    procedure ReadVec3Coord(out P: TVec3);

  public
    function ReadCoord: Single;
    procedure BeginReading;
    function Read(Buffer: Pointer; Size: UInt): Int32; overload;
    function Read<T>: T; overload;
    function ReadString: PLChar;
    function ReadStringLine: PLChar;
    function ReadAngle: Single;
    function ReadHiResAngle: Single;
  end;

implementation

uses
  Memory, SysMain, Console, Common;

const
 InvBitTable: array[0..32] of Int32 =
  (-(1 shl 0) - 1, -(1 shl 1) - 1, -(1 shl 2) - 1, -(1 shl 3) - 1,
  -(1 shl 4) - 1, -(1 shl 5) - 1, -(1 shl 6) - 1, -(1 shl 7) - 1,
  -(1 shl 8) - 1, -(1 shl 9) - 1, -(1 shl 10) - 1, -(1 shl 11) - 1,
  -(1 shl 12) - 1, -(1 shl 13) - 1, -(1 shl 14) - 1, -(1 shl 15) - 1,
  -(1 shl 16) - 1, -(1 shl 17) - 1, -(1 shl 18) - 1, -(1 shl 19) - 1,
  -(1 shl 20) - 1, -(1 shl 21) - 1, -(1 shl 22) - 1, -(1 shl 23) - 1,
  -(1 shl 24) - 1, -(1 shl 25) - 1, -(1 shl 26) - 1, -(1 shl 27) - 1,
  -(1 shl 28) - 1, -(1 shl 29) - 1, -(1 shl 30) - 1, $80000000 - 1,
  -1);

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

procedure TSizeBuf.Alloc(AName: PLChar; ASize: UInt);
begin
if ASize < 32 then
 ASize := 32;

AllowOverflow := False;
Overflowed := False;
Data := Hunk_AllocName(ASize, AName);
MaxSize := ASize;
CurrentSize := 0;
end;

procedure TSizeBuf.Clear;
begin
CurrentSize := 0;
Overflowed := False;
end;

function TSizeBuf.GetSpace(Length: UInt): Pointer;
var
 P: PLChar;
begin
if CurrentSize + Length > MaxSize then
 begin
   P := '???';

  if not AllowOverflow then
   if MaxSize >= 1 then
    Sys_Error(['SZ_GetSpace: Overflow without FSB_ALLOWOVERFLOW set on "', P, '".'])
   else
    Sys_Error(['SZ_GetSpace: Tried to write to an uninitialized sizebuf: "', P, '".']);

  if Length > MaxSize then
   if AllowOverflow then
    DPrint(['SZ_GetSpace: ', Length ,' is > full buffer size on "', P, '", ignoring.'])
   else
    Sys_Error(['SZ_GetSpace: ', Length ,' is > full buffer size on "', P, '".']);

  DPrint(['SZ_GetSpace: overflow on "', P , '".']);
  CurrentSize := 0;
  Overflowed := True;
 end;

Result := Pointer(UInt(Data) + CurrentSize);
Inc(CurrentSize, Length);
end;

procedure TSizeBuf.Write(AData: Pointer; ASize: UInt);
begin
if (AData <> nil) and (ASize > 0) then
 Move(AData^, GetSpace(ASize)^, ASize);
end;

procedure TSizeBuf.Write<T>(Value: T);
begin
  Write(@Value, SizeOf(T));
end;

procedure TSizeBuf.WriteString(S: PLChar);
begin
if S <> nil then
 Write(S, StrLen(S) + 1)
else
 Write(EmptyString, 1)
end;

procedure TSizeBuf.WriteAngle(F: Single);
begin
  Write<UInt8>(Trunc(F * 256 / 360));
end;

procedure TSizeBuf.WriteHiResAngle(F: Single);
begin
  Write<Int16>(Trunc(F * 65536 / 360));
end;

procedure TSizeBuf.WriteCoord(F: Single);
begin
  Write<Int16>(Trunc(F * 8));
end;

procedure TSizeBuf.StartBitWriting;
begin
  BFWrite.Count := 0;
  BFWrite.Data := Pointer(UInt(Data) + CurrentSize);
  BFWrite.Active := True;
end;

procedure TSizeBuf.WriteOneBit(B: Byte);
begin
if BFWrite.Count >= 8 then
 begin
  GetSpace(1);
  BFWrite.Count := 0;
  Inc(UInt(BFWrite.Data));
 end;

if not Overflowed then
 begin
  if B = 0 then
   PByte(BFWrite.Data)^ := PByte(BFWrite.Data)^ and InvBitTable[BFWrite.Count]
  else
   PByte(BFWrite.Data)^ := PByte(BFWrite.Data)^ or BitTable[BFWrite.Count];

  Inc(BFWrite.Count);
 end;
end;

function TSizeBuf.IsBitWriting: Boolean;
begin
Result := BFWrite.Active;
end;

procedure TSizeBuf.EndBitWriting;
begin
if not Overflowed then
 begin
  PByte(BFWrite.Data)^ := PByte(BFWrite.Data)^ and (255 shr (8 - BFWrite.Count));
  GetSpace(1);
 end;
 BFWrite.Active := False;
end;

procedure TSizeBuf.WriteBits(B: UInt32; Count: UInt);
var
 BitMask: UInt32;
 BitCount, ByteCount, BitsLeft: UInt;
 NextRow: Boolean;
begin
if (Count <= 31) and (B >= 1 shl Count) then
 BitMask := RowBitTable[Count]
else
 BitMask := B;

if BFWrite.Count > 7 then
 begin
  NextRow := True;
  BFWrite.Count := 0;
  Inc(UInt(BFWrite.Data));
 end
else
 NextRow := False;

BitCount := Count + BFWrite.Count;
if BitCount <= 32 then
 begin
  ByteCount := BitCount shr 3;
  BitCount := BitCount and 7;
  if BitCount = 0 then
   Dec(ByteCount);

  GetSpace(ByteCount + UInt32(NextRow));
  PUInt32(BFWrite.Data)^ := (PUInt32(BFWrite.Data)^ and RowBitTable[BFWrite.Count]) or (BitMask shl BFWrite.Count);

  if BitCount > 0 then
   BFWrite.Count := BitCount
  else
   BFWrite.Count := 8;

  Inc(UInt(BFWrite.Data), ByteCount);
 end
else
 begin
  GetSpace(UInt32(NextRow) + 4);
  PUInt32(BFWrite.Data)^ := (PUInt32(BFWrite.Data)^ and RowBitTable[BFWrite.Count]) or (BitMask shl BFWrite.Count);

  BitsLeft := 32 - BFWrite.Count;
  BFWrite.Count := BitCount and 7;
  Inc(UInt(BFWrite.Data), 4);

  PUInt32(BFWrite.Data)^ := BitMask shr BitsLeft;
 end;
end;

procedure TSizeBuf.WriteSBits(B: Int32; Count: UInt);
var
 I: Int32;
begin
if Count < 32 then
 begin
  I := (1 shl (Count - 1)) - 1;
  if B > I then
   B := I
  else
   if B < -I then
    B := -I;
 end;

WriteOneBit(UInt(B < 0));
WriteBits(Abs(B), Count - 1);
end;

procedure TSizeBuf.WriteBitString(S: PLChar);
begin
while S^ > #0 do
 begin
  WriteBits(Byte(S^), 8);
  Inc(UInt(S));
 end;

WriteBits(0, 8);
end;

procedure TSizeBuf.WriteBitData(Buffer: Pointer; Size: UInt);
var
 I: Int;
begin
for I := 0 to Size - 1 do
 WriteBits(PByte(UInt(Buffer) + UInt(I))^, 8);
end;

procedure TSizeBuf.WriteBitAngle(F: Single; Count: UInt);
var
 B: UInt32;
begin
if Count >= 32 then
 Sys_Error('MSG_WriteBitAngle: Can''t write bit angle with 32 bits precision.');

B := 1 shl Count;
WriteBits((B - 1) and (Trunc(B * F) div 360), Count);
end;

procedure TSizeBuf.WriteBitCoord(F: Single);
var
 I, IntData, FracData: Int32;
begin
I := Trunc(F);
IntData := Abs(I);
FracData := Abs(8 * I) and 7;

WriteOneBit(UInt(IntData <> 0));
WriteOneBit(UInt(FracData <> 0));
if (IntData <> 0) or (FracData <> 0) then
 begin
  WriteOneBit(UInt(F <= -0.125));
  if IntData <> 0 then
   WriteBits(IntData, 12);
  if FracData <> 0 then
   WriteBits(FracData, 3);
 end;
end;

procedure TSizeBuf.WriteBitVec3Coord(const P: TVec3);
var
 X, Y, Z: Boolean;
begin
X := (P[0] >= 0.125) or (P[0] <= -0.125);
Y := (P[1] >= 0.125) or (P[1] <= -0.125);
Z := (P[2] >= 0.125) or (P[2] <= -0.125);

WriteOneBit(UInt(X));
WriteOneBit(UInt(Y));
WriteOneBit(UInt(Z));

if X then
 WriteBitCoord(P[0]);
if Y then
 WriteBitCoord(P[1]);
if Z then
 WriteBitCoord(P[2]);
end;

procedure TSizeBuf.WriteVec3Coord(const P: TVec3);
begin
if IsBitWriting then
  WriteBitVec3Coord(P)
else
 begin
  StartBitWriting;
  WriteBitVec3Coord(P);
  EndBitWriting;
 end;
end;

procedure TSizeBuf.StartBitReading;
begin
BFRead.Active := True;
BFRead.CurrentSize := ReadCount + 1;
BFRead.ReadCount := ReadCount;
BFRead.ByteCount := 0;
BFRead.BitCount := 0;
BFRead.Data := Pointer(UInt(Data) + ReadCount);

if BFRead.CurrentSize > CurrentSize then
 BadRead := True;
end;

procedure TSizeBuf.EndBitReading;
begin
if BFRead.CurrentSize > CurrentSize then
 BadRead := True;

ReadCount := BFRead.CurrentSize;
BFRead.Active := False;
BFRead.ReadCount := 0;
BFRead.ByteCount := 0;
BFRead.BitCount := 0;
BFRead.Data := nil;
end;

function TSizeBuf.ReadOneBit: Int32;
begin
if BadRead then
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

  if BFRead.CurrentSize > CurrentSize then
   begin
    BadRead := True;
    Result := 1;
   end
  else
   begin
    Result := UInt32((BitTable[BFRead.BitCount] and PByte(BFRead.Data)^) <> 0);
    Inc(BFRead.BitCount);
   end;
 end;
end;

function TSizeBuf.ReadBits(Count: UInt): UInt32;
var
 BitCount, ByteCount: UInt;
 B: UInt32;
begin
if BadRead then
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

  if BFRead.CurrentSize > CurrentSize then
   begin
    BadRead := True;
    Result := 1;
   end;
 end;
end;

function TSizeBuf.ReadSBits(Count: UInt): Int32;
var
 B: Int32;
begin
if Count = 0 then
 Sys_Error('MSG_ReadSBits: Invalid bit count.');

B := ReadOneBit;
Result := ReadBits(Count - 1);
if B >= 1 then
 Result := -Result;
end;

function TSizeBuf.ReadBitAngle(Count: UInt): Single;
var
 X: UInt;
begin
X := 1 shl Count;
if X > 0 then
 Result := ReadBits(Count) * 360 / X
else
 begin
  ReadBits(Count);
  Result := 0;
 end;
end;

function TSizeBuf.CurrentBit: UInt32;
begin
if BFRead.Active then
 Result := BFRead.BitCount + (BFRead.ByteCount shl 3)
else
 Result := ReadCount shl 3;
end;

function TSizeBuf.IsBitReading: Boolean;
begin
Result := BFRead.Active;
end;

function TSizeBuf.ReadBitString: PLChar;
var
 B: UInt32;
 I: UInt;
begin
BitReadBuffer[Low(BitReadBuffer)] := #0;
for I := Low(BitReadBuffer) to High(BitReadBuffer) - 1 do
 begin
  B := ReadBits(8);
  if (B = 0) or BadRead then
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


procedure TSizeBuf.ReadBitData(Buffer: Pointer; Size: UInt);
var
 I: Int;
begin
for I := 0 to Size - 1 do
 PByte(UInt(Buffer) + UInt(I))^ := ReadBits(8);
end;

function TSizeBuf.ReadBitCoord: Single;
var
 IntData, FracData: Int32;
 SignBit: Boolean;
begin
IntData := ReadOneBit;
FracData := ReadOneBit;

if (IntData <> 0) or (FracData <> 0) then
 begin
  SignBit := ReadOneBit <> 0;
  if IntData <> 0 then
   IntData := ReadBits(12);
  if FracData <> 0 then
   FracData := ReadBits(3);

  Result := FracData * 0.125 + IntData;
  if SignBit then
   Result := -Result;
 end
else
 Result := 0;
end;

procedure TSizeBuf.ReadBitVec3Coord(out P: TVec3);
var
 X, Y, Z: Boolean;
begin
X := ReadOneBit <> 0;
Y := ReadOneBit <> 0;
Z := ReadOneBit <> 0;

if X then
 P[0] := ReadBitCoord
else
 P[0] := 0;

if Y then
 P[1] := ReadBitCoord
else
 P[1] := 0;

if Z then
 P[2] := ReadBitCoord
else
 P[2] := 0;
end;

procedure TSizeBuf.ReadVec3Coord(out P: TVec3);
begin
if IsBitReading then
 ReadBitVec3Coord(P)
else
 begin
  StartBitReading;
  ReadBitVec3Coord(P);
  EndBitReading;
 end;
end;

function TSizeBuf.ReadCoord: Single;
begin
Result := Read<Int16> / 8;
end;

procedure TSizeBuf.BeginReading;
begin
ReadCount := 0;
BadRead := False;
end;

function TSizeBuf.Read(Buffer: Pointer; Size: UInt): Int32;
begin
if ReadCount + Size > CurrentSize then
 begin
  BadRead := True;
  Result := -1;
 end
else
 begin
  Move(Pointer(UInt(Data) + ReadCount)^, Buffer^, Size);
  Inc(ReadCount, Size);
  Result := 1;
 end;
end;

function TSizeBuf.Read<T>: T;
begin
  Result := System.Default(T);
  Read(@Result, SizeOf(T));
end;

function TSizeBuf.ReadString: PLChar;
var
 I: UInt;
 C: LChar;
begin
for I := Low(StringBuffer) to High(StringBuffer) - 1 do
 begin
  C := Read<LChar>;
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

function TSizeBuf.ReadStringLine: PLChar;
var
 I: UInt;
 C: LChar;
begin
Result := @StringLineBuffer;

for I := Low(StringLineBuffer) to High(StringLineBuffer) - 1 do
 begin
  C := Read<LChar>;
  if (C = #0) or (C = #$A) or (C = #$FF) then
   begin
    BadRead := False;
    StringLineBuffer[I] := #0;
    Exit;
   end
  else
   StringLineBuffer[I] := C;
 end;

StringLineBuffer[High(StringLineBuffer)] := #0;
end;

function TSizeBuf.ReadAngle: Single;
begin
Result := Read<UInt8> * (360 / 256);
end;

function TSizeBuf.ReadHiResAngle: Single;
begin
Result := Read<Int16> * (360 / 65536);
end;

end.
