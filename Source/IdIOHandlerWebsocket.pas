unit IdIOHandlerWebSocket;
{ .$DEFINE DEBUG_WS }
{$WARN SYMBOL_DEPRECATED OFF}
{$WARN SYMBOL_PLATFORM OFF}


// The WebSocket Protocol, RFC 6455
// http://datatracker.ietf.org/doc/rfc6455/?include_text=1
interface

{$I wsdefines.inc}


uses
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  IdIOHandlerStack,
  IdGlobal,
  IdException,
  IdBuffer,
  IdSSLOpenSSL,
  IdSocketHandle,
  IdIIOHandlerWebSocket,
  IdWebSocketTypes,
  System.SysUtils;

type

  TIdIOHandlerWebSocket = class;
  EIdWebSocketHandleError = class(EIdSocketHandleError);

  {$IF CompilerVersion >= 26}   // XE5
  TIdTextEncoding = IIdTextEncoding;
  {$ENDIF}

  TIdIOHandlerWebSocket = class(TIdIOHandlerStack, IIOHandlerWebSocket)
  protected
    FBusyUpgrading: Boolean;
    FCloseCode, FCloseTimeout: Integer;
    FCloseCodeSend: Boolean;
    FCloseReason, FPeerCloseReason, FRoleName: string;
    FClosing: Boolean;
    FExtensionBits: TWSExtensionBits;
    FIsServerSide: Boolean;
    FIsWebSocket: Boolean;
    FLastActivityTime: TDateTime;
    FLastPingTime: TDateTime;
    FLock: TCriticalSection;
    FMessageStream: TMemoryStream;
    FOnNotifyClosed, FOnNotifyClosing: TProc;
    FOnWebSocketClosing: TOnWebSocketClosing;
    FPayloadInfo: TIOWSPayloadInfo;
    FPendingWriteCount: Integer;
    FSelectLock: TCriticalSection;
    FWSInputBuffer: TIdBuffer;

    class var FUseSingleWriteThread: Boolean;
    function GetBinding: TIdSocketHandle;
    function GetBusyUpgrading: Boolean;
    function GetClosedGracefully: Boolean;
    function GetCloseReason: string;
    function GetConnected: Boolean;
    function GetInputBuffer: TIdBuffer;
    function GetIsWebSocket: Boolean;
    function GetLastActivityTime: TDateTime;
    function GetLastPingTime: TDateTime;
    function GetOnNotifyClosed: TProc;
    function GetOnNotifyClosing: TProc;
    procedure SetBusyUpgrading(const Value: Boolean);
    procedure SetClosedGracefully(const Value: Boolean);
    procedure SetCloseReason(const AReason: string);
    procedure SetIsWebSocket(const Value: Boolean);
    procedure SetLastActivityTime(const Value: TDateTime);
    procedure SetLastPingTime(const Value: TDateTime);
    procedure SetOnNotifyClosed(const Value: TProc);
    procedure SetOnNotifyClosing(const Value: TProc);
    procedure SetUseNagle(const Value: Boolean);

    function InternalReadDataFromSource(var VBuffer: TIdBytes; ARaiseExceptionOnTimeout: Boolean): Integer;
    function ReadDataFromSource(var VBuffer: TIdBytes): Integer; override;
    function WriteDataToTarget(const ABuffer: TIdBytes; const AOffset, ALength: Integer): Integer; override;

    function ReadFrame(out aFIN, aRSV1, aRSV2, aRSV3: boolean; out aDataCode: TWSDataCode; out aData: TIdBytes): Integer;
    function ReadMessage(var aBuffer: TIdBytes; out aDataCode: TWSDataCode): Integer;

    {$IF CompilerVersion >= 26}   // XE5
    function UTF8Encoding: IIdTextEncoding;
    {$ELSE}
    function UTF8Encoding: TEncoding;
    {$ENDIF}
    procedure InitComponent; override;
  public
    function WriteData(const aData: TIdBytes; aType: TWSDataCode;
      aFIN: boolean = true; aRSV1: boolean = false; aRSV2: boolean = false; aRSV3: boolean = false): integer;
    property BusyUpgrading: Boolean read FBusyUpgrading write FBusyUpgrading;
    property IsWebSocket: Boolean read FIsWebSocket write SetIsWebSocket;
    property IsServerSide: Boolean read FIsServerSide write FIsServerSide;
    property ClientExtensionBits: TWSExtensionBits read FExtensionBits write FExtensionBits;
    property RoleName: string read FRoleName write FRoleName;

    destructor Destroy; override;

    procedure Lock;
    procedure Unlock;
    function TryLock: Boolean;

    function HasData: Boolean;
    procedure Clear;
    function Readable(AMSec: Integer = IdTimeoutDefault): Boolean; override;
    function Connected: Boolean; override;

    procedure Close; override;
    procedure CloseWithReason(const AReason: string);
    property Closing: Boolean read FClosing;
    property CloseCode: Integer read FCloseCode write FCloseCode;
    property CloseReason: string read FCloseReason write FCloseReason;
    property CloseTimeout: Integer read FCloseTimeout write FCloseTimeout;
    procedure NotifyClosed;
    procedure NotifyClosing;
    property OnWebSocketClosing: TOnWebSocketClosing read FOnWebSocketClosing write FOnWebSocketClosing;

    // text/string writes
    procedure Write(const AOut: string; AEncoding: TIdTextEncoding = nil); overload; override;
    procedure WriteLn(const AOut: string; AEncoding: TIdTextEncoding = nil); overload; override;
    procedure WriteLnRFC(const AOut: string = ''; AEncoding: TIdTextEncoding = nil); override;
    procedure Write(AValue: TStrings; AWriteLinesCount: Boolean = False; AEncoding: TIdTextEncoding = nil); overload; override;
    procedure Write(AStream: TStream; aType: TWSDataType); overload;
    procedure WriteBin(const ABytes: TArray<Byte>);
    procedure WriteBufferFlush(AByteCount: Integer); override;

    procedure ReadBytes(var VBuffer: TIdBytes; AByteCount: Integer; AAppend: Boolean = True); override;

    property LastActivityTime: TDateTime read FLastActivityTime write FLastActivityTime;
    property LastPingTime: TDateTime read FLastPingTime write FLastPingTime;
    property OnNotifyClosed: TProc read GetOnNotifyClosed write SetOnNotifyClosed;
    property OnNotifyClosing: TProc read GetOnNotifyClosing write SetOnNotifyClosing;

    class property UseSingleWriteThread: Boolean read FUseSingleWriteThread write FUseSingleWriteThread;
  end;

  TIdIOHandlerWebSocketServer = class(TIdIOHandlerWebSocket)
  protected
    procedure InitComponent; override;
  end;

  TIdBuffer_Ext = class(TIdBuffer);

