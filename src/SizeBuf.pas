unit SizeBuf;

interface

uses
  Default;

type
  PSizeBuf = ^TSizeBuf;
  TSizeBuf = record
    Name: PLChar;
    AllowOverflow: set of (FSB_ALLOWOVERFLOW = 0, FSB_OVERFLOWED); // 16 bit boundary
    Data: Pointer;
    MaxSize: UInt32;
    CurrentSize: UInt32;

  public
    procedure Alloc(AName: PLChar; ASize: UInt);
    procedure Clear;
    function GetSpace(Length: UInt): Pointer;
    procedure Write(Data: Pointer; Length: UInt);

  public
    procedure WriteChar(Value: LChar);
    procedure WriteByte(Value: Byte);
    procedure WriteShort(Value: Int16);
    procedure WriteWord(Value: UInt16);
    procedure WriteLong(Value: Int32);
    procedure WriteFloat(Value: Single);
    procedure WriteString(S: PLChar);
    procedure WriteBuffer(Size: UInt; Data: Pointer);
    procedure WriteAngle(F: Single);
    procedure WriteHiResAngle(F: Single);
    procedure WriteCoord(F: Single);
  end;

implementation

uses
  Memory, SysMain, Console, Common;

procedure TSizeBuf.Alloc(AName: PLChar; ASize: UInt);
begin
if ASize < 32 then
 ASize := 32;

Name := AName;
AllowOverflow := [];
Data := Hunk_AllocName(ASize, Name);
MaxSize := ASize;
CurrentSize := 0;
end;

procedure TSizeBuf.Clear;
begin
CurrentSize := 0;
Exclude(AllowOverflow, FSB_OVERFLOWED);
end;

function TSizeBuf.GetSpace(Length: UInt): Pointer;
var
 P: PLChar;
begin
if CurrentSize + Length > MaxSize then
 begin
  if Name <> nil then
   P := Name
  else
   P := '???';

  if not (FSB_ALLOWOVERFLOW in AllowOverflow) then
   if MaxSize >= 1 then
    Sys_Error(['SZ_GetSpace: Overflow without FSB_ALLOWOVERFLOW set on "', P, '".'])
   else
    Sys_Error(['SZ_GetSpace: Tried to write to an uninitialized sizebuf: "', P, '".']);

  if Length > MaxSize then
   if FSB_ALLOWOVERFLOW in AllowOverflow then
    DPrint(['SZ_GetSpace: ', Length ,' is > full buffer size on "', P, '", ignoring.'])
   else
    Sys_Error(['SZ_GetSpace: ', Length ,' is > full buffer size on "', P, '".']);

  DPrint(['SZ_GetSpace: overflow on "', P , '".']);
  CurrentSize := 0;
  Include(AllowOverflow, FSB_OVERFLOWED);
 end;

Result := Pointer(UInt(Data) + CurrentSize);
Inc(CurrentSize, Length);
end;

procedure TSizeBuf.Write(Data: Pointer; Length: UInt);
begin
if (Data <> nil) and (Length > 0) then
 Move(Data^, GetSpace(Length)^, Length);
end;

procedure TSizeBuf.WriteChar(Value: LChar);
begin
PLChar(GetSpace(SizeOf(Value)))^ := Value;
end;

procedure TSizeBuf.WriteByte(Value: Byte);
begin
PByte(GetSpace(SizeOf(Value)))^ := Value;
end;

procedure TSizeBuf.WriteShort(Value: Int16);
begin
PInt16(GetSpace(SizeOf(Value)))^ := LittleShort(Value);
end;

procedure TSizeBuf.WriteWord(Value: UInt16);
begin
PUInt16(GetSpace(SizeOf(Value)))^ := LittleShort(Value);
end;

procedure TSizeBuf.WriteLong(Value: Int32);
begin
PInt32(GetSpace(SizeOf(Value)))^ := LittleLong(Value);
end;

procedure TSizeBuf.WriteFloat(Value: Single);
begin
PSingle(GetSpace(SizeOf(Value)))^ := LittleFloat(Value);
end;

procedure TSizeBuf.WriteString(S: PLChar);
begin
if S <> nil then
 Write(S, StrLen(S) + 1)
else
 Write(EmptyString, 1)
end;

procedure TSizeBuf.WriteBuffer(Size: UInt; Data: Pointer);
begin
if Data <> nil then
 Write(Data, Size);
end;

procedure TSizeBuf.WriteAngle(F: Single);
begin
WriteByte(Trunc(F * 256 / 360));
end;

procedure TSizeBuf.WriteHiResAngle(F: Single);
begin
WriteShort(Trunc(F * 65536 / 360));
end;

procedure TSizeBuf.WriteCoord(F: Single);
begin
WriteShort(Trunc(F * 8));
end;

end.
