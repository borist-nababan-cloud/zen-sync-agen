unit FManualSync;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, cxGraphics, cxControls,
  cxLookAndFeels, cxLookAndFeelPainters, dxSkinsCore, dxSkinBlack, dxSkinBlue,
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
  dxSkinXmas2008Blue, cxContainer, cxEdit, cxCheckListBox, Vcl.Menus, cxButtons,
  Data.DB, MemDS, DBAccess, MyAccess,
  System.Net.HttpClient, System.Net.URLClient, System.StrUtils, System.DateUtils,
  XSuperObject, XSuperJSON, FdmDB;

type
  TfrmManualSync = class(TForm)
    manLogs: TMemo;
    listBox: TcxCheckListBox;
    btnStartManual: TcxButton;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure btnStartManualClick(Sender: TObject);
  private
    { Private declarations }
    function GetBaseRESTUrl: String;
    procedure SyncManualHRDInfo;
    procedure SyncManualMasterRoom;
    procedure SyncManualGCItems;
    procedure SyncManualPayroll;
  public
    { Public declarations }
  end;

var
  frmManualSync: TfrmManualSync;

implementation

uses FMain;

{$R *.dfm}

procedure TfrmManualSync.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;
  frmManualSync := nil;
end;

function TfrmManualSync.GetBaseRESTUrl: String;
begin
  Result := Trim(frmMain.SUPABASE_URL);
  if (Result <> '') and not (Result[Length(Result)] in ['/', '\']) then
    Result := Result + '/';
end;

procedure TfrmManualSync.btnStartManualClick(Sender: TObject);
var
  AnySelected: Boolean;
  I: Integer;
begin
  AnySelected := False;
  for I := 0 to listBox.Items.Count - 1 do
  begin
    if listBox.Items[I].Checked then
    begin
      AnySelected := True;
      Break;
    end;
  end;

  if not AnySelected then
  begin
    manLogs.Lines.Add('[!] Please check at least one item in the list before starting manual sync.');
    Exit;
  end;

  btnStartManual.Enabled := False;
  listBox.Enabled := False;
  try
    manLogs.Lines.Add('=====================================================');
    manLogs.Lines.Add(Format('MANUAL SYNC STARTED AT %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]));
    manLogs.Lines.Add(Format('Target Outlet Code: %s', [frmMain.APP_OUTLETID]));
    manLogs.Lines.Add('=====================================================');

    // Item 0: HRD Karyawan Info & Details
    if (listBox.Items.Count > 0) and listBox.Items[0].Checked then
      SyncManualHRDInfo;

    // Item 1: Master Room
    if (listBox.Items.Count > 1) and listBox.Items[1].Checked then
      SyncManualMasterRoom;

    // Item 2: GC Items
    if (listBox.Items.Count > 2) and listBox.Items[2].Checked then
      SyncManualGCItems;

    // Item 3: Payroll
    if (listBox.Items.Count > 3) and listBox.Items[3].Checked then
      SyncManualPayroll;

    manLogs.Lines.Add('=====================================================');
    manLogs.Lines.Add(Format('MANUAL SYNC COMPLETED AT %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]));
    manLogs.Lines.Add('=====================================================');
  finally
    btnStartManual.Enabled := True;
    listBox.Enabled := True;
  end;
end;

procedure TfrmManualSync.SyncManualHRDInfo;
var
  qryInfo, qryDetails: TMyQuery;
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Headers: TNetHeaders;
  JSONObj, JSONArray: ISuperObject;
  RequestBody: TStringStream;
  sKodeKaryawan, Endpoint, BaseURL: String;
  TotalCount, SuccessCount: Integer;
begin
  manLogs.Lines.Add('');
  manLogs.Lines.Add('--- [1/3] Syncing HRD Karyawan Info & Details (Full Master) ---');

  BaseURL := GetBaseRESTUrl;
  if (BaseURL = '') or (frmMain.SUPABASE_KEY = '') then
  begin
    manLogs.Lines.Add('  [!] ERROR: Supabase URL or Key is not configured!');
    Exit;
  end;

  qryInfo := TMyQuery.Create(Self);
  qryDetails := TMyQuery.Create(Self);
  HTTP := THTTPClient.Create;
  try
    qryInfo.Connection := dmDB.dbInternal;
    qryDetails.Connection := dmDB.dbInternal;

    // Full fetch of all employee master records
    qryInfo.SQL.Text := 'SELECT * FROM ben_hrd_karyawan_info ORDER BY kodekaryawan ASC';
    qryInfo.Open;

    if qryInfo.IsEmpty then
    begin
      manLogs.Lines.Add('  -> No employee records found in ben_hrd_karyawan_info.');
      Exit;
    end;

    TotalCount := qryInfo.RecordCount;
    SuccessCount := 0;
    manLogs.Lines.Add(Format('  -> Found %d employee master records to sync.', [TotalCount]));

    SetLength(Headers, 4);
    Headers[0] := TNameValuePair.Create('apikey', frmMain.SUPABASE_KEY);
    Headers[1] := TNameValuePair.Create('Authorization', 'Bearer ' + frmMain.SUPABASE_KEY);
    Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');
    Headers[3] := TNameValuePair.Create('Prefer', 'resolution=merge-duplicates'); // Upsert

    while not qryInfo.Eof do
    begin
      Application.ProcessMessages;
      sKodeKaryawan := qryInfo.FieldByName('kodekaryawan').AsString;
      manLogs.Lines.Add(Format('  -> Upserting HRD Info: %s (%s)', [sKodeKaryawan, qryInfo.FieldByName('namakaryawan').AsString]));

      // 1. Upsert to ot_hrd_karyawan_info
      JSONObj := SO();
      JSONObj.S['kode_outlet'] := frmMain.APP_OUTLETID;
      JSONObj.S['kodekaryawan'] := sKodeKaryawan;
      JSONObj.S['idkaryawan'] := qryInfo.FieldByName('idkaryawan').AsString;
      JSONObj.S['namakaryawan'] := qryInfo.FieldByName('namakaryawan').AsString;
      JSONObj.S['departemen'] := qryInfo.FieldByName('departemen').AsString;
      JSONObj.S['active'] := qryInfo.FieldByName('active').AsString;

      if not qryInfo.FieldByName('tglmasukkerja').IsNull then
        JSONObj.S['tglmasukkerja'] := FormatDateTime('yyyy-mm-dd', qryInfo.FieldByName('tglmasukkerja').AsDateTime)
      else
        JSONObj.Null['tglmasukkerja'] := jNull;

      if not qryInfo.FieldByName('tglhabiskontrak').IsNull then
        JSONObj.S['tglhabiskontrak'] := FormatDateTime('yyyy-mm-dd', qryInfo.FieldByName('tglhabiskontrak').AsDateTime)
      else
        JSONObj.Null['tglhabiskontrak'] := jNull;

      JSONObj.S['namabank'] := qryInfo.FieldByName('namabank').AsString;
      JSONObj.S['norek'] := qryInfo.FieldByName('norek').AsString;
      JSONObj.S['namarek'] := qryInfo.FieldByName('namarek').AsString;

      RequestBody := TStringStream.Create(JSONObj.AsJSON, TEncoding.UTF8);
      try
        Resp := HTTP.Post(BaseURL + 'ot_hrd_karyawan_info?on_conflict=kodekaryawan', RequestBody, nil, Headers);
        if (Resp.StatusCode = 200) or (Resp.StatusCode = 201) then
          Inc(SuccessCount)
        else
          manLogs.Lines.Add(Format('    [!] Error upserting ot_hrd_karyawan_info [%d]: %s', [Resp.StatusCode, Resp.ContentAsString]));
      finally
        RequestBody.Free;
      end;

      // 2. Sync corresponding Details from ben_hrd_karyawan_details
      qryDetails.Close;
      qryDetails.SQL.Text := 'SELECT * FROM ben_hrd_karyawan_details WHERE idkaryawan = :idk';
      qryDetails.ParamByName('idk').AsString := qryInfo.FieldByName('idkaryawan').AsString;
      qryDetails.Open;

      if not qryDetails.IsEmpty then
      begin
        Endpoint := BaseURL + 'ot_hrd_karyawan_details?kodekaryawan=eq.' + sKodeKaryawan;
        Resp := HTTP.Get(Endpoint, nil, [
          TNameValuePair.Create('apikey', frmMain.SUPABASE_KEY),
          TNameValuePair.Create('Authorization', 'Bearer ' + frmMain.SUPABASE_KEY),
          TNameValuePair.Create('Content-Type', 'application/json')
        ]);

        JSONObj := SO();
        JSONObj.S['kode_outlet'] := frmMain.APP_OUTLETID;
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
          JSONObj.S['tgllahir'] := FormatDateTime('yyyy-mm-dd', qryDetails.FieldByName('tgllahir').AsDateTime)
        else
          JSONObj.Null['tgllahir'] := jNull;

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
              Resp := HTTP.Post(BaseURL + 'ot_hrd_karyawan_details', RequestBody, nil, [
                TNameValuePair.Create('apikey', frmMain.SUPABASE_KEY),
                TNameValuePair.Create('Authorization', 'Bearer ' + frmMain.SUPABASE_KEY),
                TNameValuePair.Create('Content-Type', 'application/json')
              ]);
            end
            else
            begin
              Resp := HTTP.Patch(Endpoint, RequestBody, nil, [
                TNameValuePair.Create('apikey', frmMain.SUPABASE_KEY),
                TNameValuePair.Create('Authorization', 'Bearer ' + frmMain.SUPABASE_KEY),
                TNameValuePair.Create('Content-Type', 'application/json')
              ]);
            end;

            if (Resp.StatusCode <> 200) and (Resp.StatusCode <> 201) and (Resp.StatusCode <> 204) then
              manLogs.Lines.Add(Format('    [!] Error syncing ot_hrd_karyawan_details [%d]: %s', [Resp.StatusCode, Resp.ContentAsString]));
          end;
        finally
          RequestBody.Free;
        end;
      end;

      qryInfo.Next;
    end;

    manLogs.Lines.Add(Format('  [SUCCESS] HRD Info sync completed: %d/%d records successfully upserted.', [SuccessCount, TotalCount]));
  except
    on E: Exception do
      manLogs.Lines.Add('  [!] Exception during SyncManualHRDInfo: ' + E.Message);
  end;
  qryInfo.Free;
  qryDetails.Free;
  HTTP.Free;
end;

procedure TfrmManualSync.SyncManualMasterRoom;
var
  qryRuangan: TMyQuery;
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Headers: TNetHeaders;
  BulkRoom: ISuperArray;
  JSONRoom: ISuperObject;
  RequestBody: TStringStream;
  BaseURL, sKondisi, sStatus, sRoomID: String;
  TotalCount: Integer;
begin
  manLogs.Lines.Add('');
  manLogs.Lines.Add('--- [2/3] Syncing Master Room (ruangan -> ot_master_room) ---');

  BaseURL := GetBaseRESTUrl;
  if (BaseURL = '') or (frmMain.SUPABASE_KEY = '') then
  begin
    manLogs.Lines.Add('  [!] ERROR: Supabase URL or Key is not configured!');
    Exit;
  end;

  qryRuangan := TMyQuery.Create(Self);
  HTTP := THTTPClient.Create;
  try
    qryRuangan.Connection := dmDB.dbInternal;
    qryRuangan.SQL.Text := 'SELECT * FROM ruangan ORDER BY ruangan_id ASC';
    qryRuangan.Open;

    if qryRuangan.IsEmpty then
    begin
      manLogs.Lines.Add('  -> No room records found in ruangan table.');
      Exit;
    end;

    TotalCount := qryRuangan.RecordCount;
    manLogs.Lines.Add(Format('  -> Found %d rooms in local database.', [TotalCount]));

    SetLength(Headers, 4);
    Headers[0] := TNameValuePair.Create('apikey', frmMain.SUPABASE_KEY);
    Headers[1] := TNameValuePair.Create('Authorization', 'Bearer ' + frmMain.SUPABASE_KEY);
    Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');
    Headers[3] := TNameValuePair.Create('Prefer', 'resolution=merge-duplicates'); // Upsert on (kode_outlet, room_id)

    BulkRoom := SA();
    while not qryRuangan.Eof do
    begin
      Application.ProcessMessages;

      sRoomID := frmMain.APP_OUTLETID + '.' + qryRuangan.FieldByName('ruangan_id').AsString;
      sKondisi := UpperCase(Trim(qryRuangan.FieldByName('kondisi').AsString));
      sStatus := UpperCase(Trim(qryRuangan.FieldByName('status').AsString));

      JSONRoom := SO();
      JSONRoom.S['kode_outlet'] := frmMain.APP_OUTLETID;
      JSONRoom.S['room_id'] := sRoomID;
      JSONRoom.B['active'] := (sKondisi = 'Y');
      JSONRoom.S['jenis_jasa'] := qryRuangan.FieldByName('jenis_jasa').AsString;
      JSONRoom.S['room_gender'] := qryRuangan.FieldByName('notes').AsString;
      JSONRoom.B['available'] := (sStatus = 'AVAILABLE');
      JSONRoom.S['keterangan'] := 'floor ' + qryRuangan.FieldByName('lantai').AsString;
      JSONRoom.Null['fasilitas'] := jNull;
      JSONRoom.S['update_at'] := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', Now);
      JSONRoom.S['update_by'] := 'ManualSync';

      BulkRoom.Add(JSONRoom);
      manLogs.Lines.Add(Format('  -> Prepared room: %s (Active: %s, Avail: %s, Jasa: %s)', 
        [sRoomID, BoolToStr(JSONRoom.B['active'], True), BoolToStr(JSONRoom.B['available'], True), JSONRoom.S['jenis_jasa']]));

      qryRuangan.Next;
    end;

    if BulkRoom.Length > 0 then
    begin
      RequestBody := TStringStream.Create(BulkRoom.AsJSON, TEncoding.UTF8);
      try
        Resp := HTTP.Post(BaseURL + 'ot_master_room?on_conflict=kode_outlet,room_id', RequestBody, nil, Headers);
        if (Resp.StatusCode = 200) or (Resp.StatusCode = 201) then
          manLogs.Lines.Add(Format('  [SUCCESS] Master Room sync completed: %d rooms upserted.', [BulkRoom.Length]))
        else
          manLogs.Lines.Add(Format('  [!] Error upserting ot_master_room [%d]: %s', [Resp.StatusCode, Resp.ContentAsString]));
      finally
        RequestBody.Free;
      end;
    end;
  except
    on E: Exception do
      manLogs.Lines.Add('  [!] Exception during SyncManualMasterRoom: ' + E.Message);
  end;
  qryRuangan.Free;
  HTTP.Free;
end;

procedure TfrmManualSync.SyncManualGCItems;
var
  qryGC: TMyQuery;
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Headers: TNetHeaders;
  BulkGC: ISuperArray;
  JSONGC: ISuperObject;
  RequestBody: TStringStream;
  BaseURL, sGCNumber, sPack, sPakai, sPayBuy, sPayUsed, sOutBuy, sOutUsed: String;
  bUsed: Boolean;
  TotalCount, BatchCount, ProcessedTotal: Integer;
begin
  manLogs.Lines.Add('');
  manLogs.Lines.Add('--- [3/3] Syncing GC Items (gc_sold -> ot_pos_gc_transaction, Insert-Only) ---');

  BaseURL := GetBaseRESTUrl;
  if (BaseURL = '') or (frmMain.SUPABASE_KEY = '') then
  begin
    manLogs.Lines.Add('  [!] ERROR: Supabase URL or Key is not configured!');
    Exit;
  end;

  qryGC := TMyQuery.Create(Self);
  HTTP := THTTPClient.Create;
  try
    qryGC.Connection := dmDB.dbInternal;
    // Scalar subquery for pack_number guarantees no duplicate composite rows
    qryGC.SQL.Text := 
      'SELECT s.*, ' +
      '  (SELECT d.paket_number FROM gc_detail d WHERE d.gc_number = s.gc_number LIMIT 1) AS pack_number ' +
      'FROM gc_sold s ' +
      'WHERE s.gc_number IS NOT NULL AND s.gc_number <> '''' AND s.gc_number <> ''(NONE)'' ' +
      'ORDER BY s.autonum ASC';
    qryGC.Open;

    if qryGC.IsEmpty then
    begin
      manLogs.Lines.Add('  -> No valid sold Gift Certificates found in gc_sold.');
      Exit;
    end;

    TotalCount := qryGC.RecordCount;
    ProcessedTotal := 0;
    BatchCount := 0;
    manLogs.Lines.Add(Format('  -> Found %d Gift Certificate records to process.', [TotalCount]));

    SetLength(Headers, 4);
    Headers[0] := TNameValuePair.Create('apikey', frmMain.SUPABASE_KEY);
    Headers[1] := TNameValuePair.Create('Authorization', 'Bearer ' + frmMain.SUPABASE_KEY);
    Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');
    Headers[3] := TNameValuePair.Create('Prefer', 'resolution=ignore-duplicates'); // Insert-only: DO NOT UPDATE IF EXISTS

    BulkGC := SA();
    while not qryGC.Eof do
    begin
      Application.ProcessMessages;

      sGCNumber := Trim(qryGC.FieldByName('gc_number').AsString);
      sPack := Trim(qryGC.FieldByName('pack_number').AsString);
      sPakai := UpperCase(Trim(qryGC.FieldByName('pakai').AsString));
      bUsed := (sPakai = 'Y');

      JSONGC := SO();
      JSONGC.S['gc_number'] := sGCNumber;
      JSONGC.S['gc_barcode'] := sGCNumber;

      if (Trim(qryGC.FieldByName('notes').AsString) <> '') and (Trim(qryGC.FieldByName('notes').AsString) <> '(NONE)') then
        JSONGC.S['qrcode'] := Trim(qryGC.FieldByName('notes').AsString)
      else
        JSONGC.Null['qrcode'] := jNull;

      if (sPack <> '') and (sPack <> '(NONE)') then
        JSONGC.S['pack_number'] := sPack
      else
        JSONGC.Null['pack_number'] := jNull;

      JSONGC.S['nama_gc'] := qryGC.FieldByName('nama_menu').AsString;
      JSONGC.F['value'] := qryGC.FieldByName('harga_jasa').AsFloat;

      // buy_at timestamp
      if not qryGC.FieldByName('tgl_jual').IsNull and (FormatDateTime('yyyy', qryGC.FieldByName('tgl_jual').AsDateTime) <> '2000') then
        JSONGC.S['buy_at'] := FormatDateTime('yyyy-mm-dd"T"00:00:00"+07:00"', qryGC.FieldByName('tgl_jual').AsDateTime)
      else if not qryGC.FieldByName('tanggal').IsNull and (FormatDateTime('yyyy', qryGC.FieldByName('tanggal').AsDateTime) <> '2000') then
        JSONGC.S['buy_at'] := FormatDateTime('yyyy-mm-dd"T"00:00:00"+07:00"', qryGC.FieldByName('tanggal').AsDateTime)
      else
        JSONGC.Null['buy_at'] := jNull;

      // expired_date selalu 120 hari dari tanggal beli (tgl_jual / buy_at)
      if not qryGC.FieldByName('tgl_jual').IsNull and (FormatDateTime('yyyy', qryGC.FieldByName('tgl_jual').AsDateTime) <> '2000') then
        JSONGC.S['expired_date'] := FormatDateTime('yyyy-mm-dd', IncDay(qryGC.FieldByName('tgl_jual').AsDateTime, 120))
      else if not qryGC.FieldByName('tanggal').IsNull and (FormatDateTime('yyyy', qryGC.FieldByName('tanggal').AsDateTime) <> '2000') then
        JSONGC.S['expired_date'] := FormatDateTime('yyyy-mm-dd', IncDay(qryGC.FieldByName('tanggal').AsDateTime, 120))
      else
        JSONGC.Null['expired_date'] := jNull;

      JSONGC.B['is_active'] := (UpperCase(Trim(qryGC.FieldByName('aktif').AsString)) <> 'N');

      // has_used & used_at
      JSONGC.B['has_used'] := bUsed;
      if bUsed and not qryGC.FieldByName('tgl_pakai').IsNull and (FormatDateTime('yyyy', qryGC.FieldByName('tgl_pakai').AsDateTime) <> '2000') then
        JSONGC.S['used_at'] := FormatDateTime('yyyy-mm-dd"T"00:00:00"Z"', qryGC.FieldByName('tgl_pakai').AsDateTime)
      else
        JSONGC.Null['used_at'] := jNull;

      // id_payment_buy (sanitize '(NONE)' or empty to jNull to prevent FK violations)
      sPayBuy := Trim(qryGC.FieldByName('payment_jual').AsString);
      if (sPayBuy <> '') and (sPayBuy <> '(NONE)') then
        JSONGC.S['id_payment_buy'] := sPayBuy
      else
        JSONGC.Null['id_payment_buy'] := jNull;

      // id_payment_used
      sPayUsed := Trim(qryGC.FieldByName('payment_pakai').AsString);
      if bUsed and (sPayUsed <> '') and (sPayUsed <> '(NONE)') then
        JSONGC.S['id_payment_used'] := sPayUsed
      else
        JSONGC.Null['id_payment_used'] := jNull;

      // kode_outlet_buy
      sOutBuy := Trim(qryGC.FieldByName('outlet_jual').AsString);
      if (sOutBuy <> '') and (sOutBuy <> '(NONE)') then
        JSONGC.S['kode_outlet_buy'] := sOutBuy
      else
        JSONGC.S['kode_outlet_buy'] := frmMain.APP_OUTLETID;

      // kode_outlet_used
      sOutUsed := Trim(qryGC.FieldByName('outlet_pakai').AsString);
      if bUsed and (sOutUsed <> '') and (sOutUsed <> '(NONE)') then
        JSONGC.S['kode_outlet_used'] := sOutUsed
      else
        JSONGC.Null['kode_outlet_used'] := jNull;

      BulkGC.Add(JSONGC);

      // Stream in batches of 50 records to prevent HTTP timeout
      if BulkGC.Length >= 50 then
      begin
        Inc(BatchCount);
        RequestBody := TStringStream.Create(BulkGC.AsJSON, TEncoding.UTF8);
        try
          Resp := HTTP.Post(BaseURL + 'ot_pos_gc_transaction?on_conflict=gc_number', RequestBody, nil, Headers);
          if (Resp.StatusCode = 200) or (Resp.StatusCode = 201) then
          begin
            ProcessedTotal := ProcessedTotal + BulkGC.Length;
            manLogs.Lines.Add(Format('  -> Batch %d: Processed %d GCs (Total: %d/%d)...', [BatchCount, BulkGC.Length, ProcessedTotal, TotalCount]));
          end
          else
            manLogs.Lines.Add(Format('  [!] Error in GC batch %d [%d]: %s', [BatchCount, Resp.StatusCode, Resp.ContentAsString]));
        finally
          RequestBody.Free;
        end;
        BulkGC := SA();
      end;

      qryGC.Next;
    end;

    // Flush any remaining records in final batch
    if BulkGC.Length > 0 then
    begin
      Inc(BatchCount);
      RequestBody := TStringStream.Create(BulkGC.AsJSON, TEncoding.UTF8);
      try
        Resp := HTTP.Post(BaseURL + 'ot_pos_gc_transaction?on_conflict=gc_number', RequestBody, nil, Headers);
        if (Resp.StatusCode = 200) or (Resp.StatusCode = 201) then
        begin
          ProcessedTotal := ProcessedTotal + BulkGC.Length;
          manLogs.Lines.Add(Format('  -> Final Batch %d: Processed %d GCs (Total: %d/%d)...', [BatchCount, BulkGC.Length, ProcessedTotal, TotalCount]));
        end
        else
          manLogs.Lines.Add(Format('  [!] Error in final GC batch [%d]: %s', [Resp.StatusCode, Resp.ContentAsString]));
      finally
        RequestBody.Free;
      end;
    end;

    manLogs.Lines.Add(Format('  [SUCCESS] GC Items sync completed: %d total records submitted with ignore-duplicates policy.', [ProcessedTotal]));
  except
    on E: Exception do
      manLogs.Lines.Add('  [!] Exception during SyncManualGCItems: ' + E.Message);
  end;
  qryGC.Free;
  HTTP.Free;
end;

procedure TfrmManualSync.SyncManualPayroll;
var
  qryPayroll: TMyQuery;
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Headers: TNetHeaders;
  JSONObj, JSONData: ISuperObject;
  BulkPayroll: ISuperArray;
  RequestBody: TStringStream;
  BaseURL, sKodeKaryawan, FN: String;
  TotalCount, ProcessedTotal, BatchCount, I: Integer;
begin
  manLogs.Lines.Add('');
  manLogs.Lines.Add('--- [4/4] Syncing Payroll Details (Full Table: ben_payroll_details -> ot_hrd_karyawan_payroll_details) ---');

  BaseURL := GetBaseRESTUrl;
  if (BaseURL = '') or (frmMain.SUPABASE_KEY = '') then
  begin
    manLogs.Lines.Add('  [!] ERROR: Supabase URL or Key is not configured!');
    Exit;
  end;

  qryPayroll := TMyQuery.Create(Self);
  HTTP := THTTPClient.Create;
  HTTP.ConnectionTimeout := 10000;
  HTTP.ResponseTimeout := 30000;
  try
    qryPayroll.Connection := dmDB.dbInternal;
    // Full sync of all records in ben_payroll_details
    qryPayroll.SQL.Text := 'SELECT * FROM ben_payroll_details ORDER BY autonum ASC';
    qryPayroll.Open;

    if qryPayroll.IsEmpty then
    begin
      manLogs.Lines.Add('  -> No payroll records found in ben_payroll_details.');
      Exit;
    end;

    TotalCount := qryPayroll.RecordCount;
    ProcessedTotal := 0;
    BatchCount := 0;
    manLogs.Lines.Add(Format('  -> Found %d payroll records in local database.', [TotalCount]));

    SetLength(Headers, 4);
    Headers[0] := TNameValuePair.Create('apikey', frmMain.SUPABASE_KEY);
    Headers[1] := TNameValuePair.Create('Authorization', 'Bearer ' + frmMain.SUPABASE_KEY);
    Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');
    Headers[3] := TNameValuePair.Create('Prefer', 'resolution=merge-duplicates'); // Upsert on (kode_outlet, local_autonum)

    BulkPayroll := SA();
    while not qryPayroll.Eof do
    begin
      Application.ProcessMessages;

      sKodeKaryawan := qryPayroll.FieldByName('kodekaryawan').AsString;

      JSONObj := SO();
      JSONObj.S['kode_outlet'] := frmMain.APP_OUTLETID;
      JSONObj.I['local_autonum'] := qryPayroll.FieldByName('autonum').AsInteger;
      JSONObj.S['kodekaryawan'] := sKodeKaryawan;

      // Root level nilaithp for fast dashboard querying
      if not qryPayroll.FieldByName('nilaithp').IsNull then
        JSONObj.S['nilaithp'] := StringReplace(FloatToStr(qryPayroll.FieldByName('nilaithp').AsFloat), ',', '.', [rfReplaceAll])
      else
        JSONObj.Null['nilaithp'] := jNull;

      // Root level payrollperiode for fast period filtering
      if not qryPayroll.FieldByName('payrollperiode').IsNull then
        JSONObj.S['payrollperiode'] := qryPayroll.FieldByName('payrollperiode').AsString
      else
        JSONObj.Null['payrollperiode'] := jNull;

      // Create the nested JSON for all dynamic payroll metrics
      JSONData := SO();
      for I := 0 to qryPayroll.FieldCount - 1 do
      begin
        FN := LowerCase(qryPayroll.Fields[I].FieldName);
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

      JSONObj.O['payroll_data'] := JSONData;
      BulkPayroll.Add(JSONObj);

      // Stream in batches of 50 records to prevent HTTP timeout
      if BulkPayroll.Length >= 50 then
      begin
        Inc(BatchCount);
        RequestBody := TStringStream.Create(BulkPayroll.AsJSON, TEncoding.UTF8);
        try
          Resp := HTTP.Post(BaseURL + 'ot_hrd_karyawan_payroll_details?on_conflict=kode_outlet,local_autonum', RequestBody, nil, Headers);
          if (Resp.StatusCode = 200) or (Resp.StatusCode = 201) then
          begin
            ProcessedTotal := ProcessedTotal + BulkPayroll.Length;
            manLogs.Lines.Add(Format('  -> Batch %d: Processed %d payroll records (Total: %d/%d)...', [BatchCount, BulkPayroll.Length, ProcessedTotal, TotalCount]));
          end
          else
            manLogs.Lines.Add(Format('  [!] Error in Payroll batch %d [%d]: %s', [BatchCount, Resp.StatusCode, Resp.ContentAsString]));
        finally
          RequestBody.Free;
        end;
        BulkPayroll := SA();
      end;

      qryPayroll.Next;
    end;

    // Flush any remaining records in final batch
    if BulkPayroll.Length > 0 then
    begin
      Inc(BatchCount);
      RequestBody := TStringStream.Create(BulkPayroll.AsJSON, TEncoding.UTF8);
      try
        Resp := HTTP.Post(BaseURL + 'ot_hrd_karyawan_payroll_details?on_conflict=kode_outlet,local_autonum', RequestBody, nil, Headers);
        if (Resp.StatusCode = 200) or (Resp.StatusCode = 201) then
        begin
          ProcessedTotal := ProcessedTotal + BulkPayroll.Length;
          manLogs.Lines.Add(Format('  -> Final Batch %d: Processed %d payroll records (Total: %d/%d)...', [BatchCount, BulkPayroll.Length, ProcessedTotal, TotalCount]));
        end
        else
          manLogs.Lines.Add(Format('  [!] Error in final Payroll batch [%d]: %s', [Resp.StatusCode, Resp.ContentAsString]));
      finally
        RequestBody.Free;
      end;
    end;

    manLogs.Lines.Add(Format('  [SUCCESS] Payroll sync completed: %d total records submitted with merge-duplicates policy.', [ProcessedTotal]));
  except
    on E: Exception do
      manLogs.Lines.Add('  [!] Exception during SyncManualPayroll: ' + E.Message);
  end;
  qryPayroll.Free;
  HTTP.Free;
end;

end.
