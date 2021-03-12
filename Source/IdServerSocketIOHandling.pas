unit IdServerSocketIOHandling;
interface
{$I wsdefines.inc}
uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  IdContext,
  IdCustomTCPServer,
  IdException,
  IdServerBaseHandling,
  IdSocketIOHandling;

type
  TIdServerSocketIOHandling = class(TIdBaseSocketIOHandling)
  protected
    procedure ProcessHeatbeatRequest(const AContext: ISocketIOContext; const AText: string); override;
  public
    function SendToAll(const AMessage: string; const ACallback: TSocketIOMsgJSON = nil; const AOnError: TSocketIOError = nil): Integer;
    procedure SendTo(const AContext: TIdServerContext; const AMessage: string; const ACallback: TSocketIOMsgJSON = nil;
      const AOnError: TSocketIOError= nil);
    function EmitEventToAll(const AEventName: string; const AData: string; const ACallback: TSocketIOMsgJSON = nil;
      const AOnError: TSocketIOError = nil): Integer; overload;
    function EmitEventToAll(const AEventName: string; const AData: TJSONValue; const ACallback: TSocketIOMsgJSON = nil;
      const AOnError: TSocketIOError = nil): Integer; overload;
    procedure EmitEventTo(const AContext: TIdServerContext; const AEventName: string; const AData: TJSONValue;
      const ACallback: TSocketIOMsgJSON = nil; const AOnError: TSocketIOError = nil); overload;
    procedure EmitEventTo(const AContext: ISocketIOContext; const AEventName: string; const AData: TJSONValue;
      const ACallback: TSocketIOMsgJSON = nil; const AOnError: TSocketIOError = nil); overload;
  end;

implementation

{ TIdServerSocketIOHandling }

procedure TIdServerSocketIOHandling.ProcessHeatbeatRequest(const AContext: ISocketIOContext; const AText: string);
begin
  inherited ProcessHeatbeatRequest(AContext, AText);
end;

procedure TIdServerSocketIOHandling.EmitEventTo(const AContext: ISocketIOContext; const AEventName: string; const AData: TJSONValue;
  const ACallback: TSocketIOMsgJSON; const AOnError: TSocketIOError);
var
  LJsonArrayStr: string;
begin
  if AContext.IsDisconnected then
    raise EIdSocketIoUnhandledMessage.Create('socket.io connection closed!');

  LJsonArrayStr := AData.ToJSON;

  if not Assigned(ACallback) then
    WriteSocketIOEvent(AContext, ''{no room}, AEventName, LJsonArrayStr, nil, nil)
  else
    WriteSocketIOEventRef(AContext, ''{no room}, AEventName, LJsonArrayStr,
      procedure(const Data: string)
      begin
        ACallback(AContext, TJSONObject.ParseJSONValue(Data), nil);
      end,
      AOnError);
end;

procedure TIdServerSocketIOHandling.EmitEventTo(const AContext: TIdServerContext; const AEventName: string; const AData: TJSONValue;
  const ACallback: TSocketIOMsgJSON; const AOnError: TSocketIOError);
var
  LContext: ISocketIOContext;
begin
  Lock;
  try
    LContext := FConnections.Items[AContext];
    EmitEventTo(LContext, AEventName, AData, ACallback, AOnError);
  finally
    Unlock;
  end;
end;

function TIdServerSocketIOHandling.EmitEventToAll(const AEventName: string; const AData: TJSONValue; const ACallback: TSocketIOMsgJSON;
  const AOnError: TSocketIOError): Integer;
begin
  Result := EmitEventToAll(AEventName, AData.ToJSON, ACallback, AOnError);
end;

function TIdServerSocketIOHandling.EmitEventToAll(const AEventName, AData: string; const ACallback: TSocketIOMsgJSON;
  const AOnError: TSocketIOError): Integer;
var
  LContext: ISocketIOContext;
  LJsonArrayStr: string;
begin
  Result := 0;
  LJsonArrayStr := '[' + AData + ']';

  Lock;
  try
    for LContext in FConnections.Values do
    begin
      if LContext.IsDisconnected then
        Continue;

      try
        if not Assigned(ACallback) then
          WriteSocketIOEvent(LContext, ''{no room}, AEventName, LJsonArrayStr, nil, nil)
        else
          WriteSocketIOEventRef(LContext, ''{no room}, AEventName, LJsonArrayStr,
            procedure(const Data: string)
            begin
              ACallback(LContext, TJSONObject.ParseJSONValue(Data), nil);
            end,
            AOnError);
      except
        //try to send to others
      end;
      Inc(Result);
    end;
    for LContext in FConnectionsGUID.Values do
    begin
      if LContext.IsDisconnected then
        Continue;

      try
        if not Assigned(ACallback) then
          WriteSocketIOEvent(LContext, ''{no room}, AEventName, LJsonArrayStr, nil, nil)
        else
          WriteSocketIOEventRef(LContext, ''{no room}, AEventName, LJsonArrayStr,
            procedure(const Data: string)
            begin
              ACallback(LContext, TJSONObject.ParseJSONValue(Data), nil);
            end, AOnError);
      except
        //try to send to others
      end;
      Inc(Result);
    end;
  finally
    Unlock;
  end;
end;

procedure TIdServerSocketIOHandling.SendTo(const AContext: TIdServerContext; const AMessage: string; const ACallback: TSocketIOMsgJSON;
  const AOnError: TSocketIOError);
var
  LContext: ISocketIOContext;
begin
  Lock;
  try
    LContext := FConnections.Items[AContext];
    if LContext.IsDisconnected then
      raise EIdSocketIoUnhandledMessage.Create('socket.io connection closed!');

    if not Assigned(ACallback) then
      WriteSocketIOMsg(LContext, ''{no room}, AMessage, nil)
    else
      WriteSocketIOMsg(LContext, ''{no room}, AMessage,
        procedure(const Data: string)
        begin
          ACallback(LContext, TJSONObject.ParseJSONValue(Data), nil);
        end, AOnError);
  finally
    Unlock;
  end;
end;

function TIdServerSocketIOHandling.SendToAll(const AMessage: string; const ACallback: TSocketIOMsgJSON; const AOnError: TSocketIOError): Integer;
var
  LContext: ISocketIOContext;
begin
  Result := 0;
  Lock;
  try
    for LContext in FConnections.Values do
    begin
      if LContext.IsDisconnected then
        Continue;

      if not Assigned(ACallback) then
        WriteSocketIOMsg(LContext, ''{no room}, AMessage, nil)
      else
        WriteSocketIOMsg(LContext, ''{no room}, AMessage,
          procedure(const Data: string)
          begin
            ACallback(LContext, TJSONObject.ParseJSONValue(Data), nil);
          end, AOnError);
      Inc(Result);
    end;
    for LContext in FConnectionsGUID.Values do
    begin
      if LContext.IsDisconnected then
        Continue;

      if not Assigned(ACallback) then
        WriteSocketIOMsg(LContext, ''{no room}, AMessage, nil)
      else
        WriteSocketIOMsg(LContext, ''{no room}, AMessage,
          procedure(const Data: string)
          begin
            ACallback(LContext, TJSONObject.ParseJSONValue(Data), nil);
          end);
      Inc(Result);
    end;
  finally
    Unlock;
  end;
end;

end.
