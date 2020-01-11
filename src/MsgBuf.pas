unit MsgBuf;

interface

uses
  Default, SDK, SizeBuf, MathLib;

procedure MSG_ReadUserCmd(var SB: TSizeBuf; Dest, Source: PUserCmd);

implementation

uses Common, Delta, Memory, SVDelta, SysMain;

procedure MSG_ReadUserCmd(var SB: TSizeBuf; Dest, Source: PUserCmd);
begin
SB.StartBitReading;
UserCmdDelta.ParseDelta(SB, Source, Dest);
SB.EndBitReading;
COM_NormalizeAngles(Dest.ViewAngles);
end;

end.
