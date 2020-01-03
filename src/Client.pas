unit Client;

interface

uses
  Default, SDK, Netchan;

type
 PClient = ^TClient; // 20488 W, 20200 L
 TClient = record
  Active: Boolean; // +0, cf
  Spawned: Boolean; // +4, cf
  SendInfo: Boolean; // +8 cf
  Connected: Boolean; // +12 cf
  HasMissingResources: Boolean; // +16 cf (need missing resources)
  UserMsgReady: Boolean; // +20 cf SV_New
  NeedConsistency: Boolean; // +24 cf

  Netchan: TNetchan; // +32?  124 is netmessage (92 + 32)
  ChokeCount: UInt32; // 9536 W, cf, unsigned
  UpdateMask: Int32; // 9540 W, cf signed
  FakeClient: Boolean; // 9272 L 9544 W
  HLTV: Boolean; // 9548 W, cf
  UserCmd: TUserCmd; // 9552 W, cf  size 52

  FirstCmd: Double; // 9608 W, cf
  LastCmd: Double; // 9616 W, cf
  NextCmd: Double; // 9624 W, cf
  Latency: Single; // 9632 W, cf, single (ping)
  PacketLoss: Single; // 9636 W, cf, single

  NextPingTime: Double; // 9648 W, cf, double
  ClientTime: Double;  // 9656 W, cf, double
  UnreliableMessage: TSizeBuf; // 9664 W, yep
  UnreliableMessageData: array[1..MAX_DATAGRAM] of Byte; // 9684.. or more?

  ConnectTime: Double; // +13688 W cf
  NextUpdateTime: Double; // +13696 W cf
  UpdateRate: Double; // +13704 W cf        13424 L

  // ->
  NeedUpdate: Boolean; // 13712 W cf
  SkipThisUpdate: Boolean; // 13436 L  13716 W
  Frames: TClientFrameArrayPtr; // 13720 W
  Events: TEventState; // 13724 W cf

  // client edict pointer
  Entity: PEdict; // 19356 W cf
  Target: PEdict; // view entity, 19360 W cf
  UserID: UInt32; // 19364 W cf

  Auth: record
   AuthType: TAuthType; // +19368 cf
   // ?
   UniqueID: Int64;   // +19376 cf
   IP: array[1..4] of Byte; // +19384 cf
  end;

  // <-

  UserInfo: array[1..MAX_USERINFO_STRING] of LChar; // 19392 W cf
  UpdateInfo: Boolean; // 19648 W cf
  UpdateInfoTime: Single; // 19652 W
  CDKey: array[1..64] of LChar; // +19656 cf
  NetName: array[1..32] of LChar; // 19720 W cf
  TopColor: Int32; // 19752 W cf
  BottomColor: Int32; // 19756 W cf

  // server -> client
  DownloadList: TResource; // +19476 L   +19764 W
  // client -> server
  UploadList: TResource; // +19612 L   +19900 W
  UploadComplete: Boolean; // +20040 W cf
  Customization: TCustomization; // +20044 W cf

  MapCRC: TCRC; // +20208 W cf
  LW: Boolean; // weapon prediction;  +20212 W
  LC: Boolean; // lag compensation; +20216 W
  PhysInfo: array[1..256] of LChar; // +20220 W cf

  VoiceLoopback: Boolean; // +20476 cf
  BlockedVoice: set of 0..MAX_PLAYERS - 1; // +20480 W cf



  // Custom fields
  Protocol: Byte; // for double-protocol support

  // filters
  SendResTime: Double;
  SendEntsTime: Double;
  FullUpdateTime: Double;

  // an experimental filter for "new" command, it restricts the command to being sent only once during the single server sequence.
  ConnectSeq: UInt32;
  SpawnSeq: UInt32;

  NewCmdTime: Double;
  SpawnCmdTime: Double;

  FragSize: UInt;
  FragSizeUpdated: Boolean; // is it necessary to update the fragsize
 end;
 TClientArray = array[0..0] of TClient;


implementation

end.
