object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'Sync Application Zen Family Spa'
  ClientHeight = 541
  ClientWidth = 646
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  OnShow = FormShow
  DesignSize = (
    646
    541)
  PixelsPerInch = 96
  TextHeight = 13
  object lblCounter: TLabel
    Left = 503
    Top = 51
    Width = 125
    Height = 19
    Alignment = taRightJustify
    Anchors = [akTop, akRight]
    Caption = 'TIMER STOPED'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clRed
    Font.Height = -16
    Font.Name = 'Tahoma'
    Font.Style = [fsBold]
    ParentFont = False
    ExplicitLeft = 492
  end
  object Label1: TLabel
    Left = 444
    Top = 79
    Width = 51
    Height = 13
    Alignment = taRightJustify
    Anchors = [akTop, akRight]
    Caption = 'Line Count'
  end
  object btnSetupConfig: TcxButton
    Left = 8
    Top = 8
    Width = 101
    Height = 25
    Caption = 'Setup Config'
    TabOrder = 0
    OnClick = btnSetupConfigClick
  end
  object memLogs: TMemo
    Left = 8
    Top = 108
    Width = 630
    Height = 425
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
    TabOrder = 1
    OnChange = memLogsChange
  end
  object btnSaveLogs: TcxButton
    Left = 8
    Top = 77
    Width = 101
    Height = 25
    Caption = 'Save Logs'
    TabOrder = 2
    OnClick = btnSaveLogsClick
  end
  object btnStartStop: TcxButton
    Left = 8
    Top = 39
    Width = 101
    Height = 25
    Caption = 'Start / Stop Timer'
    TabOrder = 3
    OnClick = btnStartStopClick
  end
  object edLLineCount: TcxCalcEdit
    Left = 507
    Top = 76
    Anchors = [akTop, akRight]
    EditValue = 0.000000000000000000
    TabOrder = 4
    Width = 121
  end
  object tmrConnectDB: TTimer
    Interval = 5000
    OnTimer = tmrConnectDBTimer
    Left = 148
    Top = 28
  end
  object tmSync: TTimer
    Enabled = False
    OnTimer = tmSyncTimer
    Left = 272
    Top = 16
  end
  object SaveDialog1: TSaveDialog
    Left = 212
    Top = 20
  end
end