implementation

uses
  System.Math,
  {$IF DEFINED(MSWINDOWS)}
  Winapi.Windows,
  IdWinsock2,
  {$ELSEIF DEFINED(POSIX)}
  Posix.SysSocket,
  {$IFDEF DEFINED(ANDROID) or DEFINED(MACOS)}
  FMX.Platform,
  {$ENDIF}
  {$ENDIF}
  IdStream,
  IdStack,
  IdExceptionCore,
  IdResourceStrings,
  IdResourceStringsCore,
  IdStackConsts,
  WSDebugger,
  IdWebSocketConsts;

function BytesToStringRaw(const AValue: TIdBytes; aSize: Integer = - 1): string;
var
  i: Integer;
begin
  // SetLength(Result, Length(aValue));
  for i := 0 to High(AValue) do
  begin
    if (AValue[i] = 0) and (aSize < 0) then
      Exit;

    if (AValue[i] < 33) or ((AValue[i] > 126) and (AValue[i] < 161)) then
      Result := Result + '#' + IntToStr(AValue[i])
    else
      Result := Result + Char(AValue[i]);

    if (aSize > 0) and (i > aSize) then
      Break;
  end;
end;

{ TIdIOHandlerStack_WebSocket }

procedure TIdIOHandlerWebSocket.InitComponent;
begin
  inherited;
  FMessageStream := TMemoryStream.Create;
  FWSInputBuffer := TIdBuffer.Create;
  FLock := TCriticalSection.Create;
  FSelectLock := TCriticalSection.Create;
  {$IFDEF WEBSOCKETSSL}
  // SendBufferSize := 15 * 1024;
  {$ENDIF}
end;

procedure TIdIOHandlerWebSocket.Clear;
begin
  FWSInputBuffer.Clear;
  InputBuffer.Clear;
  FBusyUpgrading := False;
  FIsWebSocket := False;
  FClosing := False;
  FExtensionBits := [];
  FCloseReason := '';
  FCloseCode := 0;
  FLastActivityTime := 0;
  FLastPingTime := 0;
  FPayloadInfo.Clear;
  FCloseCodeSend := False;
  FPendingWriteCount := 0;
end;

procedure TIdIOHandlerWebSocket.Close;
var
  iaWriteBuffer: TIdBytes;
  sReason: UTF8String;
  iOptVal: Integer;
  LConnected: Boolean;
  LHandle: NativeUInt;
begin
  try
    // valid connection?
    LConnected := Opened and SourceIsAvailable and not ClosedGracefully;

    // no socket error? connection closed by software abort, connection reset by peer, etc
    try
      LHandle := 0;
      if Assigned(Binding) then
        LHandle := Binding.Handle;
      GStack.GetSocketOption(LHandle, Id_SOL_SOCKET, SO_ERROR, iOptVal);
      LConnected := LConnected and (iOptVal = 0);
    except
      LConnected := False;
    end;

    if LConnected and IsWebSocket then
    begin
      // close message must be responded with a close message back
      // or initiated with a close message
      if not FCloseCodeSend then
      begin
        FCloseCodeSend := True;

        // we initiate the close? then write reason etc
        if not Closing then
        begin
          SetLength(iaWriteBuffer, 2);
          if CloseCode < C_FrameClose_Normal then
            CloseCode := C_FrameClose_Normal;
          iaWriteBuffer[0] := Byte(CloseCode shr 8);
          iaWriteBuffer[1] := Byte(CloseCode);
          if CloseReason <> '' then
          begin
            sReason := utf8string(CloseReason);
            SetLength(iaWriteBuffer, Length(iaWriteBuffer) + Length(sReason));
            Move(sReason[1], iaWriteBuffer[2], Length(sReason));
          end;
        end
        else
        begin
          // just send normal close response back
          SetLength(iaWriteBuffer, 2);
          iaWriteBuffer[0] := Byte(C_FrameClose_Normal shr 8);
          iaWriteBuffer[1] := Byte(C_FrameClose_Normal);
        end;

        WriteData(iaWriteBuffer, wdcClose); // send close + code back
      end;

      // we did initiate the close? then wait (a little) for close response
      if not Closing then
      begin
        FClosing := True;
        CheckForDisconnect();
        // wait till client respond with close message back
        // but a pending message can be in the buffer, so process this too
        while ReadFromSource(False { no disconnect error } , 1 * 1000, False) > 0 do; // response within 1s?
      end;
    end;
  except
    // ignore, it's possible that the client is disconnected already (crashed etc)
  end;

  IsWebSocket := False;
  BusyUpgrading := False;
  inherited Close;
end;

