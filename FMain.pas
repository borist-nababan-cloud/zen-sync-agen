unit FMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, cxGraphics, cxLookAndFeels,
  cxLookAndFeelPainters, Vcl.Menus, dxSkinsCore, dxSkinBlack, dxSkinBlue,
  dxSkinBlueprint, dxSkinCaramel, dxSkinCoffee, dxSkinDarkRoom, dxSkinDarkSide,
  dxSkinDevExpressDarkStyle, dxSkinDevExpressStyle, dxSkinFoggy,
  dxSkinGlassOceans, dxSkinHighContrast, dxSkiniMaginary, dxSkinLilian,
  dxSkinLiquidSky, dxSkinLondonLiquidSky, dxSkinMcSkin, dxSkinMetropolis,
  dxSkinMetropolisDark, dxSkinMoneyTwins, dxSkinOffice2007Black,
  dxSkinOffice2007Blue, dxSkinOffice2007Green, dxSkinOffice2007Pink,
  dxSkinOffice2007Silver, dxSkinOffice2010Black, dxSkinOffice2010Blue,
  dxSkinOffice2010Silver, dxSkinOffice2013DarkGray, dxSkinOffice2013LightGray,
  dxSkinOffice2013White, dxSkinOffice2016Colorful, dxSkinOffice2016Dark,
  dxSkinPumpkin, dxSkinSeven, dxSkinSevenClassic, dxSkinSharp, dxSkinSharpPlus,
  dxSkinSilver, dxSkinSpringTime, dxSkinStardust, dxSkinSummer2008,
  dxSkinTheAsphaltWorld, dxSkinsDefaultPainters, dxSkinValentine,
  dxSkinVisualStudio2013Blue, dxSkinVisualStudio2013Dark,
  dxSkinVisualStudio2013Light, dxSkinVS2010, dxSkinWhiteprint,
  dxSkinXmas2008Blue, Vcl.StdCtrls, cxButtons, XSuperObject, XSuperJSON, MyAccess, Vcl.ExtCtrls,
  cxControls, cxContainer, cxEdit, cxTextEdit, cxMaskEdit, cxDropDownEdit,
  cxCalc;

type
  TfrmMain = class(TForm)
    btnSetupConfig: TcxButton;
    memLogs: TMemo;
    tmrConnectDB: TTimer;
    tmSync: TTimer;
    btnSaveLogs: TcxButton;
    SaveDialog1: TSaveDialog;
    btnStartStop: TcxButton;
    lblCounter: TLabel;
    edLLineCount: TcxCalcEdit;
    Label1: TLabel;
    btnManualSync: TcxButton;
    TrayIcon1: TTrayIcon;
    pmTray: TPopupMenu;
    miShow: TMenuItem;
    miManualSync: TMenuItem;
    miSep: TMenuItem;
    miExit: TMenuItem;
    tmrRate: TTimer;
    procedure btnSetupConfigClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure TrayIcon1DblClick(Sender: TObject);
    procedure miShowClick(Sender: TObject);
    procedure miExitClick(Sender: TObject);
    procedure tmrConnectDBTimer(Sender: TObject);
    procedure tmSyncTimer(Sender: TObject);
    procedure btnSaveLogsClick(Sender: TObject);
    procedure memLogsChange(Sender: TObject);
    procedure btnStartStopClick(Sender: TObject);
    procedure btnManualSyncClick(Sender: TObject);
    procedure tmrRateTimer(Sender: TObject);
  private
    { Private declarations }
    DBConnectAttempt: Integer;
    FAllowClose: Boolean;
    function PromptExitPassword(var APassword: string): Boolean;
    procedure LoadConfigApps;
    procedure SyncHRDInfo(const LastSyncStr, TargetSyncStr: String);
    procedure SyncAbsen(const LastSyncStr, TargetSyncStr: String);
    procedure SyncRekapAbsen(const LastSyncStr, TargetSyncStr: String);
    procedure SyncPayrollDetails(const LastSyncStr, TargetSyncStr: String);
    procedure SyncPosTransPayment(const LastSyncStr, TargetSyncStr: String);
    procedure SyncPosTransPaymentDetails(const LastSyncStr, TargetSyncStr: String);
    procedure SyncPosTransMaster(const LastSyncStr, TargetSyncStr: String);
    procedure SyncPosTransDetail(const LastSyncStr, TargetSyncStr: String);
    procedure SyncPosTransReject(const LastSyncStr, TargetSyncStr: String);
    procedure SyncPosGCSold(const LastSyncStr, TargetSyncStr: String);
    procedure SyncPosTrans(const LastSyncStr, TargetSyncStr: String);
    procedure SyncGuestRating;
    procedure ApplicationEventsException(Sender: TObject; E: Exception);
    procedure StopSync;
    procedure StartSync;
  public
    { Public declarations }
    LOCAL_DBNAME, LOCAL_DBUSER, LOCAL_DBHOST, LOCAL_DBPASS, LOCAL_DBPORT,
    USERAPPS, NAMEAPPS, GROUPAKSES,
    SERVER_DBNAME, SERVER_DBUSER, SERVER_DBHOST, SERVER_DBPASS, SERVER_DBPORT,
    STR_BUILDING, TXTPASS, TXTUSER, URLBASEMAILHOST, URLBASEMAILPORT,
    APP_VERSION, APP_TRADEMARK, APP_RELEASE, APP_NAME, APP_DEVELOPER,
    DBHRDNAME, DBPOSNAME, SESSION, APP_CHANGEDB, APP_OUTLETID, SATJUAL,
    APP_OUTLETNAME, APP_OUTLETADDRESS, APP_OUTLETPHONE, APP_OUTLETCITY,
    APP_OUTLETPROVINCE,APP_OUTLETZIPCODE, APP_OUTLETPLAT,
    MINPRICE, PASSDELETE, PASSCETAK, MEMBERDBNAME, JUDULATAS, JUDULBAWAH,
    MERGERDBNAME, FOOTER1, FOOTER2, FOOTER3, SUPABASE_URL, SUPABASE_KEY  : String;
    ConfigJSON : XSuperObject.ISuperObject;
    qrySearch, qryFind, qryTemp : TMyQuery;
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

uses FConfigSetup, FdmDB, MainSource, System.Net.HttpClient, System.Net.URLClient,
     System.DateUtils, Data.DB, FManualSync;

