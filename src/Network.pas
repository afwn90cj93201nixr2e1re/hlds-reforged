unit Network;

interface

uses SysUtils, {$IFDEF MSWINDOWS} Windows, Winsock, {$ELSE} Libc, KernelIoctl, {$ENDIF} Default, SDK;

function NET_AdrToString(const A: TNetAdr; out Buf; L: UInt): PLChar; overload;
function NET_BaseAdrToString(const A: TNetAdr; out Buf; L: UInt): PLChar;
function NET_CompareBaseAdr(const A1, A2: TNetAdr): Boolean;

function NET_CompareAdr(const A1, A2: TNetAdr): Boolean;
function NET_StringToAdr(S: PLChar; out A: TNetAdr): Boolean;
function NET_StringToSockaddr(Name: PLChar; out S: TSockAddr): Boolean;
function NET_CompareClassBAdr(const A1, A2: TNetAdr): Boolean;
function NET_IsReservedAdr(const A: TNetAdr): Boolean;
function NET_IsLocalAddress(const A: TNetAdr): Boolean;
procedure NET_Config(EnableNetworking: Boolean);

procedure NET_SendPacket(Source: TNetSrc; Size: UInt; Buffer: Pointer; const Dest: TNetAdr);

function NET_AllocMsg(Size: UInt): PNetQueue;

function NET_GetPacket(Source: TNetSrc): Boolean;

procedure NET_ClearLagData(Client, Server: Boolean);

procedure NET_Init;
procedure NET_Shutdown;

var
 InMessage, NetMessage: TSizeBuf;
 InFrom, NetFrom, LocalIP: TNetAdr;

 NoIP: Boolean = False;
 
 clockwindow: TCVar = (Name: 'clockwindow'; Data: '0.5');

 NetDrop: UInt = 0; // amount of dropped incoming packets

implementation

uses BZip2, Common, Console, FileSys, Memory, MsgBuf, HostMain, HostCmds,
  Resource, SVClient, SVMain, SysArgs, SysMain, NetchanMain;

const
 IPTOS_LOWDELAY = 16;
 SD_RECEIVE = 0;
 SD_SEND = 1;
 SD_BOTH = 2;
 INADDR_NONE = -1;

var
 OldConfig: Boolean = False;
 FirstInit: Boolean = True;
 NetInit: Boolean = False;

 IPSockets: array[TNetSrc] of TSocket;

 InMsgBuffer, NetMsgBuffer: array[1..MAX_NETBUFLEN] of Byte;

 // cvars
 net_address: TCVar = (Name: 'net_address'; Data: '');
 ipname: TCVar = (Name: 'ip'; Data: 'localhost');
 ip_hostport: TCVar = (Name: 'ip_hostport'; Data: '0');
 hostport: TCVar = (Name: 'hostport'; Data: '0');
 defport: TCVar = (Name: 'port'; Data: '27015');

 fakelag: TCVar = (Name: 'fakelag'; Data: '0');
 fakeloss: TCVar = (Name: 'fakeloss'; Data: '0');

 NormalQueue: PNetQueue = nil;
 NetMessages: array[TNetSrc] of PNetQueue;

 Loopbacks: array[TNetSrc] of TLoopBack;

 LagData: array[TNetSrc] of TLagPacket;
 FakeLagTime: Single = 0;
 LastLagTime: Double = 0;

 LossCount: array[TNetSrc] of UInt = (0, 0, 0);

 SplitCtx: array[0..MAX_SPLIT_CTX - 1] of TSplitContext;
 CurrentCtx: UInt = Low(SplitCtx);

 // 0 - disabled
 // 1 - normal packets only
 // 2 - files only
 // 3 - packets & files
 net_compress: TCVar = (Name: 'net_compress'; Data: '3');

function NET_LastError: Int;
begin
{$IFDEF MSWINDOWS}
Result := WSAGetLastError;
{$ELSE}
Result := errno; // h_errno
{$ENDIF}
end;

function ntohs(I: UInt16): UInt16;
begin
Result := (I shl 8) or (I shr 8);
end;

function htons(I: UInt16): UInt16;
begin
Result := (I shl 8) or (I shr 8);
end;

procedure NetadrToSockadr(const A: TNetAdr; out S: TSockAddr);
begin
case A.AddrType of
 NA_BROADCAST:
  begin
   S.sin_family := AF_INET;
   S.sin_port := A.Port;
   Int32(S.sin_addr.S_addr) := INADDR_BROADCAST;
   MemSet(S.sin_zero, SizeOf(S.sin_zero), 0);
  end;
 NA_IP:
  begin
   S.sin_family := AF_INET;
   S.sin_port := A.Port;
   Int32(S.sin_addr.S_addr) := PInt32(@A.IP)^;
   MemSet(S.sin_zero, SizeOf(S.sin_zero), 0);
  end;
 else
  MemSet(S, SizeOf(S), 0);
end;  
end;

procedure SockadrToNetadr(const S: TSockAddr; out A: TNetAdr);
begin
if S.sa_family = AF_INET then
 begin
  A.AddrType := NA_IP;
  PInt32(@A.IP)^ := Int32(S.sin_addr.S_addr);
  A.Port := S.sin_port;
 end
else
 MemSet(A, SizeOf(A), 0);
end;

function NET_CompareAdr(const A1, A2: TNetAdr): Boolean;
begin
if A1.AddrType <> A2.AddrType then
 Result := False
else
 case A1.AddrType of
  NA_LOOPBACK: Result := True;
  NA_IP: Result := (PUInt32(@A1.IP)^ = PUInt32(@A2.IP)^) and (A1.Port = A2.Port);
  else Result := False;
 end;
