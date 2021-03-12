unit UClientMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, IdHTTPWebSocketClient;

type
  TForm2 = class(TForm)
    edtUrl: TEdit;
    btn1: TButton;
    edt1: TEdit;
    btn2: TButton;
    mem1: TMemo;
    procedure btn1Click(Sender: TObject);
  private
    { Private declarations }
    FClient: TIdHTTPWebsocketClient;
  public
    { Public declarations }
  end;

var
  Form2: TForm2;

implementation

uses
  IdSocketIOHandling, System.JSON;

{$R *.dfm}

procedure TForm2.btn1Click(Sender: TObject);
begin
  FClient := TIdHTTPWebsocketClient.Create(Self);
  FClient.Port := 1234;
  FClient.Host := 'localhost';
  FClient.SocketIOCompatible := True;
  FClient.SocketIO.OnEvent('test2',
    procedure(const ASocket: ISocketIOContext; const AArgument: TJSONValue; const ACallback: ISocketIOCallback)
    begin
      TThread.Synchronize(nil,
        procedure
        begin
          mem1.Lines.Add(AArgument.ToJSON)
        end
      ) ;
      //server wants a response?
      if aCallback <> nil then
        aCallback.SendResponse('thank for the push!');
    end);
  FClient.Connect;
  FClient.SocketIO.Emit('test', '{"request":"some data"}',
    //provide callback
    procedure(const ASocket: ISocketIOContext; const aJSON: TJSONValue; const aCallback: ISocketIOCallback)
    begin
      //show response (threadsafe)
      TThread.Synchronize(nil,
        procedure
        begin
          mem1.Lines.Add(aJSON.ToJSON)
        end
      ) ;

    end);
end;

end.