procedure TfrmMain.LoadConfigApps;
var
  jsonConfig: TStringList;
  ConfigDir: string;
begin
  ConfigDir := ExtractFilePath(Application.ExeName);
  if not FileExists(ConfigDir + 'config.json') then
    Exit;

  jsonConfig := TStringList.Create;
  try
    jsonConfig.LoadFromFile(ConfigDir + 'config.json');
    ConfigJSON := XSuperObject.SO(jsonConfig.Text);

    if Assigned(ConfigJSON) then
    begin
      // App settings
      if ConfigJSON.Contains('AppInfo') then
      begin
        APP_NAME := ConfigJSON.O['AppInfo'].S['AppName'];
        APP_VERSION := ConfigJSON.O['AppInfo'].S['Version'];
        APP_RELEASE := ConfigJSON.O['AppInfo'].S['Release'];
        APP_DEVELOPER := ConfigJSON.O['AppInfo'].S['Developer'];
        APP_TRADEMARK := ConfigJSON.O['AppInfo'].S['TradeMark'];
        APP_OUTLETID := ConfigJSON.O['AppInfo'].S['OutletID'];
//        SATJUAL,
        APP_OUTLETNAME := ConfigJSON.O['AppInfo'].S['OutletName'];
        APP_OUTLETADDRESS := ConfigJSON.O['AppInfo'].S['OutletAddress'];
        APP_OUTLETPHONE := ConfigJSON.O['AppInfo'].S['OutletPhone'];
        APP_OUTLETCITY := ConfigJSON.O['AppInfo'].S['OutletCity'];
        APP_OUTLETPROVINCE := ConfigJSON.O['AppInfo'].S['OutletProvince'];
        APP_OUTLETZIPCODE := ConfigJSON.O['AppInfo'].S['OutletZipcode'];
