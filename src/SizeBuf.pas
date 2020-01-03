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
  end;

implementation

uses
  Memory, SysMain, Console;

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

end.