end;

function NET_CompareClassBAdr(const A1, A2: TNetAdr): Boolean;
begin
if A1.AddrType <> A2.AddrType then
 Result := False
else
 case A1.AddrType of
  NA_LOOPBACK: Result := True;
  NA_IP: Result := PUInt16(@A1.IP)^ = PUInt16(@A2.IP)^;
  else Result := False;
 end;
end;

function NET_IsReservedAdr(const A: TNetAdr): Boolean;
begin
case A.AddrType of
 NA_LOOPBACK: Result := True;
 NA_IP: Result := (A.IP[1] = 10) or (A.IP[1] = 127) or
                  ((A.IP[1] = 172) and (A.IP[2] >= 16) and (A.IP[2] <= 31)) or
                  ((A.IP[1] = 192) and (A.IP[2] = 168));
 else Result := False;
end;
end;

function NET_CompareBaseAdr(const A1, A2: TNetAdr): Boolean;
begin
if A1.AddrType <> A2.AddrType then
 Result := False
else
 case A1.AddrType of
  NA_LOOPBACK: Result := True;
  NA_IP: Result := PUInt32(@A1.IP)^ = PUInt32(@A2.IP)^;
  else Result := False;
 end;
end;

function NET_AdrToString(const A: TNetAdr; out Buf; L: UInt): PLChar; overload;
var
 I: Int;
 S: PLChar;
 AdrBuf: array[1..64] of LChar;
begin
if (@Buf = nil) or (L = 0) then
 Result := nil
else
 begin
  case A.AddrType of
   NA_LOOPBACK: StrLCopy(@Buf, 'loopback', L - 1);
   NA_IP, NA_BROADCAST:
    begin
     S := @AdrBuf;

     for I := 1 to 4 do
      begin
       S := IntToStrE(A.IP[I], S^, 4);
       S^ := '.';
       Inc(UInt(S));
      end;

     PLChar(UInt(S) - 1)^ := ':';
     IntToStr(ntohs(A.Port), S^, 6);
     StrLCopy(@Buf, @AdrBuf, L - 1);
    end;
   else StrLCopy(@Buf, '(bad address)', L - 1);
  end;

  Result := @Buf;
 end;
end;

function NET_BaseAdrToString(const A: TNetAdr; out Buf; L: UInt): PLChar;
var
 I: Int;
 S: PLChar;
 AdrBuf: array[1..64] of LChar;
begin
if (@Buf = nil) or (L = 0) then
 Result := nil
else
 begin
  case A.AddrType of
   NA_LOOPBACK: StrLCopy(@Buf, 'loopback', L - 1);
   NA_IP, NA_BROADCAST:
    begin
     S := @AdrBuf;

     for I := 1 to 4 do
      begin
       S := IntToStrE(A.IP[I], S^, 4);
       S^ := '.';
       Inc(UInt(S));
      end;

     PLChar(UInt(S) - 1)^ := #0;
     StrLCopy(@Buf, @AdrBuf, L - 1);
    end;
   else StrLCopy(@Buf, '(bad address)', L - 1);
  end;

  Result := @Buf;
 end;
end;

function NET_StringToSockaddr(Name: PLChar; out S: TSockAddr): Boolean;
var
 Buf: array[1..1024] of LChar;
 S2: PLChar;
 I: Int32;
 E: PHostEnt;
begin
Result := True;

S.sin_family := AF_INET;
MemSet(S.sin_zero, SizeOf(S.sin_zero), 0);

StrLCopy(@Buf, Name, SizeOf(Buf) - 1);
S2 := StrPos(PLChar(@Buf), ':');
if S2 <> nil then
 begin
  S2^ := #0;
  S.sin_port := StrToInt(PLChar(UInt(S2) + 1));
  if S.sin_port <> 0 then
   S.sin_port := htons(S.sin_port);
 end
else
 S.sin_port := 0;

I := inet_addr(@Buf);
if I = INADDR_NONE then
 begin
  E := gethostbyname(@Buf);
  if (E = nil) or (E.h_addr_list = nil) or (E.h_addr_list^ = nil) then
   begin
    S.sin_addr.S_addr := 0;
    Result := False;
   end
  else
   I := PInt32(E.h_addr_list^)^;
 end;

S.sin_addr.S_addr := I;
end;

function NET_StringToAdr(S: PLChar; out A: TNetAdr): Boolean;
var
 SAdr: TSockAddr;
begin         
if StrComp(S, 'localhost') = 0 then
 begin
  MemSet(A, SizeOf(A), 0);
  A.AddrType := NA_LOOPBACK;
  Result := True;
 end
else
 begin
  Result := NET_StringToSockaddr(S, SAdr);
  if Result then
   SockadrToNetadr(SAdr, A);
 end;
end;

function NET_IsLocalAddress(const A: TNetAdr): Boolean;
begin
Result := A.AddrType = NA_LOOPBACK;
end;