//        APP_OUTLETPLAT := ConfigJSON.O['AppInfo'].S['OutletID'];

      end;

      // LocalDB settings
      if ConfigJSON.Contains('LocalDB') then
      begin
        LOCAL_DBHOST := DecryptPass(ConfigJSON.O['LocalDB'].S['HostName']);
        LOCAL_DBUSER := DecryptPass(ConfigJSON.O['LocalDB'].S['UserName']);
        LOCAL_DBNAME := DecryptPass(ConfigJSON.O['LocalDB'].S['DBName']);
        LOCAL_DBPORT := DecryptPass(ConfigJSON.O['LocalDB'].S['Port']);
        LOCAL_DBPASS := DecryptPass(ConfigJSON.O['LocalDB'].S['Password']);
      end;

      // ServerDB settings
      if ConfigJSON.Contains('ServerDB') then
      begin
        SERVER_DBHOST := DecryptPass(ConfigJSON.O['ServerDB'].S['HostName']);
        SERVER_DBUSER := DecryptPass(ConfigJSON.O['ServerDB'].S['UserName']);
        SERVER_DBNAME := DecryptPass(ConfigJSON.O['ServerDB'].S['DBName']);
        SERVER_DBPORT := DecryptPass(ConfigJSON.O['ServerDB'].S['Port']);
        SERVER_DBPASS := DecryptPass(ConfigJSON.O['ServerDB'].S['Password']);
      end;

      // Supabase settings
      if ConfigJSON.Contains('Supabase') then
      begin
        SUPABASE_URL := Trim(DecryptPass(ConfigJSON.O['Supabase'].S['REST_URL']));
        if (SUPABASE_URL <> '') and not (SUPABASE_URL[Length(SUPABASE_URL)] in ['/', '\']) then
          SUPABASE_URL := SUPABASE_URL + '/';
        SUPABASE_KEY := Trim(DecryptPass(ConfigJSON.O['Supabase'].S['PublishableKey']));
      end;
    end;
  finally
    jsonConfig.Free;
  end;
end;

procedure TfrmMain.memLogsChange(Sender: TObject);
begin
     edLLineCount.EditValue := memLogs.Lines.Count;
end;

procedure TfrmMain.SyncAbsen(const LastSyncStr, TargetSyncStr: String);
var
  qryAbsen1 : TMyQuery;
  dtWaktuAbsen, dtWaktuAbsenUTC: TDateTime;
  sKodeKaryawan, sTanggal: String;
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Headers: TNetHeaders;
  JSONArray, JSONObj: ISuperObject;
  RequestBody: TStringStream;
  Endpoint: String;
begin
  qryAbsen1 := TMyQuery.Create(Self);
  HTTP := THTTPClient.Create;
  HTTP.ConnectionTimeout := 10000;
  HTTP.ResponseTimeout := 30000;
  try
    qryAbsen1.Connection := DMDB.dbInternal;
    
    // 1. Fetch new Absen Harian records using optimized JOIN and TIMESTAMP logic
    qryAbsen1.SQL.Text := 
      'SELECT a.*, k.kodekaryawan ' +
      'FROM absen_harian a ' +
      'LEFT JOIN ben_hrd_karyawan_info k ON a.id_karyawan = k.idkaryawan AND k.active = ''Y'' ' +
      'WHERE CONCAT(a.tanggal, '' '', a.waktu) > :LastSync AND CONCAT(a.tanggal, '' '', a.waktu) <= :TargetSync ' +
      'AND k.kodekaryawan IS NOT NULL ' + 
      'ORDER BY a.tanggal, a.waktu';
    qryAbsen1.ParamByName('LastSync').AsString := LastSyncStr;
    qryAbsen1.ParamByName('TargetSync').AsString := TargetSyncStr;
    qryAbsen1.Open;
    
    if not qryAbsen1.IsEmpty then
    begin
      memLogs.Lines.Add(Format('Found %d new attendance records to sync.', [qryAbsen1.RecordCount]));
      // Prepare HTTP Headers for Supabase
      SetLength(Headers, 3);
      Headers[0] := TNameValuePair.Create('apikey', SUPABASE_KEY);
      Headers[1] := TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY);
      Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');
      
      qryAbsen1.First;
      while not qryAbsen1.Eof do
      begin
        // Format TDateTime
        dtWaktuAbsen := qryAbsen1.FieldByName('tanggal').AsDateTime + qryAbsen1.FieldByName('waktu').AsDateTime;
        // Global Rule: Convert Local Timezone to UTC0 for Cloud DB
        dtWaktuAbsenUTC := TTimeZone.Local.ToUniversalTime(dtWaktuAbsen);
        
        sKodeKaryawan := qryAbsen1.FieldByName('kodekaryawan').AsString;
        sTanggal := FormatDateTime('yyyy-mm-dd', qryAbsen1.FieldByName('tanggal').AsDateTime);
        
        memLogs.Lines.Add(Format('  -> Pushing Absen: %s | Date: %s', [sKodeKaryawan, sTanggal]));
        
        // 3. GET check if already exists today for this employee
        Endpoint := SUPABASE_URL + 'ot_hrd_absen_harian?kodekaryawan=eq.' + sKodeKaryawan + '&tanggal=eq.' + sTanggal;
        Resp := HTTP.Get(Endpoint, nil, Headers);
        
        if Resp.StatusCode = 200 then
        begin
          JSONArray := SO(Resp.ContentAsString);
          if JSONArray.AsArray.Length = 0 then
          begin
            // POST - New Record (First tap of the day)
            JSONObj := SO();
            JSONObj.S['kode_outlet'] := APP_OUTLETID;
            JSONObj.S['kodekaryawan'] := sKodeKaryawan;
            JSONObj.S['id_karyawan'] := qryAbsen1.FieldByName('id_karyawan').AsString;
            JSONObj.S['nama'] := qryAbsen1.FieldByName('nama').AsString;
            JSONObj.S['tanggal'] := sTanggal;
            JSONObj.S['fp_in'] := DateToISO8601(dtWaktuAbsenUTC);
            
            RequestBody := TStringStream.Create(JSONObj.AsJSON, TEncoding.UTF8);
            try
              Resp := HTTP.Post(SUPABASE_URL + 'ot_hrd_absen_harian', RequestBody, nil, Headers);
              if (Resp.StatusCode <> 200) and (Resp.StatusCode <> 201) then
                memLogs.Lines.Add('  [!] POST Error: ' + IntToStr(Resp.StatusCode) + ' - ' + Resp.ContentAsString);
            finally
              RequestBody.Free;
            end;
          end
          else
          begin
            // PATCH - Update Existing Record (Subsequent tap / clock-out)
            JSONObj := SO();
            JSONObj.S['fp_out'] := DateToISO8601(dtWaktuAbsenUTC);
            
            RequestBody := TStringStream.Create(JSONObj.AsJSON, TEncoding.UTF8);
            try
              Resp := HTTP.Patch(SUPABASE_URL + 'ot_hrd_absen_harian?kodekaryawan=eq.' + sKodeKaryawan + '&tanggal=eq.' + sTanggal, RequestBody, nil, Headers);
              if (Resp.StatusCode <> 200) and (Resp.StatusCode <> 204) then
                memLogs.Lines.Add('  [!] PATCH Error: ' + IntToStr(Resp.StatusCode) + ' - ' + Resp.ContentAsString);
            finally
              RequestBody.Free;
            end;
          end;
        end;
        
        qryAbsen1.Next;
      end;
      memLogs.Lines.Add('Absen Sync sub-process completed.');
    end;
  except
    on E: Exception do
    begin
      memLogs.Lines.Add('Sync Absen Error: ' + E.Message);
      raise;
    end;
  end;
  
  qryAbsen1.Free;
  HTTP.Free;
end;

procedure TfrmMain.SyncHRDInfo(const LastSyncStr, TargetSyncStr: String);
var
  qryInfo, qryDetails : TMyQuery;
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Headers: TNetHeaders;
  JSONObj, JSONArray: ISuperObject;
  RequestBody: TStringStream;
  sKodeKaryawan, Endpoint: String;
begin
  qryInfo := TMyQuery.Create(Self);
  qryDetails := TMyQuery.Create(Self);
  HTTP := THTTPClient.Create;
  HTTP.ConnectionTimeout := 10000;
  HTTP.ResponseTimeout := 30000;
  try
    qryInfo.Connection := DMDB.dbInternal;
    qryDetails.Connection := DMDB.dbInternal;
    
    // Fetch updated Karyawan Info
    qryInfo.SQL.Text := 'SELECT * FROM ben_hrd_karyawan_info WHERE lasteditdate > :LastSync AND lasteditdate <= :TargetSync';
    qryInfo.ParamByName('LastSync').AsString := LastSyncStr;
    qryInfo.ParamByName('TargetSync').AsString := TargetSyncStr;
    qryInfo.Open;
    
    if not qryInfo.IsEmpty then
    begin
      memLogs.Lines.Add(Format('Found %d updated HRD Info records to sync.', [qryInfo.RecordCount]));
      
      SetLength(Headers, 4);
      Headers[0] := TNameValuePair.Create('apikey', SUPABASE_KEY);
      Headers[1] := TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY);
      Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');
      Headers[3] := TNameValuePair.Create('Prefer', 'resolution=merge-duplicates'); // For UPSERT
      
      qryInfo.First;
      while not qryInfo.Eof do
      begin
        sKodeKaryawan := qryInfo.FieldByName('kodekaryawan').AsString;
        memLogs.Lines.Add('  -> Syncing HRD Info: ' + sKodeKaryawan);
        
        // A. Upsert to ot_hrd_karyawan_info
        JSONObj := SO();
        JSONObj.S['kode_outlet'] := APP_OUTLETID;
        JSONObj.S['kodekaryawan'] := sKodeKaryawan;
        JSONObj.S['idkaryawan'] := qryInfo.FieldByName('idkaryawan').AsString;
        JSONObj.S['namakaryawan'] := qryInfo.FieldByName('namakaryawan').AsString;
        JSONObj.S['departemen'] := qryInfo.FieldByName('departemen').AsString;
        JSONObj.S['active'] := qryInfo.FieldByName('active').AsString;
        
        if not qryInfo.FieldByName('tglmasukkerja').IsNull then
          JSONObj.S['tglmasukkerja'] := FormatDateTime('yyyy-mm-dd', qryInfo.FieldByName('tglmasukkerja').AsDateTime);
        if not qryInfo.FieldByName('tglhabiskontrak').IsNull then
          JSONObj.S['tglhabiskontrak'] := FormatDateTime('yyyy-mm-dd', qryInfo.FieldByName('tglhabiskontrak').AsDateTime);

        JSONObj.S['namabank'] := qryInfo.FieldByName('namabank').AsString;
        JSONObj.S['norek'] := qryInfo.FieldByName('norek').AsString;
        JSONObj.S['namarek'] := qryInfo.FieldByName('namarek').AsString;
        
        RequestBody := TStringStream.Create(JSONObj.AsJSON, TEncoding.UTF8);
        try
          Resp := HTTP.Post(SUPABASE_URL + 'ot_hrd_karyawan_info?on_conflict=kodekaryawan', RequestBody, nil, Headers);
          if (Resp.StatusCode <> 200) and (Resp.StatusCode <> 201) then
            memLogs.Lines.Add('  [!] HRD Info Upsert Error: ' + IntToStr(Resp.StatusCode) + ' ' + Resp.ContentAsString);
        finally
          RequestBody.Free;
        end;
        
        // B. Sync Details using GET/POST/PATCH fallback because it lacks unique constraint
        qryDetails.SQL.Text := 'SELECT * FROM ben_hrd_karyawan_details WHERE idkaryawan = :idk';
        qryDetails.ParamByName('idk').AsString := qryInfo.FieldByName('idkaryawan').AsString;
        qryDetails.Open;
        
        if not qryDetails.IsEmpty then
        begin
          Endpoint := SUPABASE_URL + 'ot_hrd_karyawan_details?kodekaryawan=eq.' + sKodeKaryawan;
          
          Resp := HTTP.Get(Endpoint, nil, [
            TNameValuePair.Create('apikey', SUPABASE_KEY),
            TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY),
            TNameValuePair.Create('Content-Type', 'application/json')
          ]);
          
          JSONObj := SO();
          JSONObj.S['kode_outlet'] := APP_OUTLETID;
          JSONObj.S['kodekaryawan'] := sKodeKaryawan;
          JSONObj.S['idkaryawan'] := qryDetails.FieldByName('idkaryawan').AsString;
          JSONObj.S['namakaryawan'] := qryDetails.FieldByName('namakaryawan').AsString;
          JSONObj.S['sex'] := qryDetails.FieldByName('sex').AsString;
          JSONObj.S['active'] := qryDetails.FieldByName('active').AsString;
          
          JSONObj.S['noidentitas'] := qryDetails.FieldByName('noidentitas').AsString;
          JSONObj.S['alamattinggal'] := qryDetails.FieldByName('alamattinggal').AsString;
          JSONObj.S['telpfixline'] := qryDetails.FieldByName('telpfixline').AsString;
          JSONObj.S['telpponsel'] := qryDetails.FieldByName('telpponsel').AsString;
          JSONObj.S['tempatlahir'] := qryDetails.FieldByName('tempatlahir').AsString;
          
          if not qryDetails.FieldByName('tgllahir').IsNull then
            JSONObj.S['tgllahir'] := FormatDateTime('yyyy-mm-dd', qryDetails.FieldByName('tgllahir').AsDateTime);
            
          JSONObj.S['agamaid'] := qryDetails.FieldByName('agamaid').AsString;
          JSONObj.S['goldarah'] := qryDetails.FieldByName('goldarah').AsString;
          JSONObj.S['alamatemail'] := qryDetails.FieldByName('alamatemail').AsString;
          
          RequestBody := TStringStream.Create(JSONObj.AsJSON, TEncoding.UTF8);
          try
            if Resp.StatusCode = 200 then
            begin
              JSONArray := SO(Resp.ContentAsString);
              if JSONArray.AsArray.Length = 0 then
              begin
                Resp := HTTP.Post(SUPABASE_URL + 'ot_hrd_karyawan_details', RequestBody, nil, [
                  TNameValuePair.Create('apikey', SUPABASE_KEY),
                  TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY),
                  TNameValuePair.Create('Content-Type', 'application/json')
                ]);
              end
              else
              begin
                Resp := HTTP.Patch(Endpoint, RequestBody, nil, [
                  TNameValuePair.Create('apikey', SUPABASE_KEY),
                  TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY),
                  TNameValuePair.Create('Content-Type', 'application/json')
                ]);
              end;
              if (Resp.StatusCode <> 200) and (Resp.StatusCode <> 201) and (Resp.StatusCode <> 204) then
                memLogs.Lines.Add('  [!] HRD Details Sync Error: ' + IntToStr(Resp.StatusCode) + ' ' + Resp.ContentAsString);
            end;
          finally
            RequestBody.Free;
          end;
        end;
        
        qryInfo.Next;
      end;
      memLogs.Lines.Add('HRD Info Sync sub-process completed.');
    end;
  except
    on E: Exception do
    begin
      memLogs.Lines.Add('Sync HRD Error: ' + E.Message);
      raise;
    end;
  end;
  
  qryInfo.Free;
  qryDetails.Free;
  HTTP.Free;
