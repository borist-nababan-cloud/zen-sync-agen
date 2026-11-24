object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'Sync Application Zen Family Spa'
  ClientHeight = 541
  ClientWidth = 705
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnShow = FormShow
  DesignSize = (
    705
    541)
  PixelsPerInch = 96
  TextHeight = 13
  object lblCounter: TLabel
    Left = 566
    Top = 67
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
  end
  object Label1: TLabel
    Left = 513
    Top = 100
    Width = 51
    Height = 13
    Alignment = taRightJustify
    Anchors = [akTop, akRight]
    Caption = 'Line Count'
    ExplicitLeft = 454
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
    Top = 128
    Width = 689
    Height = 405
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
    Top = 97
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
    Left = 576
    Top = 97
    Anchors = [akTop, akRight]
    EditValue = 0.000000000000000000
    TabOrder = 4
    Width = 121
  end
  object btnManualSync: TcxButton
    Left = 8
    Top = 66
    Width = 101
    Height = 25
    Caption = 'Manual Sync'
    TabOrder = 5
    OnClick = btnManualSyncClick
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
  object TrayIcon1: TTrayIcon
    PopupMenu = pmTray
    OnDblClick = TrayIcon1DblClick
    Left = 424
    Top = 52
  end
  object pmTray: TPopupMenu
    Left = 464
    Top = 52
    object miShow: TMenuItem
      Caption = 'Show Sync Agent'
      Default = True
      OnClick = miShowClick
    end
    object miManualSync: TMenuItem
      Caption = 'Manual Sync...'
      OnClick = btnManualSyncClick
    end
    object miSep: TMenuItem
      Caption = '-'
    end
    object miExit: TMenuItem
      Caption = 'Exit Application...'
      OnClick = miExitClick
    end
  end
  object tmrRate: TTimer
    Enabled = False
    Interval = 5000
    OnTimer = tmrRateTimer
    Left = 348
    Top = 32
  end
end
