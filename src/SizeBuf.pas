unit SizeBuf;

interface

uses
  Default;

type
  PSizeBuf = ^TSizeBuf;
  TSizeBuf = record
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
  end;

implementation

uses
  Memory, SysMain, Console, Common;

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

end.
