object frmManualSync: TfrmManualSync
  Left = 0
  Top = 0
  Caption = 'Manual Sync'
  ClientHeight = 570
  ClientWidth = 794
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnClose = FormClose
  DesignSize = (
    794
    570)
  PixelsPerInch = 96
  TextHeight = 13
  object manLogs: TMemo
    Left = 8
    Top = 92
    Width = 773
    Height = 465
    Anchors = [akLeft, akTop, akRight, akBottom]
    Color = clBlack
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clLime
    Font.Height = -13
    Font.Name = 'Terminal'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssBoth
    TabOrder = 0
  end
  object listBox: TcxCheckListBox
    Left = 8
    Top = 8
    Width = 297
    Height = 69
    Items = <
      item
        Text = 'HRD Karyawan Info'
      end
      item
        Text = 'Master Room'
      end
      item
        Text = 'GC Items'
      end
      item
        Text = 'Payroll'
      end>
    TabOrder = 1
  end
  object btnStartManual: TcxButton
    Left = 328
    Top = 8
    Width = 105
    Height = 49
    Caption = 'Start Sync'
    TabOrder = 2
    OnClick = btnStartManualClick
  end
end