end;

procedure TfrmMain.SyncRekapAbsen(const LastSyncStr, TargetSyncStr: String);
var
  qryRekap : TMyQuery;
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Headers: TNetHeaders;
  JSONObj: ISuperObject;
  RequestBody: TStringStream;
  sKodeKaryawan, sTanggal: String;
begin
  qryRekap := TMyQuery.Create(Self);
  HTTP := THTTPClient.Create;
  HTTP.ConnectionTimeout := 10000;
  HTTP.ResponseTimeout := 30000;
  try
    qryRekap.Connection := DMDB.dbInternal;
    
    // Fetch only recently modified records
    qryRekap.SQL.Text := 'SELECT * FROM ben_presensi_rekap WHERE lasteditdate > :LastSync AND lasteditdate <= :TargetSync';
    qryRekap.ParamByName('LastSync').AsString := LastSyncStr;
    qryRekap.ParamByName('TargetSync').AsString := TargetSyncStr;
    qryRekap.Open;
    
    if not qryRekap.IsEmpty then
    begin
      memLogs.Lines.Add(Format('Found %d updated Presensi Rekap records to sync.', [qryRekap.RecordCount]));
      
      // Prepare UPSERT Headers
      SetLength(Headers, 4);
      Headers[0] := TNameValuePair.Create('apikey', SUPABASE_KEY);
      Headers[1] := TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY);
      Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');
      Headers[3] := TNameValuePair.Create('Prefer', 'resolution=merge-duplicates'); 
      
      qryRekap.First;
      while not qryRekap.Eof do
      begin
        sKodeKaryawan := qryRekap.FieldByName('kodekaryawan').AsString;
        
        if not qryRekap.FieldByName('tanggal').IsNull then
          sTanggal := FormatDateTime('yyyy-mm-dd', qryRekap.FieldByName('tanggal').AsDateTime)
        else
          sTanggal := '';
          
        memLogs.Lines.Add(Format('  -> Upserting Presensi Rekap: %s | Date: %s', [sKodeKaryawan, sTanggal]));
        
        JSONObj := SO();
        JSONObj.S['kode_outlet'] := APP_OUTLETID;
        JSONObj.I['autonum'] := qryRekap.FieldByName('autonum').AsInteger;
        JSONObj.S['payrollperiode'] := qryRekap.FieldByName('payrollperiode').AsString;
        JSONObj.S['tanggal'] := sTanggal;
        JSONObj.S['kodekaryawan'] := sKodeKaryawan;
        JSONObj.S['idkaryawan'] := qryRekap.FieldByName('idkaryawan').AsString;
        JSONObj.S['tagmasuk'] := qryRekap.FieldByName('tagmasuk').AsString;
        JSONObj.S['tagkeluar'] := qryRekap.FieldByName('tagkeluar').AsString;
        JSONObj.S['tagauto'] := qryRekap.FieldByName('tagauto').AsString;
        JSONObj.S['tagresult'] := qryRekap.FieldByName('tagresult').AsString;
        
        if not qryRekap.FieldByName('selmasuk').IsNull then
          JSONObj.I['selmasuk'] := qryRekap.FieldByName('selmasuk').AsInteger;
        if not qryRekap.FieldByName('selkeluar').IsNull then
          JSONObj.I['selkeluar'] := qryRekap.FieldByName('selkeluar').AsInteger;
          
        // Using string mapping for floats to prevent Delphi comma/dot locale issues reaching Postgres
        if not qryRekap.FieldByName('jkwajib').IsNull then
          JSONObj.S['jkwajib'] := StringReplace(FloatToStr(qryRekap.FieldByName('jkwajib').AsFloat), ',', '.', [rfReplaceAll]);
        if not qryRekap.FieldByName('jkreal').IsNull then
          JSONObj.S['jkreal'] := StringReplace(FloatToStr(qryRekap.FieldByName('jkreal').AsFloat), ',', '.', [rfReplaceAll]);
        if not qryRekap.FieldByName('komisi').IsNull then
          JSONObj.S['komisi'] := StringReplace(FloatToStr(qryRekap.FieldByName('komisi').AsFloat), ',', '.', [rfReplaceAll]);
          
        JSONObj.S['notes'] := qryRekap.FieldByName('notes').AsString;
        JSONObj.S['keterangan'] := qryRekap.FieldByName('keterangan').AsString;
        JSONObj.S['libnas'] := qryRekap.FieldByName('libnas').AsString;
        JSONObj.S['lastedituser'] := qryRekap.FieldByName('lastedituser').AsString;
        
        if not qryRekap.FieldByName('lasteditdate').IsNull then
          JSONObj.S['lasteditdate'] := DateToISO8601(TTimeZone.Local.ToUniversalTime(qryRekap.FieldByName('lasteditdate').AsDateTime));
        
        RequestBody := TStringStream.Create(JSONObj.AsJSON, TEncoding.UTF8);
        try
          Resp := HTTP.Post(SUPABASE_URL + 'ot_hrd_presensi_rekap?on_conflict=kode_outlet,autonum', RequestBody, nil, Headers);
          if (Resp.StatusCode <> 200) and (Resp.StatusCode <> 201) then
            memLogs.Lines.Add('  [!] Presensi Rekap Upsert Error: ' + IntToStr(Resp.StatusCode) + ' ' + Resp.ContentAsString);
        finally
          RequestBody.Free;
        end;
        
        qryRekap.Next;
      end;
      memLogs.Lines.Add('Presensi Rekap Sync sub-process completed.');
    end;
  except
    on E: Exception do
    begin
      memLogs.Lines.Add('Sync Presensi Rekap Error: ' + E.Message);
      raise;
    end;
  end;
  
  qryRekap.Free;
  HTTP.Free;
