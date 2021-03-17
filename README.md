# DelphiWebsockets
WebSockets and Socket.io for Delphi

## How to create a server

```delphi
uses 
  IdSocketIOHandling,
  IdWebsocketServer,
  System.JSON;

...
  
  FServer := TIdWebsocketServer.Create(nil);
  FServer.DefaultPort := 8080;

  FServer.SocketIO.OnConnection(
    procedure(const ASocket: ISocketIOContext)
    var
      LJson: TJSONObject;
    begin
      // Send a message to the client in a given event
      ASocket.EmitEvent('connect_message', '{"message":"Welcome"}', nil, nil);
    end
  );
  // To listen events
  FServer.SocketIO.OnEvent(
    'event_name',
    procedure(const ASocket: ISocketIOContext; const AArgument: TJSONValue; const ACallback: ISocketIOCallback)
    begin
      // Do something
    end
  );
  
  FServer.Active := True;
```

## How to create a client

```delphi
uses 
  IdSocketIOHandling,
  IdHTTPWebsocketClient,
  System.JSON;

...

  FWebSocketClient := TIdHTTPWebSocketClient.Create(nil);
  FWebSocketClient.SocketIOCompatible := True;
  FSocketClient.Host := 'localhost';
  FSocketClient.Port := 8080;

  FSocketClient.SocketIO.OnEvent('event_name',
    procedure(const ASocket: ISocketIOContext; const AArgument: TJSONValue; const ACallback: ISocketIOCallback)
    begin
      TThread.Synchronize(nil,
        procedure
        begin
          memLog.Lines.Add(AArgument.ToJSON);
        end
        );
      if Assigned(ACallback) then
        ACallback.SendResponse('{"message":"success"}');
    end
    );

  FSocketClient.Connect;
  
```
