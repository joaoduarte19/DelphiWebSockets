program WebSocketClient;

uses
  Vcl.Forms,
  UClientMain in 'UClientMain.pas' {Form2},
  IdHTTPWebsocketClient in '..\..\Source\IdHTTPWebsocketClient.pas',
  IdIIOHandlerWebsocket in '..\..\Source\IdIIOHandlerWebsocket.pas',
  IdIOHandlerWebsocket in '..\..\Source\IdIOHandlerWebsocket.pas',
  IdIOHandlerWebSocketSSL in '..\..\Source\IdIOHandlerWebSocketSSL.pas',
  IdServerBaseHandling in '..\..\Source\IdServerBaseHandling.pas',
  IdServerIOHandlerWebsocket in '..\..\Source\IdServerIOHandlerWebsocket.pas',
  IdServerIOHandlerWebsocketSSL in '..\..\Source\IdServerIOHandlerWebsocketSSL.pas',
  IdServerSocketIOHandling in '..\..\Source\IdServerSocketIOHandling.pas',
  IdServerWebsocketContext in '..\..\Source\IdServerWebsocketContext.pas',
  IdServerWebsocketHandling in '..\..\Source\IdServerWebsocketHandling.pas',
  IdSocketIOHandling in '..\..\Source\IdSocketIOHandling.pas',
  IdWebSocketConsts in '..\..\Source\IdWebSocketConsts.pas',
  IdWebsocketServer in '..\..\Source\IdWebsocketServer.pas',
  IdWebsocketServerSSL in '..\..\Source\IdWebsocketServerSSL.pas',
  IdWebSocketTypes in '..\..\Source\IdWebSocketTypes.pas',
  WSDebugger in '..\..\Source\WSDebugger.pas',
  WSMultiReadThread in '..\..\Source\WSMultiReadThread.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm2, Form2);
  Application.Run;
end.