procedure TIdIOHandlerWebSocket.CloseWithReason(const AReason: string);
begin
  FCloseReason := AReason;
  Close;
end;

function TIdIOHandlerWebSocket.Connected: Boolean;
begin
  Lock;
  try
    Result := inherited Connected;
  finally
    Unlock;
  end;
end;

destructor TIdIOHandlerWebSocket.Destroy;
begin
  TIdStack.DecUsage;

  while FPendingWriteCount > 0 do
    Sleep(1);

  FLock.Enter;
  FSelectLock.Enter;
  FLock.Free;
  FSelectLock.Free;

  FWSInputBuffer.Free;
  FMessageStream.Free;
  inherited;
end;

function TIdIOHandlerWebSocket.GetBinding: TIdSocketHandle;
begin
  Result := FBinding;
end;

function TIdIOHandlerWebSocket.GetBusyUpgrading: Boolean;
begin
  Result := FBusyUpgrading;
end;

function TIdIOHandlerWebSocket.GetClosedGracefully: Boolean;
begin
  Result := FClosedGracefully;
end;

function TIdIOHandlerWebSocket.GetCloseReason: string;
begin
  Result := FCloseReason;
end;

function TIdIOHandlerWebSocket.GetConnected: Boolean;
begin
  Result := Self.Connected;
end;

function TIdIOHandlerWebSocket.GetInputBuffer: TIdBuffer;
begin
  Result := FInputBuffer;
end;

function TIdIOHandlerWebSocket.GetIsWebSocket: Boolean;
begin
  Result := FIsWebSocket;
end;

function TIdIOHandlerWebSocket.GetLastActivityTime: TDateTime;
begin
  Result := FLastActivityTime;
end;

function TIdIOHandlerWebSocket.GetLastPingTime: TDateTime;
begin
  Result := FLastPingTime;
end;

function TIdIOHandlerWebSocket.GetOnNotifyClosed: TProc;
begin
  Result := FOnNotifyClosed;
end;

function TIdIOHandlerWebSocket.GetOnNotifyClosing: TProc;
begin
  Result := FOnNotifyClosing;
end;

procedure TIdIOHandlerWebSocket.SetOnNotifyClosed(const Value: TProc);
begin
  FOnNotifyClosed := Value;
end;

procedure TIdIOHandlerWebSocket.SetOnNotifyClosing(const Value: TProc);
begin
  FOnNotifyClosing := Value;
end;

function TIdIOHandlerWebSocket.HasData: Boolean;
begin
  // buffered data available? (more data from previous read)
  Result := (FWSInputBuffer.Size > 0) or not InputBufferIsEmpty;
end;

function TIdIOHandlerWebSocket.InternalReadDataFromSource(
  var VBuffer: TIdBytes; ARaiseExceptionOnTimeout: Boolean): Integer;
begin
  SetLength(VBuffer, 0);

  CheckForDisconnect;
  if not Readable(ReadTimeout) or
    not Opened or
    not SourceIsAvailable then
  begin
    CheckForDisconnect; // disconnected during wait in "Readable()"?
    if not Opened then
      raise EIdNotConnected.Create(RSNotConnected)
    else
      if not SourceIsAvailable then
      raise EIdClosedSocket.Create(RSStatusDisconnected);
    GStack.CheckForSocketError(GStack.WSGetLastError); // check for socket error
    if ARaiseExceptionOnTimeout then
      raise EIdReadTimeout.Create(RSIdNoDataToRead) // exit, no data can be received
    else
      Exit(0);
  end;

  SetLength(VBuffer, RecvBufferSize);
  Result := inherited ReadDataFromSource(VBuffer);
  if Result = 0 then
  begin
    CheckForDisconnect;                                // disconnected in the mean time?
    GStack.CheckForSocketError(GStack.WSGetLastError); // check for socket error
    if ARaiseExceptionOnTimeout then
      raise EIdNoDataToRead.Create(RSIdNoDataToRead); // nothing read? then connection is probably closed -> exit
  end;
  SetLength(VBuffer, Result);
end;

procedure TIdIOHandlerWebSocket.WriteLn(const AOut: string; AEncoding: TIdTextEncoding);
begin
  if UseSingleWriteThread and IsWebSocket and
    (TThread.Current.ThreadID <> TIdWebSocketWriteThread.Instance.ThreadID) then
  begin
    TInterlocked.Increment(FPendingWriteCount);
    TIdWebSocketWriteThread.Instance.QueueEvent(
      procedure
      begin
        TInterlocked.Decrement(FPendingWriteCount);
        WriteLn(AOut, AEncoding);
      end)
  end
  else
  begin
    Lock;
    try
      FPayloadInfo.Initialize(True, 0);
      inherited WriteLn(AOut, UTF8Encoding); // must be UTF8!
    finally
      FPayloadInfo.Clear;
      Unlock;
    end;
  end;
end;

procedure TIdIOHandlerWebSocket.WriteLnRFC(const AOut: string;
AEncoding: TIdTextEncoding);
begin
  if UseSingleWriteThread and IsWebSocket and
    (TThread.Current.ThreadID <> TIdWebSocketWriteThread.Instance.ThreadID) then
  begin
    TInterlocked.Increment(FPendingWriteCount);
    TIdWebSocketWriteThread.Instance.QueueEvent(
      procedure
      begin
        AtomicDecrement(FPendingWriteCount);
        WriteLnRFC(AOut, AEncoding);
      end)
  end
  else
  begin
    Lock;
    try
      FPayloadInfo.Initialize(True, 0);
      inherited WriteLnRFC(AOut, UTF8Encoding); // must be UTF8!
    finally
      FPayloadInfo.Clear;
      Unlock;
    end;
  end;
end;