end;

procedure TfrmMain.SyncPayrollDetails(const LastSyncStr, TargetSyncStr: String);
var
  qryPayroll : TMyQuery;
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Headers: TNetHeaders;
  JSONObj, JSONData: ISuperObject;
  RequestBody: TStringStream;
  sKodeKaryawan, FN: String;
  I: Integer;
begin
  qryPayroll := TMyQuery.Create(Self);
  HTTP := THTTPClient.Create;
  HTTP.ConnectionTimeout := 10000;
  HTTP.ResponseTimeout := 30000;
  try
    qryPayroll.Connection := DMDB.dbInternal;
    
    // Fetch only recently modified records
    qryPayroll.SQL.Text := 'SELECT * FROM ben_payroll_details WHERE lasteditdate > :LastSync AND lasteditdate <= :TargetSync';
    qryPayroll.ParamByName('LastSync').AsString := LastSyncStr;
    qryPayroll.ParamByName('TargetSync').AsString := TargetSyncStr;
    qryPayroll.Open;
    
    if not qryPayroll.IsEmpty then
    begin
      memLogs.Lines.Add(Format('Found %d updated Payroll Details to sync.', [qryPayroll.RecordCount]));
      
      // Prepare UPSERT Headers
      SetLength(Headers, 4);
      Headers[0] := TNameValuePair.Create('apikey', SUPABASE_KEY);
      Headers[1] := TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY);
      Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');
      Headers[3] := TNameValuePair.Create('Prefer', 'resolution=merge-duplicates'); 
      
      qryPayroll.First;
      while not qryPayroll.Eof do
      begin
        sKodeKaryawan := qryPayroll.FieldByName('kodekaryawan').AsString;
        memLogs.Lines.Add(Format('  -> Upserting Payroll: %s', [sKodeKaryawan]));
        
        JSONObj := SO();
        JSONObj.S['kode_outlet'] := APP_OUTLETID;
        JSONObj.I['local_autonum'] := qryPayroll.FieldByName('autonum').AsInteger;
        JSONObj.S['kodekaryawan'] := sKodeKaryawan;
        
        // Explicitly set nilaithp for fast dashboard querying (as requested)
        if not qryPayroll.FieldByName('nilaithp').IsNull then
          JSONObj.S['nilaithp'] := StringReplace(FloatToStr(qryPayroll.FieldByName('nilaithp').AsFloat), ',', '.', [rfReplaceAll]);
        
        // Explicitly set payrollperiode for fast period filtering
        if not qryPayroll.FieldByName('payrollperiode').IsNull then
          JSONObj.S['payrollperiode'] := qryPayroll.FieldByName('payrollperiode').AsString
        else
          JSONObj.Null['payrollperiode'] := jNull;
        
        // Create the nested JSON for all dynamic payroll metrics
        JSONData := SO();
        for I := 0 to qryPayroll.FieldCount - 1 do
        begin
          FN := LowerCase(qryPayroll.Fields[I].FieldName);
          // Skip fields we are explicitly handling at the root level
          if (FN <> 'autonum') and (FN <> 'idoutlet') and (FN <> 'kodekaryawan') then
          begin
            if not qryPayroll.Fields[I].IsNull then
            begin
              case qryPayroll.Fields[I].DataType of
                ftInteger, ftSmallint, ftWord, ftLargeint: 
                  JSONData.I[qryPayroll.Fields[I].FieldName] := qryPayroll.Fields[I].AsInteger;
                ftFloat, ftCurrency, ftBCD, ftFMTBcd: 
                  JSONData.S[qryPayroll.Fields[I].FieldName] := StringReplace(FloatToStr(qryPayroll.Fields[I].AsFloat), ',', '.', [rfReplaceAll]);
                ftDate, ftDateTime, ftTime, ftTimeStamp:
                  JSONData.S[qryPayroll.Fields[I].FieldName] := FormatDateTime('yyyy-mm-dd hh:nn:ss', qryPayroll.Fields[I].AsDateTime);
                else
                  JSONData.S[qryPayroll.Fields[I].FieldName] := qryPayroll.Fields[I].AsString;
              end;
            end;
          end;
        end;
        
        // Embed the nested JSON object into the root payload
        JSONObj.O['payroll_data'] := JSONData;
        
        RequestBody := TStringStream.Create(JSONObj.AsJSON, TEncoding.UTF8);
        try
          // POST to Supabase using upsert, relying on unique constraint (kode_outlet, local_autonum)
          Resp := HTTP.Post(SUPABASE_URL + 'ot_hrd_karyawan_payroll_details?on_conflict=kode_outlet,local_autonum', RequestBody, nil, Headers);
          if (Resp.StatusCode <> 200) and (Resp.StatusCode <> 201) then
            memLogs.Lines.Add('  [!] Payroll Upsert Error: ' + IntToStr(Resp.StatusCode) + ' ' + Resp.ContentAsString);
        finally
          RequestBody.Free;
        end;
        
        qryPayroll.Next;
      end;
      memLogs.Lines.Add('Payroll Sync sub-process completed.');
    end;
  except
    on E: Exception do
    begin
      memLogs.Lines.Add('Sync Payroll Error: ' + E.Message);
      raise;
    end;
  end;
  
  qryPayroll.Free;
  HTTP.Free;
