unit Host;

// hostcmds for commands

interface

uses SysUtils, Default, SDK;

type
  THost = class
  public
    class procedure Init;
    class procedure Shutdown;
    class function Frame: Boolean;
    class function SaveGameDirectory: PLChar;
    class procedure ClearSaveDirectory;
    class function IsSinglePlayerGame: Boolean;
    class procedure ClearGameState;

    class procedure Error(Msg: PLChar); overload;
    class procedure Error(const Msg: array of const); overload;

    class procedure ShutdownServer(SkipNotify: Boolean);

    class procedure Map(Name: PLChar; Save: Boolean);
    class procedure Say(Team: Boolean);

    class procedure EndSection(Name: PLChar);
    class procedure ClearMemory;

    class procedure InitCommands;
    class procedure InitCVars;
  end;


const
 LangName = 'english';
 LowViolenceBuild = False;

var
 console_cvar: TCVar = (Name: 'console'; Data: '0');
 developer: TCVar = (Name: 'developer'; Data: '0');
 deathmatch: TCVar = (Name: 'deathmatch'; Data: '0'; Flags: [FCVAR_SERVER]);
 coop: TCVar = (Name: 'coop'; Data: '0'; Flags: [FCVAR_SERVER]);
 hostname: TCVar = (Name: 'hostname'; Data: ProjectName + ' v' + ProjectVersion + ' server');
 skill: TCVar = (Name: 'skill'; Data: '1');
 hostmap: TCVar = (Name: 'hostmap'; Data: '');
 host_killtime: TCVar = (Name: 'host_killtime'; Data: '0');
 sys_ticrate: TCVar = (Name: 'sys_ticrate'; Data: '100'; Flags: [FCVAR_SERVER]);
 sys_maxframetime: TCVar = (Name: 'sys_maxframetime'; Data: '0.25');
 sys_minframetime: TCVar = (Name: 'sys_minframetime'; Data: '0.001');
 sys_timescale: TCVar = (Name: 'sys_timescale'; Data: '1');
 host_limitlocal: TCVar = (Name: 'host_limitlocal'; Data: '0');
 host_framerate: TCVar = (Name: 'host_framerate'; Data: '0');
 host_speeds: TCVar = (Name: 'host_speeds'; Data: '0');
 host_profile: TCVar = (Name: 'host_profile'; Data: '0');
 pausable: TCVar = (Name: 'pausable'; Data: '0'; Flags: [FCVAR_SERVER]);

 HostInit: Boolean = False;
 HostActive, HostSubState, HostStateInfo: UInt;
 QuitCommandIssued: Boolean;
 InHostError: Boolean;
 InHostShutdown: Boolean;
 HostHunkLevel: UInt;
 HostFrameTime: Double;
 HostNumFrames: UInt;
 
 RealTime, OldRealTime: Double;

 BaseDir, GameDir, DefaultGameDir, FallbackDir: PLChar;

 CSFlagsInitialized: Boolean = False;
 IsCStrike, IsCZero, IsCZeroRitual, IsTerrorStrike: Boolean;

 WADPath: PLChar;

 HostTimes: record
  Cur, Prev, Frame: Double;

  CollectData: Boolean;
  Host, SV, Rcon: Double;
 end = (CollectData: False);

 TimeCount: UInt;
 TimeTotal: Double;

 CmdLineTicrateCheck: Boolean = False;
 CmdLineTicrate: UInt;

 RollingFPS: Double;

implementation

uses Common, Console, CoreUI, Decal, Delta, Edict, Encode, GameLib,
  HPAK, Memory, Model, MsgBuf, Network, Renderer, Resource, SVClient,
  SVEdict, SVEvent, SVExport, SVMain, SVPacket, SVPhys, SVRcon, SVSend, SVWorld,
  SysMain, SysArgs, SysClock, Texture, Netchan, Client,
  FileSys, Info, MathLib, SVAuth;

class function THost.SaveGameDirectory: PLChar;
begin
Result := 'SAVE' + CorrectSlash;
end;

class procedure THost.ClearSaveDirectory;
begin

end;

class procedure THost.ClearGameState;
begin
THost.ClearSaveDirectory;
DLLFunctions.ResetGlobalState;
end;

class function THost.IsSinglePlayerGame: Boolean;
begin
Result := SV.Active and (SVS.MaxClients = 1);
end;

class procedure THost.EndSection(Name: PLChar);
begin
HostActive := 2;
HostSubState := 1;
HostStateInfo := 1;