procedure TIdIOHandlerWebSocket.Write(const AOut: string;
AEncoding: TIdTextEncoding);
begin
  if UseSingleWriteThread and IsWebSocket and
    (TThread.Current.ThreadID <> TIdWebSocketWriteThread.Instance.ThreadID) then
  begin
    TInterlocked.Increment(FPendingWriteCount);
    TIdWebSocketWriteThread.Instance.QueueEvent(
      procedure
      begin
        TInterlocked.Decrement(FPendingWriteCount);
        Write(AOut, AEncoding);
      end)
  end
  else
  begin
    Lock;
    try
      FPayloadInfo.Initialize(True, 0);
      inherited Write(AOut, UTF8Encoding); // must be UTF8!
    finally
      FPayloadInfo.Clear;
      Unlock;
    end;
  end;
end;

procedure TIdIOHandlerWebSocket.Write(AValue: TStrings;
AWriteLinesCount: Boolean; AEncoding: TIdTextEncoding);
begin
  if UseSingleWriteThread and IsWebSocket and
    (TThread.Current.ThreadID <> TIdWebSocketWriteThread.Instance.ThreadID) then
  begin
    TInterlocked.Increment(FPendingWriteCount);
    TIdWebSocketWriteThread.Instance.QueueEvent(
      procedure
      begin
        TInterlocked.Decrement(FPendingWriteCount);
        Write(AValue, AWriteLinesCount, AEncoding);
      end)
  end
  else
  begin
    Lock;
    try
      FPayloadInfo.Initialize(True, 0);
      inherited Write(AValue, AWriteLinesCount, UTF8Encoding); // must be UTF8!
    finally
      FPayloadInfo.Clear;
      Unlock;
    end;
  end;
end;

procedure TIdIOHandlerWebSocket.Write(AStream: TStream;
aType: TWSDataType);
begin
  if UseSingleWriteThread and IsWebSocket and
    (TThread.Current.ThreadID <> TIdWebSocketWriteThread.Instance.ThreadID) then
  begin
    TInterlocked.Increment(FPendingWriteCount);
    TIdWebSocketWriteThread.Instance.QueueEvent(
      procedure
      begin
        TInterlocked.Decrement(FPendingWriteCount);
        Write(AStream, aType);
      end)
  end
  else
  begin
    Lock;
    try
      FPayloadInfo.Initialize((aType = wdtText), AStream.Size);
      inherited Write(AStream);
    finally
      FPayloadInfo.Clear;
      Unlock;
    end;
  end;
end;

procedure TIdIOHandlerWebSocket.WriteBin(const ABytes: TArray<Byte>);
begin
  if UseSingleWriteThread and IsWebSocket and
    (TThread.Current.ThreadID <> TIdWebSocketWriteThread.Instance.ThreadID) then
  begin
    TInterlocked.Increment(FPendingWriteCount);
    TIdWebSocketWriteThread.Instance.QueueEvent(
      procedure
      begin
        TInterlocked.Decrement(FPendingWriteCount);
        WriteBin(ABytes);
      end)
  end
  else
  begin
    Lock;
    try
      FPayloadInfo.Initialize(False, 0);
      inherited Write(TIdBytes(ABytes));
    finally
      FPayloadInfo.Clear;
      Unlock;
    end;
  end;
end;

procedure TIdIOHandlerWebSocket.WriteBufferFlush(AByteCount: Integer);
begin
  if (FWriteBuffer = nil) or (FWriteBuffer.Size <= 0) then
    Exit;

  if UseSingleWriteThread and IsWebSocket and
    (TThread.Current.ThreadID <> TIdWebSocketWriteThread.Instance.ThreadID) then
  begin
    TInterlocked.Increment(FPendingWriteCount);
    TIdWebSocketWriteThread.Instance.QueueEvent(
      procedure
      begin
        TInterlocked.Decrement(FPendingWriteCount);
        WriteBufferFlush(AByteCount);
      end)
  end
  else
    inherited WriteBufferFlush(AByteCount);
end;

function TIdIOHandlerWebSocket.WriteDataToTarget(const ABuffer: TIdBytes;
const AOffset, ALength: Integer): Integer;
var data: TIdBytes; DataCode: TWSDataCode; fin: boolean;
begin
  if UseSingleWriteThread and IsWebSocket and
    (TThread.Current.ThreadID <> TIdWebSocketWriteThread.Instance.ThreadID) then
    Assert(False, 'Write done in different thread than TIdWebSocketWriteThread!');

  Lock;
  try
// Result := -1;  // commented out due to H2077 Value assigned never used...
    if not IsWebSocket then
    begin
      {$IFDEF DEBUG_WS}
      if DebugHook > 0 then
        OutputDebugString(PChar(Format('Send (non ws, TID:%d, P:%d): %s',
          [TThread.Current.ThreadID, Self.Binding.PeerPort, BytesToStringRaw(ABuffer)])));
      {$ENDIF}
      Result := inherited WriteDataToTarget(ABuffer, AOffset, ALength)
    end else
    begin
      data := ToBytes(ABuffer, ALength, AOffset);
      {$IFDEF DEBUG_WS}
      if DebugHook > 0 then
        OutputDebugString(PChar(Format('Send (ws, TID:%d, P:%d): %s',
          [TThread.Current.ThreadID, Self.Binding.PeerPort, BytesToStringRaw(data)])));

      {$ENDIF}
      try
        DataCode := FPayloadInfo.DataCode;
        fin := FPayloadInfo.DecLength(ALength);
        Result := WriteData(data, DataCode, fin, webBit1 in ClientExtensionBits,
          webBit2 in ClientExtensionBits, webBit3 in ClientExtensionBits);
      except
        FClosedGracefully := True;
        raise;
      end;
    end;
  finally
    Unlock;
  end;
