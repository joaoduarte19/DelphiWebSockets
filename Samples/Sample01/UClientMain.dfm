object Form2: TForm2
  Left = 0
  Top = 0
  Caption = 'Form2'
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
  object edtUrl: TEdit
    Left = 8
    Top = 8
    Width = 521
    Height = 21
    TabOrder = 0
    Text = 'edtUrl'
  end
  object btn1: TButton
    Left = 535
    Top = 8
    Width = 75
    Height = 25
    Caption = 'btn1'
    TabOrder = 1
    OnClick = btn1Click
  end
  object edt1: TEdit
    Left = 8
    Top = 35
    Width = 521
    Height = 21
    TabOrder = 2
    Text = 'edt1'
  end
  object btn2: TButton
    Left = 535
    Top = 33
    Width = 75
    Height = 25
    Caption = 'btn2'
    TabOrder = 3
  end
  object mem1: TMemo
    Left = 8
    Top = 62
    Width = 521
    Height = 187
    Lines.Strings = (
      'mem1')
    TabOrder = 4
  end
end