end;

{$I PosSync.pas}
{$I RateSync.pas}

function TfrmMain.PromptExitPassword(var APassword: string): Boolean;
var
  Dlg: TForm;
  lbl: TLabel;
  edt: TEdit;
  btnOk, btnCancel: TButton;
begin
  Result := False;
  Dlg := TForm.Create(nil);
  try
    Dlg.Position := poScreenCenter;
    Dlg.BorderStyle := bsDialog;
    Dlg.BorderIcons := [biSystemMenu];
    Dlg.Caption := 'Security Verification';
    Dlg.ClientWidth := 300;
    Dlg.ClientHeight := 130;
    Dlg.Font.Name := 'Tahoma';
    Dlg.Font.Size := 9;

    lbl := TLabel.Create(Dlg);
    lbl.Parent := Dlg;
    lbl.SetBounds(16, 16, 268, 16);
    lbl.Caption := 'Enter password to exit Sync Agent:';

    edt := TEdit.Create(Dlg);
    edt.Parent := Dlg;
    edt.SetBounds(16, 40, 268, 24);
    edt.PasswordChar := '*';

    btnOk := TButton.Create(Dlg);
    btnOk.Parent := Dlg;
    btnOk.SetBounds(126, 85, 75, 28);
    btnOk.Caption := 'OK';
    btnOk.Default := True;
    btnOk.ModalResult := mrOk;

    btnCancel := TButton.Create(Dlg);
    btnCancel.Parent := Dlg;
    btnCancel.SetBounds(209, 85, 75, 28);
    btnCancel.Caption := 'Cancel';
    btnCancel.Cancel := True;
    btnCancel.ModalResult := mrCancel;

    if Dlg.ShowModal = mrOk then
    begin
      APassword := edt.Text;
      Result := True;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Application.OnException := ApplicationEventsException;
  FAllowClose := False;
  TrayIcon1.Visible := True;
  TrayIcon1.Hint := 'Zen Sync Agent - Active';
  memLogs.Lines.Clear;
  memLogs.Lines.Add('Application Started. Loading config...');
  DBConnectAttempt := 0;
  LoadConfigApps;
end;

procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FAllowClose then
  begin
    CanClose := True;
    Exit;
  end;

  // Option 3: Do NOT terminate on [X], Alt+F4, or Taskbar close.
  // Instead, minimize to system tray so synchronization continues uninterrupted.
  CanClose := False;
  Hide;
  WindowState := wsMinimized;
  TrayIcon1.Visible := True;
  TrayIcon1.BalloonTitle := 'Zen Sync Agent';
  TrayIcon1.BalloonHint := 'Sync Agent is minimized to the system tray. Background synchronization remains active.';
  TrayIcon1.BalloonFlags := bfInfo;
  TrayIcon1.BalloonTimeout := 3000;
  TrayIcon1.ShowBalloonHint;
  memLogs.Lines.Add(Format('[SYSTEM] %s - Application minimized to system tray. Synchronization remains active.', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]));
end;

procedure TfrmMain.TrayIcon1DblClick(Sender: TObject);
begin
  Show;
  WindowState := wsNormal;
  Application.BringToFront;
  BringToFront;
end;

procedure TfrmMain.miShowClick(Sender: TObject);
begin
  TrayIcon1DblClick(Sender);
end;