function NET_ErrorString(E: UInt): PLChar;
begin
{$IFDEF MSWINDOWS}
case E of
 WSAEINTR: Result := 'WSAEINTR';
 WSAEBADF: Result := 'WSAEBADF';
 WSAEACCES: Result := 'WSAEACCES';
 WSAEFAULT: Result := 'WSAEFAULT';
 WSAEINVAL: Result := 'WSAEINVAL';
 WSAEMFILE: Result := 'WSAEMFILE';
 WSAEWOULDBLOCK: Result := 'WSAEWOULDBLOCK';
 WSAEINPROGRESS: Result := 'WSAEINPROGRESS';
 WSAEALREADY: Result := 'WSAEALREADY';
 WSAENOTSOCK: Result := 'WSAENOTSOCK';
 WSAEDESTADDRREQ: Result := 'WSAEDESTADDRREQ';
 WSAEMSGSIZE: Result := 'WSAEMSGSIZE';
 WSAEPROTOTYPE: Result := 'WSAEPROTOTYPE';
 WSAENOPROTOOPT: Result := 'WSAENOPROTOOPT';
 WSAEPROTONOSUPPORT: Result := 'WSAEPROTONOSUPPORT';
 WSAESOCKTNOSUPPORT: Result := 'WSAESOCKTNOSUPPORT';
 WSAEOPNOTSUPP: Result := 'WSAEOPNOTSUPP';
 WSAEPFNOSUPPORT: Result := 'WSAEPFNOSUPPORT';
 WSAEAFNOSUPPORT: Result := 'WSAEAFNOSUPPORT';
 WSAEADDRINUSE: Result := 'WSAEADDRINUSE';
 WSAEADDRNOTAVAIL: Result := 'WSAEADDRNOTAVAIL';
 WSAENETDOWN: Result := 'WSAENETDOWN';
 WSAENETUNREACH: Result := 'WSAENETUNREACH';
 WSAENETRESET: Result := 'WSAENETRESET';
 WSAECONNABORTED: Result := 'WSAECONNABORTED';
 WSAECONNRESET: Result := 'WSAECONNRESET';
 WSAENOBUFS: Result := 'WSAENOBUFS';
 WSAEISCONN: Result := 'WSAEISCONN';
 WSAENOTCONN: Result := 'WSAENOTCONN';
 WSAESHUTDOWN: Result := 'WSAESHUTDOWN';
 WSAETOOMANYREFS: Result := 'WSAETOOMANYREFS';
 WSAETIMEDOUT: Result := 'WSAETIMEDOUT';
 WSAECONNREFUSED: Result := 'WSAECONNREFUSED';
 WSAELOOP: Result := 'WSAELOOP';
 WSAENAMETOOLONG: Result := 'WSAENAMETOOLONG';
 WSAEHOSTDOWN: Result := 'WSAEHOSTDOWN';
 WSAEHOSTUNREACH: Result := 'WSAEHOSTUNREACH';
 WSAENOTEMPTY: Result := 'WSAENOTEMPTY';
 WSAEPROCLIM: Result := 'WSAEPROCLIM';
 WSAEUSERS: Result := 'WSAEUSERS';
 WSAEDQUOT: Result := 'WSAEDQUOT';
 WSAESTALE: Result := 'WSAESTALE';
 WSAEREMOTE: Result := 'WSAEREMOTE';
 WSASYSNOTREADY: Result := 'WSASYSNOTREADY';
 WSAVERNOTSUPPORTED: Result := 'WSAVERNOTSUPPORTED';
 WSANOTINITIALISED: Result := 'WSANOTINITIALISED';
 WSAEDISCON: Result := 'WSAEDISCON';
 WSAHOST_NOT_FOUND: Result := 'WSAHOST_NOT_FOUND';
 WSATRY_AGAIN: Result := 'WSATRY_AGAIN';
 WSANO_RECOVERY: Result := 'WSANO_RECOVERY';
 WSANO_DATA: Result := 'WSANO_DATA';
 else
  Result := 'NO ERROR';
end;
{$ELSE}
 Result := strerror(E);
{$ENDIF}
end;

procedure NET_TransferRawData(var S: TSizeBuf; Data: Pointer; Size: UInt);
begin
if Size > S.MaxSize then
 begin
  DPrint('NET_TransferRawData: Buffer overflow.');
  Size := S.MaxSize;
 end;

S.CurrentSize := Size;
if Size > 0 then
 Move(Data^, S.Data^, Size);
end;

function NET_GetLoopPacket(Source: TNetSrc; var A: TNetAdr; var SB: TSizeBuf): Boolean;
var
 P: PLoopBack;
 I: Int;
begin
if Source > NS_SERVER then
 Result := False
else
 begin
  P := @Loopbacks[Source];
  if P.Send - P.Get > MAX_LOOPBACK then
   P.Get := P.Send - MAX_LOOPBACK;

  if P.Get < P.Send then
   begin
    I := P.Get and (MAX_LOOPBACK - 1);
    Inc(P.Get);

    NET_TransferRawData(SB, @P.Msgs[I].Data, P.Msgs[I].Size);
    MemSet(A, SizeOf(A), 0);
    A.AddrType := NA_LOOPBACK;
    Result := True;
   end
  else
   Result := False;
 end;
end;

procedure NET_SendLoopPacket(Source: TNetSrc; Size: UInt; Buffer: Pointer);
const
 A: array[TNetSrc] of TNetSrc = (NS_SERVER, NS_CLIENT, NS_MULTICAST);
var
 P: PLoopBack;
 I: Int;
begin
P := @Loopbacks[A[Source]];
I := P.Send and (MAX_LOOPBACK - 1);
Inc(P.Send);
if Size > MAX_PACKETLEN then
 begin
  DPrint('NET_SendLoopPacket: Buffer overflow.');
  Size := MAX_PACKETLEN;
 end;

P.Msgs[I].Size := Size;
if Size > 0 then
 Move(Buffer^, P.Msgs[I].Data, Size);
end;

procedure NET_RemoveFromPacketList(P: PLagPacket);
begin
P.Next.Prev := P.Prev;
P.Prev.Next := P.Next;
P.Next := nil;
P.Prev := nil;
end;

