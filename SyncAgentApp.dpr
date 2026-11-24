program SyncAgentApp;

uses
  Vcl.Forms,
  FMain in 'FMain.pas' {frmMain},
  FConfigSetup in 'uses\FConfigSetup.pas' {frmConfigSetup},
  FdmDB in 'uses\FdmDB.pas' {dmDB: TDataModule},
  MainSource in 'uses\MainSource.pas',
  uHTTP in 'uses\uHTTP.pas',
  XSuperJSON in 'uses\XSuperJSON.pas',
  XSuperObject in 'uses\XSuperObject.pas',
  FManualSync in 'FManualSync.pas' {frmManualSync};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TdmDB, dmDB);
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