end;

function TIdIOHandlerWebSocket.Readable(AMSec: Integer): Boolean;
begin
  if FWSInputBuffer.Size > 0 then
    Exit(True);

  if not FSelectLock.TryEnter then
    Exit(False);
  try
    Result := inherited Readable(AMSec);
  finally
    FSelectLock.Leave;
  end;
end;

procedure TIdIOHandlerWebSocket.ReadBytes(var VBuffer: TIdBytes;
AByteCount: Integer; AAppend: Boolean);
begin
  inherited;
  {$IFDEF DEBUG_WS}
  if IsWebSocket then
    if DebugHook > 0 then
    begin
      OutputDebugString(PChar(Format('%d Bytes read(TID:%d): %s',
        [AByteCount, TThread.Current.ThreadID, BytesToStringRaw(VBuffer, AByteCount)])));
      OutputDebugString(PChar(Format('Buffer (HeadIndex:%d): %s',
        [TIdBuffer_Ext(InputBuffer).FHeadIndex,
        BytesToStringRaw(TIdBuffer_Ext(InputBuffer).FBytes,
        InputBuffer.Size + TIdBuffer_Ext(InputBuffer).FHeadIndex)])));
    end;
  {$ENDIF}
end;

function TIdIOHandlerWebSocket.ReadDataFromSource(
  var VBuffer: TIdBytes): Integer;
var
  wscode: TWSDataCode;
begin
  // the first time something is read AFTER upgrading, we switch to WS
  // (so partial writes can be done, till a read is done)
  if BusyUpgrading then
  begin
    BusyUpgrading := False;
    IsWebSocket := True;
  end;

// Result := -1; // commented out due to H2077 Value assigned never used...
  Lock;
  try
    if not IsWebSocket then
    begin
      Result := inherited ReadDataFromSource(VBuffer);
      {$IFDEF DEBUG_WS}
      if DebugHook > 0 then
        OutputDebugString(PChar(Format('Received (non ws, TID:%d, P:%d): %s',
          [TThread.Current.ThreadID, Self.Binding.PeerPort, BytesToStringRaw(VBuffer, Result)])));
      {$ENDIF}
    end
    else
    begin
      try
        // we wait till we have a full message here (can be fragmented in several frames)
        Result := ReadMessage(VBuffer, wscode);

        {$IFDEF DEBUG_WS}
        if DebugHook > 0 then
          OutputDebugString(PChar(Format('Received (ws, TID:%d, P:%d): %s',
            [TThread.Current.ThreadID, Self.Binding.PeerPort, BytesToStringRaw(VBuffer)])));
        {$ENDIF}
// first write the data code (text or binary, ping, pong)
        FInputBuffer.Write(Uint32(Ord(wscode)));
        // we write message size here, vbuffer is written after this. This way we can use ReadStream to get 1 single message (in case multiple messages in FInputBuffer)
        if LargeStream then
          FInputBuffer.Write(Int64(Result))
        else
          FInputBuffer.Write(Uint32(Result))
      except
        FClosedGracefully := True; // closed (but not gracefully?)
        raise;
      end;
    end;
  finally
    Unlock; // normal unlock (no double try finally)
  end;
end;

function TIdIOHandlerWebSocket.ReadMessage(var aBuffer: TIdBytes; out aDataCode: TWSDataCode): Integer;
var
  iReadCount: Integer;
  iaReadBuffer: TIdBytes;
  bFIN, bRSV1, bRSV2, bRSV3: boolean;
  lDataCode: TWSDataCode;
  lFirstDataCode: TWSDataCode;
// closeCode: integer;
// closeResult: string;
begin
  Result := 0;
  (* ...all fragments of a message are of
     the same type, as set by the first fragment's opcode.  Since
     control frames cannot be fragmented, the type for all fragments in
     a message MUST be either text, binary, or one of the reserved
     opcodes. *)
  lFirstDataCode := wdcNone;
  FMessageStream.Clear;

  repeat
    // read a single frame
    iReadCount := ReadFrame(bFIN, bRSV1, bRSV2, bRSV3, lDataCode, iaReadBuffer);
    if (iReadCount > 0) or
      (lDataCode <> wdcNone) then
    begin
      Assert(Length(iaReadBuffer) = iReadCount);

      // store client extension bits
      if Self.IsServerSide then
      begin
        ClientExtensionBits := [];
        if bRSV1 then
          ClientExtensionBits := ClientExtensionBits + [webBit1];
        if bRSV2 then
          ClientExtensionBits := ClientExtensionBits + [webBit2];
        if bRSV3 then
          ClientExtensionBits := ClientExtensionBits + [webBit3];
      end;

      // process frame
      case lDataCode of
        wdcText, wdcBinary:
          begin
            if lFirstDataCode <> wdcNone then
              raise EIdWebSocketHandleError.Create('Invalid frame: specified data code only allowed for the first frame. Data = ' +
                BytesToStringRaw(iaReadBuffer));
            lFirstDataCode := lDataCode;

            FMessageStream.Clear;
            TIdStreamHelper.Write(FMessageStream, iaReadBuffer);
          end;
        wdcContinuation:
          begin
            if not (lFirstDataCode in [wdcText, wdcBinary]) then
              raise EIdWebSocketHandleError.Create('Invalid frame continuation. Data = ' + BytesToStringRaw(iaReadBuffer));
            TIdStreamHelper.Write(FMessageStream, iaReadBuffer);
          end;
        wdcClose:
          begin
            FCloseCode := C_FrameClose_Normal;
            // "If there is a body, the first two bytes of the body MUST be a 2-byte
            // unsigned integer (in network byte order) representing a status code"
            if Length(iaReadBuffer) > 1 then
            begin
              FCloseCode := (iaReadBuffer[0] shl 8) +
                iaReadBuffer[1];
              if Length(iaReadBuffer) > 2 then
                FCloseReason := BytesToString(iaReadBuffer, 2, Length(iaReadBuffer), UTF8Encoding);
            end;

            FClosing := True;
            Self.Close;
          end;
        // Note: control frames can be send between fragmented frames
        wdcPing:
          begin
            WriteData(iaReadBuffer, wdcPong); // send pong + same data back
            lFirstDataCode := lDataCode;
          // bFIN := False; //ignore ping when we wait for data?
          end;
        wdcPong:
          begin
           // pong received, ignore;
            lFirstDataCode := lDataCode;
          end;
      end;
    end
    else
      Break;
  until bFIN;

  // done?
  if bFIN then
  begin
    if (lFirstDataCode in [wdcText, wdcBinary]) then
    begin
      // result
      FMessageStream.Position := 0;
      TIdStreamHelper.ReadBytes(FMessageStream, aBuffer);
      Result := FMessageStream.Size;
      aDataCode := lFirstDataCode
    end
    else if (lFirstDataCode in [wdcPing, wdcPong]) then
    begin
      // result
      FMessageStream.Position := 0;
      TIdStreamHelper.ReadBytes(FMessageStream, aBuffer);
      SetLength(aBuffer, FMessageStream.Size);
      // dummy data: there *must* be some data read otherwise connection is closed by Indy!
      if Length(aBuffer) <= 0 then
      begin
        SetLength(aBuffer, 1);
        aBuffer[0] := Ord(lFirstDataCode);
      end;

      Result := Length(aBuffer);
      aDataCode := lFirstDataCode
    end;
  end;
