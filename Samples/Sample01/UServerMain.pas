unit UServerMain;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Variants,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,
  IdWebsocketServer,
  IdHTTPWebsocketClient,
  IdSocketIOHandling;

type
  TForm1 = class(TForm)
    edtPort: TEdit;
    btn1: TButton;
    mem1: TMemo;
    procedure btn1Click(Sender: TObject);
  private
    { Private declarations }
    FServer: TIdWebsocketServer;
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

uses
  System.JSON;

{$R *.dfm}


procedure TForm1.btn1Click(Sender: TObject);
begin
  if not Assigned(FServer) then
  begin
    FServer := TIdWebsocketServer.Create(Self);
    FServer.DefaultPort := StrToInt(edtPort.Text);
    FServer.SocketIO.OnEvent('test',
      procedure(const ASocket: ISocketIOContext; const AArgument: TJSONValue; const ACallback: ISocketIOCallback)
      begin
        TThread.Synchronize(nil,
          procedure
          begin
            mem1.Lines.Add(AArgument.ToJSON)
          end
        );
      // send callback (only if specified!)
        if aCallback <> nil then
          aCallback.SendResponse('{"succes":true}');
      end);
    FServer.Active := True;
  end;
end;

end.