function NET_CountLaggedList(P: PLagPacket): Int;
var
 P2: PLagPacket;
begin
Result := 0;
if P <> nil then
 begin
  P2 := P.Prev;
  while (P2 <> nil) and (P2 <> P) do
   begin
    Inc(Result);
    P2 := P2.Prev;
   end;
 end;
end;

procedure NET_ClearLaggedList(P: PLagPacket);
var
 P2, P3: PLagPacket;
begin
P2 := P.Prev;
while (P2 <> nil) and (P2 <> P) do
 begin
  P3 := P2.Prev;
  NET_RemoveFromPacketList(P2);
  if P2.Data <> nil then
   Mem_Free(P2.Data);
  Mem_Free(P2);
  P2 := P3;
 end;

P.Next := P;
P.Prev := P;
end;

procedure NET_AddToLagged(Source: TNetSrc; Base, New: PLagPacket; const A: TNetAdr; const SB: TSizeBuf; Time: Single);
begin
if New = nil then
 DPrint('NET_AddToLagged: Bad packet.')
else
 if (New.Prev <> nil) or (New.Next <> nil) then
  DPrint('NET_AddToLagged: Packet already linked.')
 else
  begin
   New.Data := Mem_Alloc(SB.CurrentSize);
   if New.Data = nil then
    DPrint(['NET_AddToLagged: Failed to allocate ', SB.CurrentSize, ' bytes.'])
   else
    begin
     New.Size := SB.CurrentSize;

     New.Next := Base.Next;
     Base.Next.Prev := New;
     Base.Next := New;
     New.Prev := Base;

     Move(SB.Data^, New.Data^, New.Size);
     New.Addr := A;
     New.Time := Time;
    end;
  end;
end;

procedure NET_AdjustLag;
var
 X, D, SD: Double;
begin
if not AllowCheats and (fakelag.Value <> 0) then
 begin
  Print('Server must enable cheats to activate fakelag.');
  CVar_DirectSet(fakelag, '0');
  FakeLagTime := 0;
 end
else
 if AllowCheats and (fakelag.Value <> FakeLagTime) then
  begin
   X := RealTime - LastLagTime;
   if X < 0 then
    X := 0
   else
    if X > 0.1 then
     X := 0.1;

   LastLagTime := RealTime;

   D := fakelag.Value - FakeLagTime;
   SD := X * 200;
   if Abs(D) < SD then
    SD := Abs(D);
   if D < 0 then
    SD := -SD;
   FakeLagTime := FakeLagTime + SD;
  end;
end;

function NET_LagPacket(Add: Boolean; Source: TNetSrc; A: PNetAdr; SB: PSizeBuf): Boolean;
var
 S: Single;
 P, P2: PLagPacket;
begin
if FakeLagTime <= 0 then
 begin
  NET_ClearLagData(False, True);
  Result := Add;
  Exit;
 end;

Result := False;

if Add then
 begin
  S := fakeloss.Value;
  if S <> 0 then
   if AllowCheats then
    begin
     Inc(LossCount[Source]);
     if S < 0 then
      begin
       S := Trunc(Abs(S));
       if S < 2 then
        S := 2;
       if (LossCount[Source] mod Trunc(S)) = 0 then
        Exit;
      end
     else
      if RandomLong(0, 100) <= Trunc(S) then
       Exit;
    end
   else
    CVar_DirectSet(fakeloss, '0');

  if (A <> nil) and (SB <> nil) then
   NET_AddToLagged(Source, @LagData[Source], Mem_ZeroAlloc(SizeOf(TLagPacket)), A^, SB^, RealTime);
 end;

P := LagData[Source].Prev;
P2 := @LagData[Source];

if P = P2 then
 Exit;

S := RealTime - FakeLagTime / 1000;
while P.Time > S do
 begin
  P := P.Prev;
  if P = P2 then
   Exit;
 end;

NET_RemoveFromPacketList(P);
if P.Data <> nil then
 begin
  NET_TransferRawData(InMessage, P.Data, P.Size);
  Move(P.Addr, InFrom, SizeOf(InFrom));
  Mem_Free(P.Data);
 end
else
 Move(P.Addr, InFrom, SizeOf(InFrom));

Mem_Free(P);
Result := True;
end;

procedure NET_FlushSocket(Source: TNetSrc);
var
 S: TSocket;
 AddrLen: Int32;
 Buf: array[1..MAX_MESSAGELEN] of Byte;
 A: TSockAddr;
begin
S := IPSockets[Source];
if S > 0 then
 begin
  AddrLen := SizeOf(A);
  {$IFDEF MSWINDOWS}
  while recvfrom(S, Buf, SizeOf(Buf), 0, A, AddrLen) > 0 do ;
  {$ELSE}
  while recvfrom(S, Buf, SizeOf(Buf), 0, @A, @AddrLen) > 0 do ;
  {$ENDIF}
 end;
end;

function NET_FindSplitContext(const Addr: TNetAdr): PSplitContext;
var
 I, J, Index: UInt;
 P: PSplitContext; 
 MinTime: Double;
begin
MinTime := RealTime;
Index := 0;

for I := 0 to MAX_SPLIT_CTX - 1 do
 begin
  J := (CurrentCtx - I) and (MAX_SPLIT_CTX - 1);
  P := @SplitCtx[J];
  if NET_CompareAdr(P.Addr, Addr) then
   begin
    Result := P;
    Exit;
   end
  else
   if P.Time < MinTime then
    begin
     MinTime := P.Time;
     Index := J;
    end;
 end;