end;

procedure TIdIOHandlerWebSocket.SetBusyUpgrading(const Value: Boolean);
begin
  FBusyUpgrading := Value;
end;

procedure TIdIOHandlerWebSocket.SetCloseReason(const AReason: string);
begin
  FCloseReason := AReason;
end;

procedure TIdIOHandlerWebSocket.SetClosedGracefully(const Value: Boolean);
begin
  FClosedGracefully := Value;
end;

procedure TIdIOHandlerWebSocket.SetIsWebSocket(const Value: Boolean);
var data: TIdBytes;
begin
  // copy websocket data which was send/received during http upgrade
  if not FIsWebSocket and Value and
    (FInputBuffer.Size > 0) then
  begin
    FInputBuffer.ExtractToBytes(data);
    FWSInputBuffer.Write(data);
  end;

  FIsWebSocket := Value;
end;

procedure TIdIOHandlerWebSocket.SetLastActivityTime(const Value: TDateTime);
begin
  FLastActivityTime := Value;
end;

procedure TIdIOHandlerWebSocket.SetLastPingTime(const Value: TDateTime);
begin
  FLastPingTime := Value;
end;

procedure TIdIOHandlerWebSocket.SetUseNagle(const Value: Boolean);
begin
  FUseNagle := Value;
end;

procedure TIdIOHandlerWebSocket.Lock;
begin
  FLock.Enter;
end;

procedure TIdIOHandlerWebSocket.NotifyClosed;
begin
  if Assigned(FOnNotifyClosed) then
    FOnNotifyClosed;
end;

procedure TIdIOHandlerWebSocket.NotifyClosing;
begin
  {$IF DEFINED(DEBUG_WS)}
  WSDebugger.OutputDebugString(RoleName, 'TIdIOHandlerWebSocketSSL.NotifyClosing');
  {$ENDIF}
  if Assigned(FOnNotifyClosing) then
    FOnNotifyClosing;
  if Assigned(OnWebSocketClosing) then
    OnWebSocketClosing(FCloseReason);
end;

function TIdIOHandlerWebSocket.TryLock: Boolean;
begin
  Result := FLock.TryEnter;
end;

procedure TIdIOHandlerWebSocket.Unlock;
begin
  FLock.Leave;
end;

{$IF CompilerVersion >= 26}

// XE5
function TIdIOHandlerWebSocket.UTF8Encoding: IIdTextEncoding;
begin
  Result := IndyTextEncoding_UTF8;
end;
{$ELSE}


function TIdIOHandlerWebSocket.UTF8Encoding: TEncoding;
begin
  Result := TIdTextEncoding.UTF8;
end;
{$ENDIF}


function TIdIOHandlerWebSocket.ReadFrame(out aFIN, aRSV1, aRSV2, aRSV3: boolean;
out aDataCode: TWSDataCode; out aData: TIdBytes): Integer;
var
  iInputPos: NativeInt;

  function _WaitByte(ARaiseExceptionOnTimeout: Boolean): Boolean;
  var
    temp: TIdBytes;
  begin
    // if HasData then Exit(True);
    if (FWSInputBuffer.Size > iInputPos) then
      Exit(True);

    Result := InternalReadDataFromSource(temp, ARaiseExceptionOnTimeout) > 0;
    if Result then
    begin
      FWSInputBuffer.Write(temp);
      {$IFDEF DEBUG_WS}
