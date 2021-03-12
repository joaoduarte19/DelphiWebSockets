object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'Form1'
  ClientHeight = 299
  ClientWidth = 635
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  PixelsPerInch = 96
  TextHeight = 13
  object edtPort: TEdit
    Left = 8
    Top = 8
    Width = 121
    Height = 21
    TabOrder = 0
    Text = '1234'
  end
  object btn1: TButton
    Left = 135
    Top = 8
    Width = 75
    Height = 25
    Caption = 'btn1'
    TabOrder = 1
    OnClick = btn1Click
  end
  object mem1: TMemo
    Left = 8
    Top = 39
    Width = 449
    Height = 242
    Lines.Strings = (
      'mem1')
    TabOrder = 2
  end
end