P := @SplitCtx[Index];
P.Addr := Addr;
P.PacketsLeft := -1;
CurrentCtx := Index;
Result := P;
end;

procedure NET_ClearSplitContexts;
var
 I: UInt;
 P: PSplitContext;
begin
for I := 0 to MAX_SPLIT_CTX - 1 do
 begin
  P := @SplitCtx[I];
  MemSet(P.Addr, SizeOf(P.Addr), 0);
  P.Time := 0;
 end;
end;

function NET_GetLong(Data: Pointer; Size: UInt; out OutSize: UInt; const Addr: TNetAdr): Boolean;
var
 Header: TSplitHeader;
 CurSplit, MaxSplit: UInt;
 P: PSplitContext;
 I: Int;
begin
Result := False;

Move(Data^, Header, SizeOf(Header));
CurSplit := Header.Index shr 4;
MaxSplit := Header.Index and $F;

if (CurSplit >= MAX_SPLIT) or (CurSplit >= MaxSplit) then
 DPrint(['Malformed split packet current number (', CurSplit, ').'])
else
 if (MaxSplit > MAX_SPLIT) or (MaxSplit = 0) then
  DPrint(['Malformed split packet max number (', MaxSplit, ').'])
 else
  begin
   P := NET_FindSplitContext(Addr);
   if (P.PacketsLeft <= 0) or (P.Sequence <> Header.SplitSeq) then
    begin
     if net_showpackets.Value = 4 then
      if P.PacketsLeft = -1 then
       DPrint(['New split context with ', MaxSplit, ' packets, sequence = ', Header.SplitSeq, '.'])
      else
       DPrint(['Restarting split context with ', MaxSplit, ' packets, sequence = ', Header.SplitSeq, '.']);

     P.Time := RealTime;
     P.PacketsLeft := MaxSplit;
     P.Sequence := Header.SplitSeq;
     P.Size := 0;
     P.Ack := [];
    end
   else
    if net_showpackets.Value = 4 then
     DPrint(['Found existing split context with ', MaxSplit, ' packets, sequence = ', Header.SplitSeq, '.']);

   Dec(Size, SizeOf(Header));
   if CurSplit in P.Ack then
    DPrint(['Received duplicated split fragment (num = ', CurSplit + 1, '/', MaxSplit, ', sequence = ', Header.SplitSeq, '), ignoring.'])
   else
    if P.Size + Size > MAX_MESSAGELEN then
     DPrint(['Split context overflowed with ', P.Size + Size, ' bytes (num = ', CurSplit + 1, '/', MaxSplit, ', sequence = ', Header.SplitSeq, ').'])
    else
     begin
      if net_showpackets.Value = 4 then
       DPrint(['Received split fragment (num = ', CurSplit + 1, '/', MaxSplit, ', sequence = ', Header.SplitSeq, ').']);

      Dec(P.PacketsLeft);
      Include(P.Ack, CurSplit);
      Move(Pointer(UInt(Data) + SizeOf(Header))^, Pointer(UInt(@P.Data) + P.Size)^, Size);
      Inc(P.Size, Size);

      if P.PacketsLeft = 0 then
       begin
        for I := 0 to MaxSplit - 1 do
         if not (I in P.Ack) then
          begin
           DPrint(['Received a split packet without all ', MaxSplit, ' parts; sequence = ', Header.SplitSeq, ', ignoring.']);
           Exit;
          end;

        DPrint(['Received a split packet with sequence = ', Header.SplitSeq, '.']);

        Move(P.Data, Data^, P.Size);
        OutSize := P.Size;

        MemSet(P.Addr, SizeOf(P.Addr), 0);
        P.Time := 0;
        Result := True;
       end;
     end;
  end;
end;

function NET_QueuePacket(Source: TNetSrc): Boolean;
var
 S: TSocket;
 Buf: array[1..MAX_MESSAGELEN] of Byte;
 NetAdrBuf: array[1..64] of LChar;
 A: TSockAddr;
 AddrLen: Int32;
 Size: UInt;
 E: Int;
begin
S := IPSockets[Source];
if S > 0 then
 begin
  AddrLen := SizeOf(TSockAddr);
  {$IFDEF MSWINDOWS}
  E := recvfrom(S, Buf, SizeOf(Buf), 0, A, AddrLen);
  {$ELSE}
  E := recvfrom(S, Buf, SizeOf(Buf), 0, @A, @AddrLen);
  {$ENDIF}
  if E = SOCKET_ERROR then
   begin
    E := NET_LastError;
    if E = {$IFDEF MSWINDOWS}WSAEMSGSIZE{$ELSE}EMSGSIZE{$ENDIF} then
     DPrint(['NET_QueuePacket: Ignoring oversized network message, allowed no more than ', MAX_MESSAGELEN, ' bytes.'])
    else
     {$IFDEF MSWINDOWS}
     if (E <> WSAEWOULDBLOCK) and (E <> WSAECONNRESET) and (E <> WSAECONNREFUSED) then
     {$ELSE}
     if (E <> EAGAIN) and (E <> ECONNRESET) and (E <> ECONNREFUSED) then
     {$ENDIF}
      Print(['NET_QueuePacket: Network error "', NET_ErrorString(E), '".']);
   end
  else
   begin
    SockadrToNetadr(A, InFrom);
    if E > SizeOf(Buf) then
     DPrint(['NET_QueuePacket: Oversized packet from ', NET_AdrToString(InFrom, NetAdrBuf, SizeOf(NetAdrBuf)), '.'])
    else
     begin
      Size := E;
      NET_TransferRawData(InMessage, @Buf, Size);
      if PInt32(InMessage.Data)^ = SPLIT_TAG then
       if InMessage.CurrentSize >= SizeOf(TSplitHeader) then
        Result := NET_GetLong(InMessage.Data, Size, InMessage.CurrentSize, InFrom)
       else
        begin
         DPrint(['NET_QueuePacket: Invalid incoming split packet length (', InMessage.CurrentSize, '), should be no lesser than ', SizeOf(TSplitHeader), '.']);
         Result := NET_LagPacket(False, Source, nil, nil);
        end
      else
       Result := NET_LagPacket(True, Source, @InFrom, @InMessage);

      Exit;
     end;
   end;
 end;