if (Name = nil) or (Name^ = #0) then
 Print('Host_EndSection: EndSection with no arguments.')
else
 if StrIComp(Name, '_oem_end_training') = 0 then
  HostStateInfo := 1
 else
  if StrIComp(Name, '_oem_end_logo') = 0 then
   HostStateInfo := 2
  else
   if StrIComp(Name, '_oem_end_demo') = 0 then
    HostStateInfo := 3
   else
    DPrint('Host_EndSection: EndSection with unknown Section keyvalue.');

CBuf_AddText(#10'disconnect'#10);
end;

class procedure THost.ClearMemory;
begin
DPrint('Clearing memory.');

Mod_ClearAll;
CM_FreePAS;
SV_FreePMSimulator;
SV_ClearEntities;
SV_ClearPrecachedEvents;

if HostHunkLevel > 0 then
 Hunk_FreeToLowMark(HostHunkLevel);

SV_ClearClientStates;

MemSet(SV, SizeOf(SV), 0);
end;

class procedure THost.Error(Msg: PLChar);
begin
if InHostError then
 Sys_Error('Host_Error: Recursively entered.')
else
 begin
  InHostError := True;
  Print(['Host_Error: ', Msg]);
  if SV.Active then
   THost.ShutdownServer(False);

  Sys_Error(['Host_Error: ', Msg]);
 end;
end;

class procedure THost.Error(const Msg: array of const);
begin
THost.Error(PLChar(StringFromVarRec(Msg)));
end;

class procedure THost.ShutdownServer(SkipNotify: Boolean);
var
 I: Int;
 C: PClient;
begin
if SV.Active then
 begin
  for I := 0 to SVS.MaxClients - 1 do
   begin
    C := @SVS.Clients[I];
    if C.Connected then
     SV_DropClient(C^, SkipNotify, 'Server shutting down.');
   end;

  SV_ServerDeactivate;
  SV.Active := False;

  HPAK_FlushHostQueue;
  THost.ClearMemory;

  SV_ClearClients;
  MemSet(SVS.Clients^, SizeOf(TClient) * SVS.MaxClientsLimit, 0);
  
  NET_ClearLagData(False, True);
  LPrint('Server shutdown'#10);
  Log_Close;
 end;
end;

procedure Host_InitLocal;
begin
THost.InitCommands;
THost.InitCVars;
end;

class procedure THost.Say(Team: Boolean);
var
 Buf: array[1..192] of LChar;
 S, S2: PLChar;
 I: Int;
 C: PClient;
begin
if CmdSource = csServer then
 if Cmd_Argc < 2 then
  Print('Usage: say <message>')  
 else
  begin
   S := Cmd_Args;
   if (S <> nil) and (S^ > #0) and (StrLen(S) <= 96) then
    begin
     S2 := @Buf;
     S2^ := #1;
     Inc(UInt(S2));

     if hostname.Data^ > #0 then
      begin
       S2 := StrECopy(S2, '<');
       S2 := StrLECopy(S2, hostname.Data, 63);
       S2 := StrECopy(S2, '>: ');
      end
     else
      S2 := StrECopy(S2, '<Server>: ');

     if S^ = '"' then
      Inc(UInt(S));
     S2 := StrECopy(S2, S);
     if PLChar(UInt(S2) - 1)^ = '"' then
      Dec(UInt(S2));
     StrCopy(S2, #10);

     for I := 0 to SVS.MaxClients - 1 do
      begin
       C := @SVS.Clients[I];
       if C.Active and not C.FakeClient then
        begin
         PF_MessageBegin(MSG_ONE, PF_RegUserMsg('SayText', -1), nil, @SV.Edicts[I + 1]);
         PF_WriteByte(0);
         PF_WriteString(@Buf);
         PF_MessageEnd;
        end;
      end;

     S2^ := #0;
     Print(['Server say "', PLChar(UInt(@Buf) + 1), '"']);
     LPrint(['Server say "', PLChar(UInt(@Buf) + 1), '"'#10]);
    end;
  end;
end;

class procedure THost.Map(Name: PLChar; Save: Boolean);
begin
THost.ShutdownServer(False);
if not Save then
 begin
  THost.ClearGameState;
  SVS.ServerFlags := 0;
 end;

if SV_SpawnServer(Name, nil) then
 if Save then
  begin
   SV_LoadEntities;

   SV.Paused := True;
   SV.SavedGame := True;
   SV_ActivateServer(False);
   SV_LinkNewUserMsgs;
  end
 else
  begin
   SV_LoadEntities;
   SV_ActivateServer(True);
   SV_LinkNewUserMsgs;
  end;
end;

procedure Host_SetHostTimes;
begin
HostTimes.Cur := Sys_FloatTime;
HostTimes.Frame := HostTimes.Cur - HostTimes.Prev;
if HostTimes.Frame < 0 then
 begin
  if sys_minframetime.Value <= 0 then
   CVar_DirectSet(sys_minframetime, '0.0001');
  HostTimes.Frame := sys_minframetime.Value;
 end;
HostTimes.Prev := HostTimes.Cur;
end;

procedure Host_CheckTimeCVars;
begin
if sys_minframetime.Value <= 0 then
 CVar_DirectSet(sys_minframetime, '0.0001')
else
 if sys_maxframetime.Value > 2 then
  CVar_DirectSet(sys_maxframetime, '2')
 else
  if sys_timescale.Value <= 0 then
   CVar_DirectSet(sys_timescale, '1');
end;

function Host_FilterTime(Time: Double): Boolean;
var
 F: Double;
begin
Host_CheckTimeCVars;
if sys_timescale.Value <> 1 then
 RealTime := RealTime + Time * sys_timescale.Value
else
 RealTime := RealTime + Time;

if not CmdLineTicrateCheck then
 begin
  CmdLineTicrateCheck := True;
  CmdLineTicrate := StrToIntDef(COM_ParmValueByName('-sys_ticrate'), 0);
 end;

if CmdLineTicrate = 0 then
 F := sys_ticrate.Value
else
 F := CmdLineTicrate;

if (F > 0) and (RealTime - OldRealTime < (1 / (F + 1))) then
 Result := False
else
 begin
  F := RealTime - OldRealTime;
  OldRealTime := RealTime;

  if F > sys_maxframetime.Value then
   HostFrameTime := sys_maxframetime.Value
  else
   if F < sys_minframetime.Value then
    HostFrameTime := sys_minframetime.Value
   else
    HostFrameTime := F;

  if HostFrameTime <= 0 then
   HostFrameTime := sys_minframetime.Value;

  Result := True;
 end;
end;

procedure Host_ComputeFPS(Time: Double);
begin
RollingFPS := RollingFPS * 0.6 + Time * 0.4;
end;

procedure Host_WriteSpeeds;
begin

end;

procedure Host_UpdateStats;
begin

end;

procedure _Host_Frame(Time: Double);
begin
if Host_FilterTime(Time) then
 begin
  Host_ComputeFPS(HostFrameTime);
  CBuf_Execute;
  if HostTimes.CollectData then
   HostTimes.Host := Sys_FloatTime;
  
  SV_Frame;
  if HostTimes.CollectData then
   HostTimes.SV := Sys_FloatTime;

  SV_CheckForRcon;
  if HostTimes.CollectData then
   HostTimes.Rcon := Sys_FloatTime;

  Host_WriteSpeeds;
  Inc(HostNumFrames);
  if sv_stats.Value <> 0 then
   Host_UpdateStats;

  if (host_killtime.Value <> 0) and (host_killtime.Value < SV.Time) then
   CBuf_AddText('quit'#10);

  UI_Frame(RealTime);
 end;
end;

class function THost.Frame: Boolean;
var
 TimeStart, TimeEnd: Double;
 Profile: Boolean;
 Count: UInt;
 I: Int;
begin
Host_SetHostTimes;

if QuitCommandIssued then
 Result := False
else
 begin
  Profile := host_profile.Value <> 0;
  if not Profile then
   begin
    _Host_Frame(HostTimes.Frame);
    if HostStateInfo <> 0 then
     begin
      HostStateInfo := 0;
      CBuf_Execute;
     end;
   end
  else
   begin
    TimeStart := Sys_FloatTime;
    _Host_Frame(HostTimes.Frame);
    TimeEnd := Sys_FloatTime;

    if HostStateInfo <> 0 then
     begin
      HostStateInfo := 0;
      CBuf_Execute;
     end;

    Inc(TimeCount);
    TimeTotal := TimeTotal + TimeEnd - TimeStart;

    if TimeCount >= 1000 then
     begin
      Count := 0;
      for I := 0 to SVS.MaxClients - 1 do
       if SVS.Clients[I].Active then
        Inc(Count);

      Print(['host_profile: ', Count, ' clients, ', Trunc(TimeTotal * 1000 / TimeCount), ' msec']);
      TimeTotal := 0;
      TimeCount := 0;
     end;
   end;

  Result := True;
 end;
end;

class procedure THost.Init;
var
 Buf: array[1..256] of LChar;
 IntBuf: array[1..32] of LChar;
begin
RealTime := 0;

Rand_Init;
CBuf_Init;
Cmd_Init;
CVar_Init;       
Host_InitLocal;
THost.ClearSaveDirectory;
Con_Init;
HPAK_Init;

SV_SetMaxClients;
W_LoadWADFile('gfx.wad');
W_LoadWADFile('fonts.wad');
Decal_Init;
Mod_Init;
R_Init;
NET_Init;
TNetchan.Init;
Delta_Init;
SV_Init;

StrLCopy(@Buf, ProjectVersion, SizeOf(Buf) - 1);
StrLCat(@Buf, ',47-48,', SizeOf(Buf) - 1);
StrLCat(@Buf, IntToStr(BuildNumber, IntBuf, SizeOf(IntBuf)), SizeOf(Buf) - 1);
CVar_DirectSet(sv_version, @Buf);

HPAK_CheckIntegrity('custom.hpk');

CBuf_InsertText('exec valve.rc'#10);
Hunk_AllocName(0, '-HOST_HUNKLEVEL-');
HostHunkLevel := Hunk_LowMark;

HostActive := 1;
HostNumFrames := 0;

HostTimes.Prev := Sys_FloatTime;
HostInit := True;
end;

class procedure THost.Shutdown;
begin
if InHostShutdown then
 Sys_DebugOutStraight('Host_Shutdown: Recursive shutdown.')
else
 begin
  InHostShutdown := True;
  HostInit := False;

  SV_ServerDeactivate;

  Mod_ClearAll;
  SV_ClearEntities;
  CM_FreePAS;
  SV_FreePMSimulator;

  SV_Shutdown;
  ReleaseEntityDLLs;
  Delta_Shutdown;
  NET_Shutdown;
  if WADPath <> nil then
   Mem_FreeAndNil(WADPath);
  Draw_DecalShutdown;
  W_Shutdown;
  HPAK_FlushHostQueue;
  Con_Shutdown;
  Cmd_RemoveGameCmds;
  Cmd_Shutdown;
  CVar_Shutdown;

  LPrint('Server shutdown'#10);
  Log_Close;
  RealTime := 0;
  SV.Time := 0;
 end;
end;

procedure Host_KillServer_F; cdecl;
begin
if CmdSource = csServer then
 if SV.Active then
  begin
   Print('Shutting down the server.');
   THost.ShutdownServer(False);
  end
 else
  Print('The server is not active, can''t shutdown.');
end;

procedure Host_Restart_F; cdecl;
var
 Map: array[1..MAX_MAP_NAME] of LChar;
begin
if (CmdSource = csServer) and SV.Active then
 begin
  THost.ClearGameState;
  SV_InactivateClients;
  StrCopy(@Map, @SV.Map);
  SV_ServerDeactivate;
  SV_SpawnServer(@Map, nil);
  SV_LoadEntities;
  SV_ActivateServer(True);
 end;
end;

procedure Host_Status_F; cdecl;
var
 Buf: array[1..1024] of LChar;
 NetAdrBuf: array[1..128] of LChar;
 IntBuf, ExpandBuf: array[1..32] of LChar;
 ExtInfo, ToConsole: Boolean;
 F: TFile;
 S, S2, UniqueID: PLChar;
 I, HSpecs, HSlots, HDelay: Int;
 Time, Players, Hour, Min, Sec: UInt;
 C: PClient;
 AvgTx, AvgRx: Double;

 procedure Host_Status_PrintF(const Msg: array of const);
 begin
  if ToConsole then
   Print(Msg)
  else
   SV_ClientPrint(PLChar(StringFromVarRec(Msg)));

  if F <> nil then
   FS_FPrintF(F, Msg, True);
 end;

begin
ExtInfo := False;
F := nil;
ToConsole := CmdSource = csServer;
for I := 1 to Cmd_Argc - 1 do
 begin
  S := Cmd_Argv(I);
  if (StrIComp(S, 'ext') = 0) or (StrIComp(S, '-ext') = 0) then
   ExtInfo := True
  else
   if ((StrIComp(S, 'log') = 0) or (StrIComp(S, '-log') = 0)) and (F = nil) and ToConsole then
    if not FS_Open(F, 'status.log', 'wo') then
     F := nil;
 end;

Players := SV_CountPlayers;

Host_Status_PrintF(['- Server Status -']);
if hostname.Data^ > #0 then
 Host_Status_PrintF(['Hostname: ', hostname.Data]);

Host_Status_PrintF(['Version:  ', ProjectVersion, '; build ', ProjectBuild, '; 47/48 multi-protocol']);
if not NoIP then
 Host_Status_PrintF(['TCP/IP:   ', NET_AdrToString(LocalIP, NetAdrBuf, SizeOf(NetAdrBuf))]);

if not SV.Active then
 Host_Status_PrintF(['The server is not active.'])
else
 begin
  Host_Status_PrintF(['Map:      ', PLChar(@SV.Map)]);
  Host_Status_PrintF(['Players:  ', Players, ' connected (', SVS.MaxClients, ' max)']);

  AvgTx := 0;
  AvgRx := 0;
  for I := 0 to SVS.MaxClients - 1 do
   begin
    C := @SVS.Clients[I];
    if C.Active then
     begin
      AvgTx := AvgTx + C.Netchan.Flow[FS_TX].KBAvgRate;
      AvgRx := AvgRx + C.Netchan.Flow[FS_RX].KBAvgRate;
     end;
   end;
  Host_Status_PrintF(['Network:  Out = ', RoundTo(AvgTx, -2), ' KBps; In = ', RoundTo(AvgRx, -2), ' KBps']);

  if ExtInfo then
   Host_Status_PrintF(['Sequence: ', SVS.SpawnCount]);

  for I := 0 to SVS.MaxClients - 1 do
   begin
    C := @SVS.Clients[I];
    if C.Active then
     begin
      Time := Trunc(RealTime - C.ConnectTime);
      Sec := Time mod 60;
      Time := Time div 60;
      Min := Time mod 60;
      Time := Time div 60;
      Hour := Time;

      if C.FakeClient then
       UniqueID := 'BOT'
      else
       UniqueID := SV_GetClientIDString(C^);

      S := StrECopy(@Buf, '#');
      S := StrECopy(S, ExpandString(IntToStr(I + 1, IntBuf, SizeOf(IntBuf)), @ExpandBuf, SizeOf(ExpandBuf), 2));
      S := StrECopy(S, ': ');
      S := StrECopy(S, @C.NetName);
      S := StrECopy(S, ' (UserID: ');
      S := StrECopy(S, IntToStr(C.UserID, IntBuf, SizeOf(IntBuf)));
      S := StrECopy(S, ', UniqueID: ');
      S := StrECopy(S, UniqueID);
      S := StrECopy(S, ', Time: ');
      if Min > 0 then
       begin
        if Hour > 0 then
         begin
          S := StrECopy(S, ExpandString(IntToStr(Hour, IntBuf, SizeOf(IntBuf)), @ExpandBuf, SizeOf(ExpandBuf), 2));
          S := StrECopy(S, ':');
         end;

        S := StrECopy(S, ExpandString(IntToStr(Min, IntBuf, SizeOf(IntBuf)), @ExpandBuf, SizeOf(ExpandBuf), 2));
        S := StrECopy(S, ':');
        S := StrECopy(S, ExpandString(IntToStr(Sec, IntBuf, SizeOf(IntBuf)), @ExpandBuf, SizeOf(ExpandBuf), 2));
        S := StrECopy(S, ', ');
       end
      else
       begin
        S := StrECopy(S, IntToStr(Sec, IntBuf, SizeOf(IntBuf)));
        S := StrECopy(S, ' sec, ');
       end;

      if C.HLTV then
       begin
        S := StrECopy(S, 'HLTV: ');
        HSpecs := -1;
        HSlots := -1;
        HDelay := -1;

        S2 := Info_ValueForKey(@C.UserInfo, 'hspecs');
        if (S2 <> nil) and (S2^ > #0) then
         HSpecs := StrToIntDef(S2, -1);
        S2 := Info_ValueForKey(@C.UserInfo, 'hslots');
        if (S2 <> nil) and (S2^ > #0) then
         HSlots := StrToIntDef(S2, -1);
        S2 := Info_ValueForKey(@C.UserInfo, 'hdelay');
        if (S2 <> nil) and (S2^ > #0) then
         HDelay := StrToIntDef(S2, -1);

        if (HSpecs < 0) or (HSlots < 0) then
         if HDelay < 0 then
          S := StrECopy(S, 'no data, ')
         else
          begin
           S := StrECopy(S, 'no slot data, delay: ');
           S := StrECopy(S, IntToStr(HDelay, IntBuf, SizeOf(IntBuf)));
           S := StrECopy(S, 's, ');
          end
        else
         begin
          S := StrECopy(S, IntToStr(HSpecs, IntBuf, SizeOf(IntBuf)));
          S := StrECopy(S, '/');
          S := StrECopy(S, IntToStr(HSlots, IntBuf, SizeOf(IntBuf)));
          if HDelay < 0 then
           S := StrECopy(S, ', no delay data, ')
          else
           begin
            S := StrECopy(S, ' with ');
            S := StrECopy(S, IntToStr(HDelay, IntBuf, SizeOf(IntBuf)));
            S := StrECopy(S, 's delay, ');
           end;
         end;
       end
      else
       if C.Entity <> nil then
        begin
         S := StrECopy(S, 'Frags: ');
         S := StrECopy(S, IntToStr(Trunc(C.Entity.V.Frags), IntBuf, SizeOf(IntBuf)));
        end;

      if not C.FakeClient then
       begin
        S := StrECopy(S, ', Protocol: ');
        S := StrECopy(S, IntToStr(C.Protocol, IntBuf, SizeOf(IntBuf)));
        S := StrECopy(S, ', Ping: ');
        S := StrECopy(S, IntToStr(SV_CalcPing(C^), IntBuf, SizeOf(IntBuf)));
        S := StrECopy(S, ', Loss: ');
        S := StrECopy(S, IntToStr(Trunc(C.PacketLoss), IntBuf, SizeOf(IntBuf)));
       end;

      if (ToConsole or C.HLTV) and (C.Netchan.Addr.AddrType = NA_IP) then
       begin
        S := StrECopy(S, ', Addr: ');
        S := StrECopy(S, NET_AdrToString(C.Netchan.Addr, NetAdrBuf, SizeOf(NetAdrBuf)));
       end;

      if ExtInfo then
       begin
        if C.Active then
         S := StrECopy(S, ', active');
        if C.Spawned then
         S := StrECopy(S, ', spawned');
        if C.Connected then
         S := StrECopy(S, ', connected');
       end;

      StrCopy(S, ').');
      Host_Status_PrintF([PLChar(@Buf)]);
     end;
   end;

  Host_Status_PrintF([Players, ' users.']);
 end;

if F <> nil then
 FS_Close(F);
end;

procedure Host_Quit_F; cdecl;
begin
if CmdSource = csServer then
 if Cmd_Argc = 1 then
  begin
   HostActive := 3;
   QuitCommandIssued := True;
   THost.ShutdownServer(False);
  end
 else
  begin
   HostActive := 2;
   HostStateInfo := 4;
  end;
end;

procedure Host_Quit_Restart_F; cdecl;
begin
if CmdSource = csServer then
 begin
  HostActive := 5;
  HostStateInfo := 4;
 end;
end;

procedure Host_Map_F; cdecl;
var
 MapName, MapFullName: array[1..MAX_MAP_NAME] of LChar;
begin
if CmdSource <> csServer then
 Exit;

if Cmd_Argc <> 2 then
 Print('Usage: map <name>')
else
 if not FilterMapName(Cmd_Argv(1), @MapFullName) then
  Print('map: The map name is too big.')
 else
  if not FS_FileExists(@MapFullName) then
   Print(['map: "', PLChar(@MapFullName), '" was not found on the server.'])
  else
   begin
    COM_FileBase(@MapFullName, @MapName);
    CVar_DirectSet(hostmap, @MapName);

    FS_LogLevelLoadStarted('Map_Common');
    if not SVS.InitGameDLL then
     Host_InitializeGameDLL;
    FS_LogLevelLoadStarted(@MapName);
    THost.Map(@MapName, False);
   end;
end;

procedure Host_Maps_F; cdecl;
var
 S: PLChar;
begin
if Cmd_Argc <> 2 then
 Print('Usage: maps <substring>')
else
 begin
  S := Cmd_Argv(1);
  if (S <> nil) and (S^ > #0) then
   if S^ = '*' then
    COM_ListMaps(nil)
   else
    COM_ListMaps(S)
  else
   Print('maps: Bad substring.')
 end;
end;

procedure Host_Reload_F; cdecl;
begin
if CmdSource = csServer then
 begin
  THost.ClearGameState;
  SV_InactivateClients;
  SV_ServerDeactivate;
  SV_SpawnServer(hostmap.Data, nil);
  SV_LoadEntities;
  SV_ActivateServer(True);
 end;
end;

procedure Host_Changelevel_F; cdecl;
var
 S: PLChar;
 K: UInt;
 MapName, MapFullName: array[1..MAX_MAP_NAME] of LChar;
begin
if CmdSource = csServer then
 begin
  K := Cmd_Argc;
  if (K < 2) or (K > 3) then
   Print('Usage: changelevel <levelname>')
  else
   if not FilterMapName(Cmd_Argv(1), @MapFullName) then
    Print('changelevel: The map name is too big.')
   else
    if not FS_FileExists(@MapFullName) then
     Print(['changelevel: "', PLChar(@MapFullName), '" was not found on the server.'])
    else
     begin
      if K = 2 then
       S := nil
      else
       S := Cmd_Argv(2);

      COM_FileBase(@MapFullName, @MapName);
      CVar_DirectSet(hostmap, @MapName);

      FS_LogLevelLoadStarted('Map_Common');
      if not SVS.InitGameDLL then
       Host_InitializeGameDLL;
      FS_LogLevelLoadStarted(@MapName);

      SV_InactivateClients;
      SV_ServerDeactivate;
      SV_SpawnServer(@MapName, S);
      SV_LoadEntities;
      SV_ActivateServer(True);
     end;
 end;
end;

procedure Host_Changelevel2_F; cdecl;
begin
if CmdSource = csServer then
 begin
  Print('changelevel2: Not implemented.');
 end;
end;

procedure Host_Version_F; cdecl;
begin
if CmdSource = csServer then
 Print(['Protocol version: 47/48 (multi-protocol).', sLineBreak,
        'Server build: ', BuildNumber, '; server version ', ProjectVersion, '.']);
end;

procedure Host_Say_F; cdecl;
begin
if CmdSource = csServer then
 THost.Say(False);
end;

procedure Host_Say_Team_F; cdecl;
begin
if CmdSource = csServer then
 THost.Say(True);
end;

procedure Host_Tell_F; cdecl;
begin
if CmdSource = csServer then
 THost.Say(False);
end;

procedure Host_Kill_F; cdecl;
begin
if CmdSource = csClient then
 if SVPlayer.V.Health > 0 then
  begin
   GlobalVars.Time := SV.Time;
   DLLFunctions.ClientKill(SVPlayer^);
  end
 else
  SV_ClientPrint('Can''t suicide - already dead.');
end;

procedure Host_TogglePause_F; cdecl;
var
 S: PLChar;
begin
if not SV.Active then
 SV_CmdPrint('The server is not running.')
else
 if (CmdSource = csClient) and not NET_IsLocalAddress(HostClient.Netchan.Addr) then
  SV_CmdPrint('Only server operators may use this command.')
 else
  if pausable.Value = 0 then
   SV_CmdPrint('Pause is not allowed on this server.')
  else
   begin
    if CmdSource = csClient then
     S := @HostClient.NetName
    else
     S := 'Server operator';

    SV.Paused := not SV.Paused;
    if SV.Paused then
     SV_BroadcastPrint([S, ' paused the game.'#10])
    else
     SV_BroadcastPrint([S, ' unpaused the game.'#10]);

    MSG_WriteByte(SV.ReliableDatagram, SVC_SETPAUSE);
    MSG_WriteByte(SV.ReliableDatagram, Byte(SV.Paused));
   end;
end;

procedure Host_Kick_F; cdecl;
var
 C, C2: PClient;
 I, J, K, UserID: UInt;
 S: PLChar;
 Buf: array[1..1024] of LChar;
begin
K := Cmd_Argc;
if K < 2 then
 SV_CmdPrint('Usage: kick <username or #userid> [reason]')
else
 if (CmdSource = csClient) and not NET_IsLocalAddress(HostClient.Netchan.Addr) then
  SV_CmdPrint('Only server operators may use this command.')
 else
  if not SV.Active then
   SV_CmdPrint('kick: The server is not running.')
  else
   begin
    J := 1;
    S := Cmd_Argv(J);
    if StrComp(S, '#') = 0 then
     begin
      Inc(J);
      UserID := StrToIntDef(Cmd_Argv(J), 0);
      S := nil;
     end
    else
     if S^ = '#' then
      begin
       UserID := StrToIntDef(PLChar(UInt(S) + 1), 0);
       S := nil;
      end
     else
      UserID := 0;

    if (UserID = 0) and (S = nil) then
     begin
      SV_CmdPrint('kick: Bad userid specified.');
      Exit;
     end;

    Buf[Low(Buf)] := #0;
    for I := J + 1 to K - 1 do
     begin
      StrLCat(@Buf, Cmd_Argv(I), SizeOf(Buf) - 1);
      if I < K - 1 then
       StrLCat(@Buf, ' ', SizeOf(Buf) - 1);
     end;

    for I := 0 to SVS.MaxClients - 1 do
     begin
      C := @SVS.Clients[I];
      if C.Connected and (((UserID > 0) and (C.UserID = UserID)) or ((S <> nil) and (StrComp(@C.NetName, S) = 0))) then
       begin
        if CmdSource = csClient then
         S := @HostClient.NetName
        else
         S := 'server operator';

        C2 := HostClient;
        HostClient := C;

        if Buf[Low(Buf)] = #0 then
         begin
          SV_CmdPrint(['Kicked ', PLChar(@C.NetName), '.']);
          SV_ClientPrint(['Kicked by ', S, '.']);
          SV_DropClient(C^, False, 'Kicked by server operator.');
          if CmdSource = csClient then
           LPrint([S, ' kicked ', PLChar(@C.NetName), '.'#10])
          else
           LPrint(['Kicked ', PLChar(@C.NetName), '.'#10]);
         end
        else
         begin
          SV_CmdPrint(['Kicked ', PLChar(@C.NetName), '. Reason: ', PLChar(@Buf)]);
          SV_ClientPrint(['Kicked by ', S, '. Reason: ', PLChar(@Buf)]);
          SV_DropClient(C^, False, PLChar(@Buf));
          if CmdSource = csClient then
           LPrint([S, ' kicked ', PLChar(@C.NetName), ', reason: ', PLChar(@Buf), #10])
          else
           LPrint(['Kicked ', PLChar(@C.NetName), ', reason: ', PLChar(@Buf), #10]);
         end;

        HostClient := C2;
        Exit;
       end;
     end;

    if UserID > 0 then
     SV_CmdPrint(['kick: Couldn''t find #', UserID, '.'])
    else
     SV_CmdPrint(['kick: Couldn''t find "', S, '".'])
   end;
end;

procedure Host_Ping_F; cdecl;
var
 I, Num: Int;
 C: PClient;
begin
SV_CmdPrint('Client ping times:');
Num := 0;
for I := 0 to SVS.MaxClients - 1 do
 begin
  C := @SVS.Clients[I];
  if C.Active then
   begin
    Inc(Num);
    SV_CmdPrint([PLChar(@C.NetName), ': ', SV_CalcPing(C^)]);
   end;
 end;

if Num = 0 then
 SV_CmdPrint('(no clients currently connected)')
else
 SV_CmdPrint([Num, ' total clients.']);
end;

procedure Host_SetInfo_F; cdecl;
begin
if CmdSource = csClient then
 if Cmd_Argc <> 3 then
  SV_ClientPrint('Usage: setinfo [<key> <value>]')
 else
  begin
   Info_SetValueForKey(@HostClient.UserInfo, Cmd_Argv(1), Cmd_Argv(2), MAX_USERINFO_STRING);
   HostClient.UpdateInfo := True;
   HostClient.FragSizeUpdated := False;
  end;
end;

procedure Host_WriteFPS_F; cdecl;
begin
if CmdSource = csServer then
 if RollingFPS = 0 then
  Print('FPS: 0')
 else
  Print(['FPS: ', RoundTo(1 / RollingFPS, -2)]);
end;

procedure Host_Maxplayers_F; cdecl;
var
 I: UInt;
begin
if CmdSource = csServer then
 begin
  I := Cmd_Argc;
  if I < 2 then
   Print(['"maxplayers" is "', SVS.MaxClients, '"'])
  else
   if I > 2 then
    Print('Usage: maxplayers <value>')
   else
    if SV.Active then
     Print('maxplayers: Can''t change maxplayers while a server is running.')
    else
     begin
      I := StrToInt(Cmd_Argv(1));
      if I < 1 then
       I := 1
      else
       if I > SVS.MaxClientsLimit then
        I := SVS.MaxClientsLimit;

      Print(['"maxplayers" set to "', I, '"']);

      SVS.MaxClients := I;
      if I > 1 then
       CVar_DirectSet(deathmatch, '1')
      else
       CVar_DirectSet(deathmatch, '0');
     end;
 end;
end;

procedure Host_God_F; cdecl;
begin
if (CmdSource = csClient) and AllowCheats then
 begin
  SVPlayer.V.Flags := SVPlayer.V.Flags xor FL_GODMODE;
  if (SVPlayer.V.Flags and FL_GODMODE) > 0 then
   SV_ClientPrint('god: God mode is now enabled.')
  else
   SV_ClientPrint('god: God mode is now disabled.');
 end;
end;

procedure Host_Notarget_F; cdecl;
begin
if (CmdSource = csClient) and AllowCheats then
 begin
  SVPlayer.V.Flags := SVPlayer.V.Flags xor FL_NOTARGET;
  if (SVPlayer.V.Flags and FL_NOTARGET) > 0 then
   SV_ClientPrint('notarget: No-targeting mode is now enabled.')
  else
   SV_ClientPrint('notarget: No-targeting mode is now disabled.');
 end;
end;

function FindPassableSpace(var E: TEdict; const Angles: TVec3; Dir: Single): Boolean;
var
 I: UInt;
begin
for I := 1 to 32 do
 begin
  VectorMA(E.V.Origin, Dir, Angles, E.V.Origin);
  if SV_TestEntityPosition(E) = nil then
   begin
    E.V.OldOrigin := E.V.Origin;
    Result := True;
    Exit;
   end;
 end;

Result := False;
end;

procedure Host_Noclip_F; cdecl;
var
 Fwd, Right, Up: TVec3;
begin
if (CmdSource = csClient) and AllowCheats then
 if SVPlayer.V.MoveType = MOVETYPE_NOCLIP then
  begin
   SVPlayer.V.MoveType := MOVETYPE_WALK;
   SVPlayer.V.OldOrigin := SVPlayer.V.Origin;

   if SV_TestEntityPosition(SVPlayer^) <> nil then
    begin
     AngleVectors(SVPlayer.V.VAngle, @Fwd, @Right, @Up);
     if not FindPassableSpace(SVPlayer^, Fwd, 1) and
        not FindPassableSpace(SVPlayer^, Fwd, -1) and
        not FindPassableSpace(SVPlayer^, Right, 1) and
        not FindPassableSpace(SVPlayer^, Right, -1) and
        not FindPassableSpace(SVPlayer^, Up, 1) and
        not FindPassableSpace(SVPlayer^, Up, -1) then
      SV_ClientPrint('noclip: Can''t find the world.');

     SVPlayer.V.Origin := SVPlayer.V.OldOrigin;
    end;

   SV_ClientPrint('noclip: No-clipping mode is now disabled.');
  end
 else
  begin
   SVPlayer.V.MoveType := MOVETYPE_NOCLIP;
   SV_ClientPrint('noclip: No-clipping mode is now enabled.');
  end;
end;

class procedure THost.InitCommands;
begin
Cmd_AddCommand('maxplayers', @Host_Maxplayers_F);
Cmd_AddCommand('shutdownserver', Host_KillServer_F);
Cmd_AddCommand('status', Host_Status_F);
Cmd_AddCommand('quit', Host_Quit_F);
Cmd_AddCommand('exit', Host_Quit_F);
Cmd_AddCommand('_restart', Host_Quit_Restart_F);
Cmd_AddCommand('map', Host_Map_F);
Cmd_AddCommand('maps', Host_Maps_F);
Cmd_AddCommand('restart', Host_Restart_F);
Cmd_AddCommand('reload', Host_Reload_F);
Cmd_AddCommand('changelevel', Host_Changelevel_F);
Cmd_AddCommand('changelevel2', Host_Changelevel2_F);
Cmd_AddCommand('version', Host_Version_F);
Cmd_AddCommand('say', Host_Say_F);
Cmd_AddCommand('say_team', Host_Say_Team_F);
Cmd_AddCommand('tell', Host_Tell_F);
Cmd_AddCommand('kill', Host_Kill_F);
Cmd_AddCommand('pause', Host_TogglePause_F);
Cmd_AddCommand('kick', Host_Kick_F);
Cmd_AddCommand('ping', Host_Ping_F);
Cmd_AddCommand('setinfo', Host_SetInfo_F);

Cmd_AddCommand('god', Host_God_F);
Cmd_AddCommand('notarget', Host_Notarget_F);
Cmd_AddCommand('noclip', Host_Noclip_F);

Cmd_AddCommand('writefps', Host_WriteFPS_F);

end;

class procedure THost.InitCVars;
begin
CVar_RegisterVariable(developer);
CVar_RegisterVariable(console_cvar);
CVar_RegisterVariable(hostmap);
CVar_RegisterVariable(host_killtime);
CVar_RegisterVariable(sys_ticrate);
CVar_RegisterVariable(hostname);
CVar_RegisterVariable(sys_timescale);
CVar_RegisterVariable(host_limitlocal);
CVar_RegisterVariable(host_framerate);
CVar_RegisterVariable(host_speeds);
CVar_RegisterVariable(host_profile);
CVar_RegisterVariable(deathmatch);
CVar_RegisterVariable(coop);
CVar_RegisterVariable(pausable);
CVar_RegisterVariable(skill);

// Custom
CVar_RegisterVariable(sys_maxframetime);
CVar_RegisterVariable(sys_minframetime);
end;

end.
