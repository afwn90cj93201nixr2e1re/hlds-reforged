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



end.