Result := NET_LagPacket(False, Source, nil, nil);
end;

function NET_AllocMsg(Size: UInt): PNetQueue;
var
 P: PNetQueue;
begin
if (Size <= NET_QUEUESIZE) and (NormalQueue <> nil) then
 begin
  P := NormalQueue;
  P.Size := Size;
  P.Normal := True;
  NormalQueue := P.Prev;
 end
else
 begin
  P := Mem_ZeroAlloc(SizeOf(P^));
  P.Data := Mem_ZeroAlloc(Size);
  P.Size := Size;
  P.Normal := False;
 end;

Result := P;
end;

procedure NET_FreeMsg(P: PNetQueue);
begin
if P.Normal then
 begin
  P.Prev := NormalQueue;
  NormalQueue := P;
 end
else
 begin
  Mem_Free(P.Data);
  Mem_Free(P);
 end;
end;

procedure NET_AllocateQueues;
var
 I: UInt;
 P: PNetQueue;
begin
for I := 1 to MAX_NET_QUEUES do
 begin
  P := Mem_ZeroAlloc(SizeOf(P^));
  P.Prev := NormalQueue;
  P.Normal := True;
  P.Data := Mem_ZeroAlloc(NET_QUEUESIZE);
  NormalQueue := P;
 end;
end;

procedure NET_FlushQueues;
var
 I: TNetSrc;
 P, P2: PNetQueue;
begin
for I := Low(I) to High(I) do
 begin
  P := NetMessages[I];
  while P <> nil do
   begin
    P2 := P.Prev;
    Mem_Free(P.Data);
    Mem_Free(P);
    P := P2;
   end;
  NetMessages[I] := nil;
 end;

P := NormalQueue;
while P <> nil do
 begin
  P2 := P.Prev;
  Mem_Free(P.Data);
  Mem_Free(P);
  P := P2;
 end;
NormalQueue := nil;
end;

function NET_GetPacket(Source: TNetSrc): Boolean;
var
 B: Boolean;
 P: PNetQueue;
begin
NET_AdjustLag;
if NET_GetLoopPacket(Source, InFrom, InMessage) then
 B := NET_LagPacket(True, Source, @InFrom, @InMessage)
else
 if not NET_QueuePacket(Source) then
  B := NET_LagPacket(False, Source, nil, nil)
 else
  B := True;

if B then
 begin
  NetMessage.CurrentSize := InMessage.CurrentSize;
  Move(InMessage.Data^, NetMessage.Data^, NetMessage.CurrentSize);
  NetFrom := InFrom;
  Result := True;
 end
else
 begin
  P := NetMessages[Source];
  if P <> nil then
   begin
    NetMessages[Source] := P.Prev;
    NetMessage.CurrentSize := P.Size;
    Move(P.Data^, NetMessage.Data^, NetMessage.CurrentSize);
    NetFrom := P.Addr;
    NET_FreeMsg(P);
    Result := True;
   end
  else
   Result := False;
 end;
end;

var
 SplitSeq: Int = 1;
 
function NET_SendLong(Source: TNetSrc; Socket: TSocket; Buffer: Pointer; Size: UInt; const NetAdr: TNetAdr; var SockAddr: TSockAddr; AddrLength: UInt): Int;
var
 Buf: packed record
  Header: TSplitHeader;
  Data: array[0..MAX_SPLIT_FRAGLEN - 1] of Byte;
 end;
 CurSplit, MaxSplit, SentBytes, RemainingBytes, ThisBytes: UInt;
 E: Int;
 ShowPackets: Boolean;
 AdrBuf: array[1..64] of LChar;
begin
if (Size <= MAX_FRAGLEN) or (Source <> NS_SERVER) then
 Result := sendto(Socket, Buffer^, Size, 0, SockAddr, AddrLength)
else
 begin
  MaxSplit := (Size + MAX_SPLIT_FRAGLEN - 1) div MAX_SPLIT_FRAGLEN;
  if MaxSplit > MAX_SPLIT then
   begin
    DPrint(['Refusing to send split packet to ', NET_AdrToString(NetAdr, AdrBuf, SizeOf(AdrBuf)), ', the packet is too big (', Size, ' bytes).']);
    Result := 0;    
   end
  else
   begin
    Inc(SplitSeq);
    if SplitSeq < 0 then
     SplitSeq := 1;
    Buf.Header.Seq := SPLIT_TAG;
    Buf.Header.SplitSeq := SplitSeq;

    CurSplit := 0;
    SentBytes := 0;
    ShowPackets := net_showpackets.Value = 4;
    RemainingBytes := Size;
    while RemainingBytes > 0 do
     begin
      if RemainingBytes >= MAX_SPLIT_FRAGLEN then
       ThisBytes := MAX_SPLIT_FRAGLEN
      else
       ThisBytes := RemainingBytes;

      Buf.Header.Index := MaxSplit or (CurSplit shl 4);
      Move(Buffer^, Buf.Data, ThisBytes);
      if ShowPackets then
       DPrint(['Sending split packet #', CurSplit + 1, ' of ', MaxSplit, ' (size = ', ThisBytes, ' bytes, sequence = ', SplitSeq, ') to ', NET_AdrToString(NetAdr, AdrBuf, SizeOf(AdrBuf)), '.']);

      E := sendto(Socket, Buf, SizeOf(TSplitHeader) + ThisBytes, 0, SockAddr, AddrLength);
      if E < 0 then
       begin
        Result := E;
        Exit;
       end
      else
       begin
        Inc(SentBytes, E);
        Inc(CurSplit);
        Dec(RemainingBytes, ThisBytes);
        Inc(UInt(Buffer), ThisBytes);
       end;
     end;
     
    Result := SentBytes;
   end;
 end;