procedure TfrmMain.miExitClick(Sender: TObject);
var
  sInputPass, sExpectedPass: string;
begin
  sExpectedPass := 'ZenSpa168';
  if (ConfigJSON <> nil) then
  begin
    if ConfigJSON.S['ExitPassword'] <> '' then
      sExpectedPass := ConfigJSON.S['ExitPassword']
    else if ConfigJSON.Contains('AppInfo') and (ConfigJSON.O['AppInfo'].S['ExitPassword'] <> '') then
      sExpectedPass := ConfigJSON.O['AppInfo'].S['ExitPassword'];
  end;

  if PromptExitPassword(sInputPass) then
  begin
    if sInputPass = sExpectedPass then
    begin
      memLogs.Lines.Add(Format('[SECURITY] %s - Authorized exit password entered. Shutting down Sync Agent...', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]));
      FAllowClose := True;
      tmSync.Enabled := False;
      tmrRate.Enabled := False;
      tmrConnectDB.Enabled := False;
      Close;
    end
    else
    begin
      memLogs.Lines.Add(Format('[SECURITY] %s - Unauthorized exit attempt with invalid password.', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]));
    end;
  end;
end;

procedure TfrmMain.tmrConnectDBTimer(Sender: TObject);
begin
  tmrConnectDB.Enabled := False; // Pause timer while attempting
  Inc(DBConnectAttempt);
  
  if DBConnectAttempt > 10 then
  begin
    memLogs.Lines.Add('Max connection attempts (10) reached. Connection failed. Pausing retries.');
    Exit;
  end;

  memLogs.Lines.Add(Format('Attempting to connect to local database (%d/10)...', [DBConnectAttempt]));
  memLogs.Lines.Add(Format('Host: %s | DB: %s', [LOCAL_DBHOST, LOCAL_DBNAME]));

  try
    dmDB.dbInternal.Connected := False;
    dmDB.dbInternal.Server := LOCAL_DBHOST;
    dmDB.dbInternal.UserName := LOCAL_DBUSER;
    dmDB.dbInternal.Password := LOCAL_DBPASS;
    dmDB.dbInternal.Port := StrToIntDef(LOCAL_DBPORT, 3306);
    dmDB.dbInternal.Database := LOCAL_DBNAME;
    
    dmDB.dbInternal.Connected := True;
    
    memLogs.Lines.Add('SUCCESS: Connected to local database!');
    DBConnectAttempt := 0; // Reset on success
    
    // Wire up and start the synchronization timer dynamically
    tmSync.Interval := 60000; // 1 minute
    tmSync.OnTimer := tmSyncTimer;
    tmrRate.Interval := 5000; // 5 seconds
    tmrRate.OnTimer := tmrRateTimer;
    btnStartStop.Click;
//    tmSync.Enabled := True;
//    memLogs.Lines.Add('Sync Timer started (1 min interval).');
  except
    on E: Exception do
    begin
      memLogs.Lines.Add('ERROR: ' + E.Message);
      tmrConnectDB.Enabled := True; // Resume timer for next retry
    end;
  end;
end;

procedure TfrmMain.FormShow(Sender: TObject);
begin
     {
     qryLogin := TmySQLQuery.Create(Self);
     qryLogin.Database := DMDB.StoreDB;
     qryLogin.SQL.Add('select * from temptable');
     qryLogin.Active := true
     }
end;

procedure TfrmMain.btnSetupConfigClick(Sender: TObject);
begin
    Application.CreateForm(TfrmConfigSetup, frmConfigSetup);
    tmSync.Enabled := False;
    tmrRate.Enabled := False;
    lblCounter.Caption := 'TIMER STOPED';
    lblCounter.Font.Color := clRed;
    frmConfigSetup.Show;
end;

procedure TfrmMain.ApplicationEventsException(Sender: TObject; E: Exception);
begin
  memLogs.Lines.Add('[!] System Exception: ' + E.Message + '. Auto-retry on next cycle.');
  tmSync.Enabled := True;
end;

procedure TfrmMain.StopSync;
begin
  tmSync.Enabled := False;
  tmrRate.Enabled := False;
  lblCounter.Caption := 'TIMER STOPED';
  lblCounter.Font.Color := clRed;
  memLogs.Lines.Add('Sync Timer Stopped');
end;

procedure TfrmMain.StartSync;
begin
  tmSync.Enabled := True;
  tmrRate.Enabled := True;
  lblCounter.Caption := 'TIMER START';
  lblCounter.Font.Color := clGreen;
  memLogs.Lines.Add('Sync Timer started (1 min interval).');
  memLogs.Lines.Add('Guest Rating Timer started (5s interval).');
end;

procedure TfrmMain.tmrRateTimer(Sender: TObject);
begin
  tmrRate.Enabled := False;
  try
    SyncGuestRating;
  finally
    tmrRate.Enabled := True;
  end;
end;

procedure TfrmMain.btnStartStopClick(Sender: TObject);
begin
  if (tmSync.Enabled = False) and (lblCounter.Caption <> 'TIMER START') then
    StartSync
  else
    StopSync;
end;

procedure TfrmMain.tmSyncTimer(Sender: TObject);
var
  qryConfig: TMyQuery;
  CurrentSyncTime, SyncTargetTime, LastSyncTime: TDateTime;
  sLastSyncStr, sSyncTargetStr: String;
  FS: TFormatSettings;
  bSyncFailed, bMySQLAlive: Boolean;
  HTTPCheck: THTTPClient;
  CheckHeaders: TNetHeaders;
  CheckResp: IHTTPResponse;