// if DebugHook > 0 then
// OutputDebugString(PChar(Format('Received (TID:%d, P:%d): %s',
// [TThread.Current.ThreadID, Self.Binding.PeerPort, BytesToStringRaw(temp)])));
// OutputDebugString(PChar('Received: ' + BytesToStringRaw(temp)));
      {$ENDIF}
    end;
  end;

  function _GetByte: Byte;
  begin
    while FWSInputBuffer.Size <= iInputPos do
    begin
      // FWSInputBuffer.AsString;
      _WaitByte(True);
      if FWSInputBuffer.Size <= iInputPos then
        Sleep(1);
    end;

    // Self.ReadByte copies all data everytime (because the first byte must be removed) so we use index (much more efficient)
    Result := FWSInputBuffer.PeekByte(iInputPos);
    // FWSInputBuffer.AsString
    inc(iInputPos);
  end;

  function _GetBytes(aCount: Integer): TIdBytes;
  var
    temp: TIdBytes;
  begin
    while FWSInputBuffer.Size < aCount do
    begin
      InternalReadDataFromSource(temp, True);
      FWSInputBuffer.Write(temp);
      {$IFDEF DEBUG_WS}
      if DebugHook > 0 then
        OutputDebugString(PChar('Received: ' + BytesToStringRaw(temp)));
      {$ENDIF}
      if FWSInputBuffer.Size < aCount then
        Sleep(1);
    end;

    FWSInputBuffer.ExtractToBytes(Result, aCount);
  end;

var
  iByte: Byte;
  i, iCode: NativeInt;
  bHasMask: boolean;
  iDataLength, iPos: Int64;
  rMask: record
    case Boolean of
    True: (MaskAsBytes: array [0 .. 3] of Byte);
  False: (MaskAsInt: Int32);
end;
begin
  iInputPos := 0;
  Result := 0;
  aFIN := False;
  aRSV1 := False;
  aRSV2 := False;
  aRSV3 := False;
  aDataCode := wdcNone;
  SetLength(aData, 0);

  if not _WaitByte(False) then
    Exit;
  FLastActivityTime := Now; // received some data

  // wait + process data
  iByte := _GetByte;
  (* 0                   1                   2                   3
     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 (nr)
     7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0 (bit)
    +-+-+-+-+-------+-+-------------+-------------------------------+
    |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
    |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
    |N|V|V|V|       |S|             |   (if payload len==126/127)   |
    | |1|2|3|       |K|             |                               |
    +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - + *)
  // FIN, RSV1, RSV2, RSV3: 1 bit each
  aFIN := (iByte and (1 shl 7)) > 0;
  aRSV1 := (iByte and (1 shl 6)) > 0;
  aRSV2 := (iByte and (1 shl 5)) > 0;
  aRSV3 := (iByte and (1 shl 4)) > 0;
  // Opcode: 4 bits
  iCode := (iByte and $0F); // clear 4 MSB's
  case iCode of
    C_FrameCode_Continuation:
      aDataCode := wdcContinuation;
    C_FrameCode_Text:
      aDataCode := wdcText;
    C_FrameCode_Binary:
      aDataCode := wdcBinary;
    C_FrameCode_Close:
      aDataCode := wdcClose;
    C_FrameCode_Ping:
      aDataCode := wdcPing;
    C_FrameCode_Pong:
      aDataCode := wdcPong;
  else
    raise EIdException.CreateFmt('Unsupported data code: %d. Buffer = %s', [iCode, FWSInputBuffer.AsString]);
  end;

  // Mask: 1 bit
  iByte := _GetByte;
  bHasMask := (iByte and (1 shl 7)) > 0;
  // Length (7 bits or 7+16 bits or 7+64 bits)
  iDataLength := (iByte and $7F); // clear 1 MSB
  // Extended payload length?
  // If 126, the following 2 bytes interpreted as a 16-bit unsigned integer are the payload length
  if (iDataLength = 126) then
  begin
    iByte := _GetByte;
    iDataLength := (iByte shl 8); // 8 MSB
    iByte := _GetByte;
    iDataLength := iDataLength + iByte;
  end
  // If 127, the following 8 bytes interpreted as a 64-bit unsigned integer (the most significant bit MUST be 0) are the payload length
  else if (iDataLength = 127) then
  begin
    iDataLength := 0;
    for i := 7 downto 0 do // read 8 bytes in reverse order
    begin
      iByte := _GetByte;
      iDataLength := iDataLength +
        (Int64(iByte) shl (8 * i)); // shift bits to left to recreate 64bit integer
    end;
    Assert(iDataLength > 0);
  end;

  // "All frames sent from client to server must have this bit set to 1"
  if IsServerSide and not bHasMask then
    raise EIdWebSocketHandleError.Create('No mask supplied: mask is required for clients when sending data to server. Buffer = ' +
      FWSInputBuffer.AsString)
  else if not IsServerSide and bHasMask then
    raise EIdWebSocketHandleError.Create('Mask supplied but mask is not allowed for servers when sending data to clients. Buffer = ' +
      FWSInputBuffer.AsString);

  // Masking-key: 0 or 4 bytes
  if bHasMask then
  begin
    rMask.MaskAsBytes[0] := _GetByte;
    rMask.MaskAsBytes[1] := _GetByte;
    rMask.MaskAsBytes[2] := _GetByte;
    rMask.MaskAsBytes[3] := _GetByte;
  end;
  // Payload data:  (x+y) bytes
  FWSInputBuffer.Remove(iInputPos); // remove first couple of processed bytes (header)
  // simple read?
  if not bHasMask then
    aData := _GetBytes(iDataLength)
  else
  // reverse mask
  begin
    aData := _GetBytes(iDataLength);
    iPos := 0;
    while iPos < iDataLength do
    begin
      aData[iPos] := aData[iPos] xor
        rMask.MaskAsBytes[iPos mod 4]; // apply mask
      inc(iPos);
    end;
  end;

  Result := Length(aData);
  {$IFDEF DEBUG_WS}
  if DebugHook > 0 then
    OutputDebugString(PChar(Format('Received (TID:%d, P:%d, Count=%d): %s',
      [TThread.Current.ThreadID, Self.Binding.PeerPort, Result, BytesToStringRaw(aData, Result)])));
  {$ENDIF}
end;