end;

procedure NET_SendPacket(Source: TNetSrc; Size: UInt; Buffer: Pointer; const Dest: TNetAdr);
var
 AddrType: TNetAdrType;
 S: TSocket;
 A: TSockAddr;
 E: Int;
begin
AddrType := Dest.AddrType;
if (AddrType = NA_IP) or (AddrType = NA_BROADCAST) then
 begin
  S := IPSockets[Source];
  if S > 0 then
   begin
    NetadrToSockadr(Dest, A);
    if NET_SendLong(Source, S, Buffer, Size, Dest, A, SizeOf(A)) = SOCKET_ERROR then
     begin
      E := NET_LastError;
      {$IFDEF MSWINDOWS}
      if (E <> WSAEWOULDBLOCK) and (E <> WSAECONNREFUSED) and (E <> WSAECONNRESET) and
         ((E <> WSAEADDRNOTAVAIL) or (Dest.AddrType <> NA_BROADCAST)) then
      {$ELSE}
      if (E <> EAGAIN) and (E <> ECONNREFUSED) and (E <> ECONNRESET) and
         ((E <> EADDRNOTAVAIL) or (Dest.AddrType <> NA_BROADCAST)) then
      {$ENDIF}
       Print(['NET_SendPacket: Network error "', NET_ErrorString(E), '".']);
     end;
   end;
 end
else
 if AddrType = NA_LOOPBACK then
  NET_SendLoopPacket(Source, Size, Buffer)
 else
  Sys_Error(['NET_SendPacket: Bad address type (', UInt(AddrType), ').']);
end;

function NET_IPSocket(IP: PLChar; Port: UInt16; Reuse: Boolean): TSocket;
var
 S: TSocket;
 A: TSockAddr;
 I: Int32;
 E: Int;
begin
S := socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
if S = INVALID_SOCKET then
 begin
  E := NET_LastError;
  if E <> {$IFDEF MSWINDOWS}WSAEAFNOSUPPORT{$ELSE}EAFNOSUPPORT{$ENDIF} then
   Print(['Error: Can''t allocate socket on port ', Port, ' - ', NET_ErrorString(E), '.']);
 end