begin
  tmSync.Enabled := False;
  bSyncFailed := False;
  if (edLLineCount.EditValue >= 2000) then
  begin
       memLogs.Clear;
  end;

  // 1. Pre-flight Check: Local MySQL Connection Health & Ping
  try
    if not dmDB.dbInternal.Connected then
    begin
      memLogs.Lines.Add('[!] Local MySQL connection inactive. Attempting reconnection...');
      dmDB.dbInternal.Connected := True;
    end
    else
    begin
      // Ping sends a MySQL ping packet; raises EMyError if the server dropped the connection
      dmDB.dbInternal.Ping;
    end;
    bMySQLAlive := dmDB.dbInternal.Connected;
  except
    on E: Exception do
    begin
      memLogs.Lines.Add('[!] Local MySQL ping/reconnect failed: ' + E.Message);
      try
        dmDB.dbInternal.Connected := False;
        dmDB.dbInternal.Connected := True;
        bMySQLAlive := dmDB.dbInternal.Connected;
      except
        bMySQLAlive := False;
      end;
    end;
  end;

  if not bMySQLAlive then
  begin
    memLogs.Lines.Add('[!] Local MySQL offline/unreachable. Chunk anchor preserved. Retrying in 1 min...');
    tmSync.Enabled := True; // Keep timer active for auto-retry
    Exit;
  end;

  // 2. Pre-flight Check: Supabase Cloud Connectivity (Internet connection check)
  HTTPCheck := THTTPClient.Create;
  try
    HTTPCheck.ConnectionTimeout := 5000; // 5s connection timeout
    HTTPCheck.ResponseTimeout := 8000;   // 8s response timeout
    SetLength(CheckHeaders, 2);
    CheckHeaders[0] := TNameValuePair.Create('apikey', SUPABASE_KEY);
    CheckHeaders[1] := TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY);
    try
      CheckResp := HTTPCheck.Get(SUPABASE_URL + 'master_outlet?select=kode_outlet&limit=1', nil, CheckHeaders);
      if (CheckResp.StatusCode <> 200) and (CheckResp.StatusCode <> 206) then
      begin
        memLogs.Lines.Add(Format('[!] Supabase Cloud health check returned HTTP %d. Network/cloud unavailable. Retrying in 1 min...', [CheckResp.StatusCode]));
        tmSync.Enabled := True; // Keep timer active for auto-retry
        Exit;
      end;
    except
      on E: Exception do
      begin
        memLogs.Lines.Add('[!] Supabase Cloud unreachable (Internet connection lost/offline): ' + E.Message + '. Retrying in 1 min...');
        tmSync.Enabled := True; // Keep timer active for auto-retry
        Exit;
      end;
    end;
  finally
    HTTPCheck.Free;
  end;

  CurrentSyncTime := Now;
  
  qryConfig := TMyQuery.Create(Self);
  try
    try
      qryConfig.Connection := DMDB.dbInternal;
      qryConfig.SQL.Text := 'SELECT details FROM configapp WHERE configname = ''LAST_SYNC''';
      qryConfig.Open;
      
      if qryConfig.IsEmpty then
      begin
        qryConfig.SQL.Text := 'INSERT INTO configapp (configname, details) VALUES (''LAST_SYNC'', :dt)';
        qryConfig.ParamByName('dt').AsString := FormatDateTime('yyyy-mm-dd hh:nn:ss', CurrentSyncTime);
        qryConfig.Execute;
        sLastSyncStr := '2026-09-01 00:00:00'; // Default safe past date
        LastSyncTime := EncodeDateTime(2026, 9, 1, 0, 0, 0, 0);
      end
      else
      begin
        sLastSyncStr := qryConfig.FieldByName('details').AsString;
        
        // Setup FormatSettings to handle SQL format robustly
        FS := TFormatSettings.Create('en-US');
        FS.DateSeparator := '-';
        FS.TimeSeparator := ':';
        FS.ShortDateFormat := 'yyyy-mm-dd';
        
        // TryStrToDateTime prevents the Delphi IDE debugger from interrupting with EConvertError
        if not TryStrToDateTime(sLastSyncStr, LastSyncTime, FS) then
        begin
          LastSyncTime := EncodeDateTime(2026, 9, 1, 0, 0, 0, 0);
          sLastSyncStr := '2026-09-01 00:00:00';
        end;
      end;
      
      // Time-based chunking (12 hours per cycle to avoid memory blowouts)
      if (CurrentSyncTime - LastSyncTime) > 0.5 then
        SyncTargetTime := LastSyncTime + 0.5
      else
        SyncTargetTime := CurrentSyncTime;
        
      sSyncTargetStr := FormatDateTime('yyyy-mm-dd hh:nn:ss', SyncTargetTime);
      
      memLogs.Lines.Add('--------------------------------------------------');
      memLogs.Lines.Add('Starting Global Sync Cycle (Chunked)...');
      memLogs.Lines.Add('Sync Window: ' + sLastSyncStr + ' TO ' + sSyncTargetStr);

      // Call individual sync routines in dependency order
      SyncHRDInfo(sLastSyncStr, sSyncTargetStr);
      SyncAbsen(sLastSyncStr, sSyncTargetStr);
      SyncRekapAbsen(sLastSyncStr, sSyncTargetStr);
      SyncPayrollDetails(sLastSyncStr, sSyncTargetStr);
      SyncPosTrans(sLastSyncStr, sSyncTargetStr);

      // Update global anchor to the chunk target
      qryConfig.SQL.Text := 'UPDATE configapp SET details = :dt WHERE configname = ''LAST_SYNC''';
      qryConfig.ParamByName('dt').AsString := sSyncTargetStr;
      qryConfig.Execute;
      
      memLogs.Lines.Add('Global Sync Cycle chunk completed. Anchor updated.');
    except
      on E: Exception do
      begin
        bSyncFailed := True;
        memLogs.Lines.Add('Global Sync Error: ' + E.Message);
      end;
    end;
  finally
    qryConfig.Free;
  end;
  
  if bSyncFailed then
  begin
    memLogs.Lines.Add('[!] Sub-routine failure detected. Chunk anchor preserved. Auto-retrying in 1 min...');
    tmSync.Enabled := True; // Auto-retry on next cycle!
  end
  else
  begin
    tmSync.Enabled := True; // Resume timer for next interval
  end;
end;

procedure TfrmMain.btnManualSyncClick(Sender: TObject);
begin
    StopSync;
    Application.CreateForm(TfrmManualSync, frmManualSync);
    frmManualSync.ShowModal;
end;

procedure TfrmMain.btnSaveLogsClick(Sender: TObject);
begin
  SaveDialog1.Filter := 'Text Files (*.txt)|*.txt|All Files (*.*)|*.*';
  SaveDialog1.DefaultExt := 'txt';
  SaveDialog1.FileName := 'SyncLogs_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.txt';
  if SaveDialog1.Execute then
  begin
    memLogs.Lines.SaveToFile(SaveDialog1.FileName);
    memLogs.Lines.Add('SUCCESS: Logs saved to ' + SaveDialog1.FileName);
  end;
end;

end.
