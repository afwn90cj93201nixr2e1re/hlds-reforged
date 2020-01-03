program HLDS;

{$APPTYPE CONSOLE}

uses
  {$IFDEF MSWINDOWS}
  Windows,
  UCWinAPI in 'src/UCWinAPI.pas',
  {$ENDIF }
  {$IFDEF LINUX}
  kerneldefs in 'src/unix/kerneldefs.pas',
  {$ENDIF }
  SysUtils,

  Default in 'src/Default.pas',
  SDK in 'src/SDK.pas',
  Main in 'src/Main.pas',
  BZip2 in 'src/BZip2.pas',
  Common in 'src/Common.pas',
  Console in 'src/Console.pas',
  CoreUI in 'src/CoreUI.pas',
  Decal in 'src/Decal.pas',
  Delta in 'src/Delta.pas',
  Edict in 'src/Edict.pas',
  Encode in 'src/Encode.pas',
  FileSys in 'src/FileSys.pas',
  FilterIP in 'src/FilterIP.pas',
  GameLib in 'src/GameLib.pas',
  HostMain in 'src/HostMain.pas',
  HostCmds in 'src/HostCmds.pas',
  HostSave in 'src/HostSave.pas',
  HPAK in 'src/HPAK.pas',
  Info in 'src/Info.pas',
  MathLib in 'src/MathLib.pas',
  Memory in 'src/Memory.pas',
  Model in 'src/Model.pas',
  MsgBuf in 'src/MsgBuf.pas',
  Network in 'src/Network.pas',
  NetchanMain in 'src/NetchanMain.pas',
  ParseLib in 'src/ParseLib.pas',
  PMove in 'src/PMove.pas',
  Renderer in 'src/Renderer.pas',
  Resource in 'src/Resource.pas',
  StdUI in 'src/StdUI.pas',
  SVAuth in 'src/SVAuth.pas',
  SVClient in 'src/SVClient.pas',
  SVCmds in 'src/SVCmds.pas',
  SVDelta in 'src/SVDelta.pas',
  SVEdict in 'src/SVEdict.pas',
  SVEvent in 'src/SVEvent.pas',
  SVExport in 'src/SVExport.pas',
  SVMain in 'src/SVMain.pas',
  SVMove in 'src/SVMove.pas',
  SVPacket in 'src/SVPacket.pas',
  SVPhys in 'src/SVPhys.pas',
  SVRcon in 'src/SVRcon.pas',
  SVSend in 'src/SVSend.pas',
  SVWorld in 'src/SVWorld.pas',
  SysArgs in 'src/SysArgs.pas',
  SysClock in 'src/SysClock.pas',
  SysMain in 'src/SysMain.pas',
  Texture in 'src/Texture.pas',
  FSNative in 'src/FSNative.pas',
  Client in 'src/Client.pas';

// stuff to do

// shutdown stuff ET in GameLib!!! (win/linux, check for non-nil, mem_free it) (NOT DONE)

// decompressing file err (check?)
// Draw_FreeWAD: check all occurences (don't remember)

// Sys_Error: shutdown host, disconnect clients if necessary
//  - gamedll

// Host_Error: shutdown server

// Host_Error: disconnect all clients and shutdown
// Sys_Error: shutdown immediately without disconnecting

// mp.dll+8d091 FP OP

// a better voice relay, maybe 50% of chan max, 75% of chan max and such
// optimize parsemove
// fix createpacketentities, origin[z], demo recording
// add banlist!

// also find out why players have random viewangles after respawn

// demo recorder!

// FIX:   if SendFrag[I] and (FB <> nil) and (Size + C.ReliableLength <= MAX_FRAGDATA) then
// was   if SendFrag[I] and (FB <> nil) and (Size + C.ReliableLength < MAX_FRAGDATA) then

// Netchan_CreateFileFragments check

begin
FormatSettings.DecimalSeparator := '.';

Start;
while Frame do
 Sys_Sleep(0);
Shutdown;

Writeln('Press any key to close the program...');
Readln;
end.