else
 begin
  I := 1;
  if {$IFDEF MSWINDOWS}ioctlsocket{$ELSE}ioctl{$ENDIF}(S, FIONBIO, I) = SOCKET_ERROR then
   Print(['Error: Can''t set non-blocking I/O for socket on port ', Port, ' - ', NET_ErrorString(NET_LastError), '.'])
  else
   begin
    I := 1;
    if setsockopt(S, SOL_SOCKET, SO_BROADCAST, @I, SizeOf(I)) = SOCKET_ERROR then
     Print(['Warning: Can''t enable broadcast capability for socket on port ', Port, ' - ', NET_ErrorString(NET_LastError), '.']);

    I := 1;
    if (Reuse or (COM_CheckParm('-reuse') > 0)) and (setsockopt(S, SOL_SOCKET, SO_REUSEADDR, @I, SizeOf(I)) = SOCKET_ERROR) then
     Print(['Warning: Can''t allow address reuse for socket on port ', Port, ' - ', NET_ErrorString(NET_LastError), '.']);

    I := Int32(COM_CheckParm('-loopback') > 0);
    if setsockopt(S, IPPROTO_IP, IP_MULTICAST_LOOP, @I, SizeOf(I)) = SOCKET_ERROR then
     Print(['Warning: Can''t set multicast loopback for socket on port ', Port, ' - ', NET_ErrorString(NET_LastError), '.']);
    
    if COM_CheckParm('-tos') > 0 then
     begin
      I := IPTOS_LOWDELAY;
      if setsockopt(S, IPPROTO_IP, IP_TOS, @I, SizeOf(I)) = SOCKET_ERROR then
       Print(['Warning: Can''t set LOWDELAY TOS for socket on port ', Port, ' - ', NET_ErrorString(NET_LastError), '.'])
      else
       DPrint('LOWDELAY TOS option enabled.');
     end;

    MemSet(A, SizeOf(A), 0);
    A.sin_family := AF_INET;
    if (IP^ > #0) and (StrIComp(IP, 'localhost') <> 0) then
     NET_StringToSockaddr(IP, A);
    A.sin_port := htons(Port);

    if bind(S, A, SizeOf(A)) = SOCKET_ERROR then
     Print(['Error: Can''t bind socket on port ', Port, ' - ', NET_ErrorString(NET_LastError), '.'])
    else
     begin
      Result := S;
      Exit;
     end;
   end;

  {$IFDEF MSWINDOWS}shutdown(S, SD_BOTH); closesocket(S);
  {$ELSE}shutdown(S, SHUT_RDWR); __close(S);{$ENDIF};
 end;

Result := 0;
end;

procedure NET_OpenIP;
var
 P: Single;
begin
if IPSockets[NS_SERVER] = 0 then
 begin
  P := ip_hostport.Value;
  if P = 0 then
   begin
    P := hostport.Value;
    if P = 0 then
     begin
      CVar_SetValue('hostport', defport.Value);
      P := defport.Value;
      if P = 0 then
       P := NET_SERVERPORT;
     end;
   end;

  IPSockets[NS_SERVER] := NET_IPSocket(ipname.Data, Trunc(P), False);
  if IPSockets[NS_SERVER] = 0 then
   Sys_Error(['Couldn''t allocate dedicated server IP on port ', Trunc(P), '.' + sLineBreak +
              'Try using a different port by specifying either -port X or +hostport X in the commandline parameters.']);
 end;
end;

procedure NET_GetLocalAddress;
var
 Buf: array[1..256] of LChar;
 AdrBuf: array[1..32] of LChar;
 NL: {$IFDEF MSWINDOWS}Int32{$ELSE}UInt32{$ENDIF};
 S: TSockAddr;
begin
if not NoIP then
 begin
  if StrIComp(ipname.Data, 'localhost') = 0 then
   begin
    gethostname(@Buf, SizeOf(Buf));
    Buf[High(Buf)] := #0;
   end
  else
   StrLCopy(@Buf, ipname.Data, SizeOf(Buf) - 1);

  NET_StringToAdr(@Buf, LocalIP);
  NL := SizeOf(TSockAddr);
  if getsockname(IPSockets[NS_SERVER], S, NL) <> 0 then
   begin
    NoIP := True;
    Print(['Couldn''t get TCP/IP address, TCP/IP disabled.' + sLineBreak +
           'Reason: ', NET_ErrorString(NET_LastError), '.']);
   end
  else
   begin
    LocalIP.Port := S.sin_port;
    Print(['Server IP address: ', NET_AdrToString(LocalIP, AdrBuf, SizeOf(AdrBuf)), '.']);
    CVar_DirectSet(net_address, @Buf);
    Exit;
   end;
 end
else
 Print('TCP/IP disabled.');

MemSet(LocalIP, SizeOf(LocalIP), 0);
end;

function NET_IsConfigured: Boolean;
begin
Result := NetInit;
end;

procedure NET_Config(EnableNetworking: Boolean);
var
 I: TNetSrc;
 S: TSocket;
begin
if OldConfig <> EnableNetworking then
 begin
  OldConfig := EnableNetworking;
  if EnableNetworking then
   begin
    if not NoIP then
     NET_OpenIP;

    if FirstInit then
     begin
      FirstInit := False;
      NET_GetLocalAddress;
     end;

    NET_ClearSplitContexts;
    NetInit := True;
   end
  else
   begin
    for I := Low(TNetSrc) to High(TNetSrc) do
     begin
      S := IPSockets[I];
      if S > 0 then
       begin
        {$IFDEF MSWINDOWS}shutdown(S, SD_RECEIVE); closesocket(S);
        {$ELSE}shutdown(S, SHUT_RD); __close(S);{$ENDIF}
        IPSockets[I] := 0;
       end;
     end;
    NetInit := False;
   end;
 end;
end;

procedure NET_Init;
var
 I: UInt;
 J: TNetSrc;
 P: PLagPacket;
begin
CVar_RegisterVariable(clockwindow);
CVar_RegisterVariable(net_address);
CVar_RegisterVariable(ipname);
CVar_RegisterVariable(ip_hostport);
CVar_RegisterVariable(hostport);
CVar_RegisterVariable(defport);
CVar_RegisterVariable(fakelag);
CVar_RegisterVariable(fakeloss);

NoIP := COM_CheckParm('-noip') > 0;

I := COM_CheckParm('-port');
if I > 0 then
 CVar_DirectSet(hostport, COM_ParmValueByIndex(I));

I := COM_CheckParm('-clockwindow');
if I > 0 then
 CVar_DirectSet(clockwindow, COM_ParmValueByIndex(I));

NetMessage.Name := 'net_message';
NetMessage.AllowOverflow := [FSB_ALLOWOVERFLOW];
NetMessage.Data := @NetMsgBuffer;
NetMessage.MaxSize := SizeOf(NetMsgBuffer);
NetMessage.CurrentSize := 0;

InMessage.Name := 'in_message';
InMessage.AllowOverflow := [];
InMessage.Data := @InMsgBuffer;
InMessage.MaxSize := SizeOf(InMsgBuffer);
InMessage.CurrentSize := 0;

for J := Low(LagData) to High(LagData) do
 begin
  P := @LagData[J];
  P.Prev := P;
  P.Next := P;
 end;

NET_AllocateQueues;
NET_ClearSplitContexts;
DPrint('Base networking initialized.');
end;

procedure NET_ClearLagData(Client, Server: Boolean);
begin
if Client then
 begin
  NET_ClearLaggedList(@LagData[NS_CLIENT]);
  NET_ClearLaggedList(@LagData[NS_MULTICAST]);
 end;
if Server then
 NET_ClearLaggedList(@LagData[NS_SERVER]);
end;

procedure NET_Shutdown;
begin
NET_ClearLagData(True, True);
NET_Config(False);
NET_FlushQueues;
end;




{$IFDEF MSWINDOWS}
var
 WSA: TWSAData;

initialization
 WSAStartup($202, WSA);

finalization
 WSACleanup;
{$ENDIF}
                    
end.