function TIdIOHandlerWebSocket.WriteData(const aData: TIdBytes;
aType: TWSDataCode; aFIN, aRSV1, aRSV2, aRSV3: Boolean): integer;
var
  iByte: Byte;
  i, ioffset: NativeInt;
  iDataLength, iPos: Int64;
  rLength: Int64Rec;
  rMask: record
    case Boolean of
    True: (MaskAsBytes: array [0 .. 3] of Byte);
  False: (MaskAsInt: Int32);
end;
strmData:
TMemoryStream;
bData:
TIdBytes;
begin
// Result := 0;// commented out due to H2077 Value assigned never used...
  Assert(Binding <> nil);

  strmData := TMemoryStream.Create;
  Lock;
  try
    FLastActivityTime := Now; // sending some data
    (* 0                   1                   2                   3
       0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 (nr)
       7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0 (bit)
      +-+-+-+-+-------+-+-------------+-------------------------------+
      |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
      |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
      |N|V|V|V|       |S|             |   (if payload len==126/127)   |
      | |1|2|3|       |K|             |                               |
      +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - + *)
    // FIN, RSV1, RSV2, RSV3: 1 bit each
    if aFIN then
      iByte := (1 shl 7)
    else
      iByte := 0;
    if aRSV1 then
      iByte := iByte + (1 shl 6);
    if aRSV2 then
      iByte := iByte + (1 shl 5);
    if aRSV3 then
      iByte := iByte + (1 shl 4);
    // Opcode: 4 bits
    case aType of
      wdcContinuation:
        iByte := iByte + C_FrameCode_Continuation;
      wdcText:
        iByte := iByte + C_FrameCode_Text;
      wdcBinary:
        iByte := iByte + C_FrameCode_Binary;
      wdcClose:
        iByte := iByte + C_FrameCode_Close;
      wdcPing:
        iByte := iByte + C_FrameCode_Ping;
      wdcPong:
        iByte := iByte + C_FrameCode_Pong;
    else
      raise EIdException.CreateFmt('Unsupported data code: %d', [Ord(aType)]);
    end;
    strmData.Write(iByte, SizeOf(iByte));

    iByte := 0;
    // Mask: 1 bit; Note: Clients must apply a mask
    if not IsServerSide then
      iByte := (1 shl 7);

    // Length: 7 bits or 7+16 bits or 7+64 bits
    if Length(aData) < 126 then // 7 bit, 128
      iByte := iByte + Length(aData)
    else if Length(aData) < 1 shl 16 then // 16 bit, 65536
      iByte := iByte + 126
    else
      iByte := iByte + 127;
    strmData.Write(iByte, SizeOf(iByte));

    // Extended payload length?
    if Length(aData) >= 126 then
    begin
      // If 126, the following 2 bytes interpreted as a 16-bit unsigned integer are the payload length
      if Length(aData) < 1 shl 16 then // 16 bit, 65536
      begin
        rLength.Lo := Length(aData);
        iByte := rLength.Bytes[1];
        strmData.Write(iByte, SizeOf(iByte));
        iByte := rLength.Bytes[0];
        strmData.Write(iByte, SizeOf(iByte));
      end
      else
      // If 127, the following 8 bytes interpreted as a 64-bit unsigned integer (the most significant bit MUST be 0) are the payload length
      begin
        rLength := Int64Rec(Int64(Length(aData)));
        for i := 7 downto 0 do
        begin
          iByte := rLength.Bytes[i];
          strmData.Write(iByte, SizeOf(iByte));
        end;
      end
    end;

    // Masking-key: 0 or 4 bytes; Note: Clients must apply a mask
    if not IsServerSide then
    begin
      rMask.MaskAsInt := Random(MaxInt);
      strmData.Write(rMask.MaskAsBytes[0], SizeOf(Byte));
      strmData.Write(rMask.MaskAsBytes[1], SizeOf(Byte));
      strmData.Write(rMask.MaskAsBytes[2], SizeOf(Byte));
      strmData.Write(rMask.MaskAsBytes[3], SizeOf(Byte));
    end;

    // write header
    strmData.Position := 0;
    TIdStreamHelper.ReadBytes(strmData, bData);

    // Mask? Note: Only clients must apply a mask
    if not IsServerSide then
    begin
      iPos := 0;
      iDataLength := Length(aData);
      // in place masking
      while iPos < iDataLength do
      begin
        iByte := aData[iPos] xor rMask.MaskAsBytes[iPos mod 4]; // apply mask
        aData[iPos] := iByte;
        inc(iPos);
      end;
    end;

    AppendBytes(bData, aData); // important: send all at once!
    ioffset := 0;
    repeat
      // Result := Binding.Send(bData, ioffset);
      //
      Result := inherited WriteDataToTarget(bdata, iOffset, (Length(bData) - ioffset)); // ssl compatible?
      if Result < 0 then
      begin
         // IO error ; probably connexion closed by peer on protocol error ?
        {$IFDEF DEBUG_WS}
        if DebugHook > 0 then
          OutputDebugString(PChar(Format('WriteError ThrID:%d, L:%d, R:%d', [TThread.CurrentThread.ThreadID, Length(bData) - ioffset, Result])));

        {$ENDIF}
        break;
      end;
      Inc(ioffset, Result);
    until ioffset >= Length(bData);

// if DebugHook > 0 then
// OutputDebugString(PChar(Format('Written (TID:%d, P:%d): %s',
// [TThread.Current.ThreadID, Self.Binding.PeerPort, BytesToStringRaw(bData)])));
  finally
    Unlock;
    strmData.Free;
  end;
end;

{ TIdIOHandlerWebSocketServer }

procedure TIdIOHandlerWebSocketServer.InitComponent;
begin
  inherited;
  IsServerSide := True;
  UseNagle := False;
end;

end.
