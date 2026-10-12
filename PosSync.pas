procedure TfrmMain.SyncPosTransPayment(const LastSyncStr, TargetSyncStr: String);
var
  qryLocal, qrySearchLocal: TMyQuery;
  HTTP: THTTPClient;
  JSONPayload, JSONMember, UpdatePayload: ISuperObject;
  BulkPayment, BulkMember: ISuperArray;
  Response: IHTTPResponse;
  RecCount: Integer;
  TransIDList: TStringList;
  Headers, HeadersReturnMinimal: TNetHeaders;
  RequestBody, RequestBodyInner: TStringStream;
begin
  qryLocal := TMyQuery.Create(nil);
  qrySearchLocal := TMyQuery.Create(nil);
  HTTP := THTTPClient.Create;
  TransIDList := TStringList.Create;
  try
    qrySearchLocal.Connection := DMDB.dbInternal;
    
    qryLocal.Connection := DMDB.dbInternal;
    qryLocal.SQL.Text := 'SELECT * FROM trans_payment WHERE notes > :LastSync AND notes <= :TargetSync ORDER BY notes ASC';
    qryLocal.ParamByName('LastSync').AsString := LastSyncStr;
    qryLocal.ParamByName('TargetSync').AsString := TargetSyncStr;
    qryLocal.Open;
    
    if qryLocal.IsEmpty then Exit;
    
    SetLength(Headers, 4);
    Headers[0] := TNameValuePair.Create('apikey', SUPABASE_KEY);
    Headers[1] := TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY);
    Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');
    Headers[3] := TNameValuePair.Create('Prefer', 'resolution=merge-duplicates');
    
    SetLength(HeadersReturnMinimal, 4);
    HeadersReturnMinimal[0] := TNameValuePair.Create('apikey', SUPABASE_KEY);
    HeadersReturnMinimal[1] := TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY);
    HeadersReturnMinimal[2] := TNameValuePair.Create('Content-Type', 'application/json');
    HeadersReturnMinimal[3] := TNameValuePair.Create('Prefer', 'return=minimal');

    RecCount := 0;
    BulkPayment := SA();
    BulkMember := SA();
    
    while not qryLocal.Eof do
    begin
      Application.ProcessMessages;
      
      JSONPayload := SO();
      JSONPayload.S['id_payment'] := qryLocal.FieldByName('id_payment').AsString;
      JSONPayload.S['kode_outlet'] := APP_OUTLETID;
      if qryLocal.FieldByName('id_member').AsString <> '' then
        JSONPayload.S['user_uid'] := qryLocal.FieldByName('id_member').AsString
      else
        JSONPayload.S['user_uid'] := ''; 

      JSONPayload.F['subtotal'] := qryLocal.FieldByName('subtotal').AsFloat;
      JSONPayload.F['disc_percent'] := qryLocal.FieldByName('disc_percent').AsFloat;
      JSONPayload.F['disc_amount'] := qryLocal.FieldByName('disc_amount').AsFloat;
      JSONPayload.F['total'] := qryLocal.FieldByName('total').AsFloat;
      JSONPayload.S['rcpt'] := qryLocal.FieldByName('staff_id').AsString;
      JSONPayload.S['payment_method'] := qryLocal.FieldByName('payment_via').AsString;
      
      BulkPayment.Add(JSONPayload);
      
      if (qryLocal.FieldByName('id_member').AsString <> '') and 
         (qryLocal.FieldByName('id_member').AsString <> '(NONE)') then
      begin
        JSONMember := SO();
        JSONMember.S['id_payment'] := qryLocal.FieldByName('id_payment').AsString;
        JSONMember.S['user_uid'] := qryLocal.FieldByName('id_member').AsString;
        JSONMember.F['point_awal'] := qryLocal.FieldByName('point_awal').AsFloat;
        JSONMember.F['tambah_point'] := qryLocal.FieldByName('tambah_point').AsFloat;
        JSONMember.F['kurang_point'] := qryLocal.FieldByName('kurang_point').AsFloat;
        JSONMember.F['sisa_point'] := qryLocal.FieldByName('sisa').AsFloat;
        BulkMember.Add(JSONMember);
      end;

      qrySearchLocal.Close;
      qrySearchLocal.SQL.Text := 'SELECT trans_id FROM trans_master WHERE id_payment = :idpay';
      qrySearchLocal.ParamByName('idpay').AsString := qryLocal.FieldByName('id_payment').AsString;
      qrySearchLocal.Open;
      
      TransIDList.Clear;
      while not qrySearchLocal.Eof do
      begin
        TransIDList.Add('"' + qrySearchLocal.FieldByName('trans_id').AsString + '"');
        qrySearchLocal.Next;
      end;
      
      if TransIDList.Count > 0 then
      begin
        UpdatePayload := SO();
        UpdatePayload.S['id_payment'] := qryLocal.FieldByName('id_payment').AsString;
        
        RequestBodyInner := TStringStream.Create(UpdatePayload.AsJSON, TEncoding.UTF8);
        try
          HTTP.Patch(SUPABASE_URL + 'ot_pos_trans_master?trans_id=in.(' + TransIDList.CommaText + ')', 
            RequestBodyInner, nil, HeadersReturnMinimal);
        finally
          RequestBodyInner.Free;
        end;
          
        RequestBodyInner := TStringStream.Create(UpdatePayload.AsJSON, TEncoding.UTF8);
        try
          HTTP.Patch(SUPABASE_URL + 'ot_pos_trans_detail?trans_id=in.(' + TransIDList.CommaText + ')', 
            RequestBodyInner, nil, HeadersReturnMinimal);
        finally
          RequestBodyInner.Free;
        end;
      end;
      
      Inc(RecCount);
      qryLocal.Next;
    end;
    
    if BulkPayment.Length > 0 then
    begin
      RequestBody := TStringStream.Create(BulkPayment.AsJSON, TEncoding.UTF8);
      try
        Response := HTTP.Post(SUPABASE_URL + 'ot_pos_trans_payment?on_conflict=id_payment', RequestBody, nil, Headers);
        if (Response.StatusCode <> 200) and (Response.StatusCode <> 201) then
          memLogs.Lines.Add('[!] Bulk Payment Upsert Error: ' + Response.ContentAsString);
      finally
        RequestBody.Free;
      end;
    end;
    
    if BulkMember.Length > 0 then
    begin
      RequestBody := TStringStream.Create(BulkMember.AsJSON, TEncoding.UTF8);
      try
        Response := HTTP.Post(SUPABASE_URL + 'pos_trans_point_member?on_conflict=id_payment', RequestBody, nil, Headers);
        if (Response.StatusCode <> 200) and (Response.StatusCode <> 201) then
          memLogs.Lines.Add('[!] Bulk Member Point Upsert Error: ' + Response.ContentAsString);
      finally
        RequestBody.Free;
      end;
    end;
    
    if RecCount > 0 then memLogs.Lines.Add('Synced ' + IntToStr(RecCount) + ' Payments (Bulk).');
  finally
    qryLocal.Free;
    qrySearchLocal.Free;
    HTTP.Free;
    TransIDList.Free;
  end;
end;

procedure TfrmMain.SyncPosTransPaymentDetails(const LastSyncStr, TargetSyncStr: String);
var
  qryLocal: TMyQuery;
  HTTP: THTTPClient;
  JSONPayload, JSONGC: ISuperObject;
  BulkPaymentDetails: ISuperArray;
  Response, GCResponse: IHTTPResponse;
  RecCount: Integer;
  Headers, HeadersReturnMinimal: TNetHeaders;
  RequestBody, RequestBodyInner: TStringStream;
begin
  qryLocal := TMyQuery.Create(nil);
  HTTP := THTTPClient.Create;
  try
    qryLocal.Connection := DMDB.dbInternal;
    qryLocal.SQL.Text := 
      'SELECT pd.*, p.namapromo, mp1.namapayment as payment1_name, mp2.namapayment as payment2_name, ' +
      'b1.namabank as bank1_name, b2.namabank as bank2_name, tp.id_member ' +
      'FROM trans_payment_detail pd ' +
      'LEFT JOIN pos_master_promo p ON pd.kodepromo = p.kodepromo ' +
      'LEFT JOIN pos_master_payment mp1 ON pd.kodepayment1 = mp1.kodepayment ' +
      'LEFT JOIN pos_master_payment mp2 ON pd.kodepayment2 = mp2.kodepayment ' +
      'LEFT JOIN ben_master_bank b1 ON pd.kodebank1 = b1.kodebank ' +
      'LEFT JOIN ben_master_bank b2 ON pd.kodebank2 = b2.kodebank ' +
      'LEFT JOIN trans_payment tp ON pd.id_payment = tp.id_payment ' +
      'WHERE pd.lasteditdate > :LastSync AND pd.lasteditdate <= :TargetSync ORDER BY pd.lasteditdate ASC';
    qryLocal.ParamByName('LastSync').AsString := LastSyncStr;
    qryLocal.ParamByName('TargetSync').AsString := TargetSyncStr;
    qryLocal.Open;
    
    if qryLocal.IsEmpty then Exit;
    
    SetLength(Headers, 4);
    Headers[0] := TNameValuePair.Create('apikey', SUPABASE_KEY);
    Headers[1] := TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY);
    Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');
    Headers[3] := TNameValuePair.Create('Prefer', 'resolution=merge-duplicates');
    
    SetLength(HeadersReturnMinimal, 4);
    HeadersReturnMinimal[0] := TNameValuePair.Create('apikey', SUPABASE_KEY);
    HeadersReturnMinimal[1] := TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY);
    HeadersReturnMinimal[2] := TNameValuePair.Create('Content-Type', 'application/json');
    HeadersReturnMinimal[3] := TNameValuePair.Create('Prefer', 'return=minimal');
    
    RecCount := 0;
    BulkPaymentDetails := SA();
    
    while not qryLocal.Eof do
    begin
      Application.ProcessMessages;
      JSONPayload := SO();
      JSONPayload.S['id_payment'] := qryLocal.FieldByName('id_payment').AsString;
      JSONPayload.S['kode_outlet'] := APP_OUTLETID;
      
      JSONPayload.S['namapromo'] := qryLocal.FieldByName('namapromo').AsString;
      JSONPayload.S['refpromo'] := qryLocal.FieldByName('refpromo').AsString;
      JSONPayload.F['vpromo'] := qryLocal.FieldByName('vpromo').AsFloat;
      JSONPayload.S['refdisc'] := qryLocal.FieldByName('refdisc').AsString;
      JSONPayload.F['vdisc'] := qryLocal.FieldByName('vdisc').AsFloat;
      JSONPayload.F['total'] := qryLocal.FieldByName('total').AsFloat;
      JSONPayload.F['vredeem'] := qryLocal.FieldByName('vredeem').AsFloat;
      JSONPayload.S['refgift'] := qryLocal.FieldByName('refgift').AsString;
      JSONPayload.F['vgift'] := qryLocal.FieldByName('vgift').AsFloat;
      JSONPayload.F['vcash'] := qryLocal.FieldByName('vcash').AsFloat - qryLocal.FieldByName('exchange').AsFloat;
      
      JSONPayload.S['payment1'] := qryLocal.FieldByName('payment1_name').AsString;
      JSONPayload.S['bank1'] := qryLocal.FieldByName('bank1_name').AsString;
      JSONPayload.S['refpayment1'] := qryLocal.FieldByName('refpayment1').AsString;
      JSONPayload.F['vpayment1'] := qryLocal.FieldByName('vpayment1').AsFloat;
      
      JSONPayload.S['payment2'] := qryLocal.FieldByName('payment2_name').AsString;
      JSONPayload.S['bank2'] := qryLocal.FieldByName('bank2_name').AsString;
      JSONPayload.S['refpayment2'] := qryLocal.FieldByName('refpayment2').AsString;
      JSONPayload.F['vpayment2'] := qryLocal.FieldByName('vpayment2').AsFloat;
      JSONPayload.S['rcpt'] := qryLocal.FieldByName('lastuser').AsString;

      BulkPaymentDetails.Add(JSONPayload);
      
      if (qryLocal.FieldByName('refgift').AsString <> '') and (qryLocal.FieldByName('refgift').AsString <> '(NONE)') then
      begin
        GCResponse := HTTP.Get(SUPABASE_URL + 'ot_pos_gc_transaction?gc_number=eq.' + qryLocal.FieldByName('refgift').AsString, nil, Headers);
        
        if (GCResponse.StatusCode = 200) and (GCResponse.ContentAsString <> '[]') then
        begin
          JSONGC := SO();
          JSONGC.S['used_at'] := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
          JSONGC.S['id_payment_used'] := qryLocal.FieldByName('id_payment').AsString;
          JSONGC.S['kode_outlet_used'] := APP_OUTLETID;
          JSONGC.B['has_used'] := True;
          
          RequestBodyInner := TStringStream.Create(JSONGC.AsJSON, TEncoding.UTF8);
          try
            HTTP.Patch(SUPABASE_URL + 'ot_pos_gc_transaction?gc_number=eq.' + qryLocal.FieldByName('refgift').AsString, 
              RequestBodyInner, nil, HeadersReturnMinimal);
          finally
            RequestBodyInner.Free;
          end;
        end
        else
        begin
          JSONGC := SO();
          JSONGC.S['user_uid'] := qryLocal.FieldByName('id_member').AsString;
          JSONGC.S['gc_number'] := qryLocal.FieldByName('refgift').AsString;
          JSONGC.S['gc_barcode'] := qryLocal.FieldByName('refgift').AsString;
          JSONGC.S['pack_number'] := qryLocal.FieldByName('refgift').AsString;
          JSONGC.S['nama_gc'] := 'AUTO INSERT ' + qryLocal.FieldByName('refgift').AsString + ' ' + FloatToStr(qryLocal.FieldByName('vgift').AsFloat);
          JSONGC.F['value'] := qryLocal.FieldByName('vgift').AsFloat;
          JSONGC.S['buy_at'] := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
          JSONGC.S['used_at'] := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
          JSONGC.B['has_used'] := True;
          JSONGC.S['id_payment_buy'] := qryLocal.FieldByName('id_payment').AsString;
          JSONGC.S['id_payment_used'] := qryLocal.FieldByName('id_payment').AsString;
          JSONGC.S['kode_outlet_buy'] := APP_OUTLETID;
          JSONGC.S['kode_outlet_used'] := APP_OUTLETID;
          
          RequestBodyInner := TStringStream.Create(JSONGC.AsJSON, TEncoding.UTF8);
          try
            HTTP.Post(SUPABASE_URL + 'ot_pos_gc_transaction?on_conflict=gc_number', 
              RequestBodyInner, nil, Headers);
          finally
            RequestBodyInner.Free;
          end;
        end;
      end;
        
      Inc(RecCount);
      qryLocal.Next;
    end;
    
    if BulkPaymentDetails.Length > 0 then
    begin
      RequestBody := TStringStream.Create(BulkPaymentDetails.AsJSON, TEncoding.UTF8);
      try
        Response := HTTP.Post(SUPABASE_URL + 'ot_pos_trans_payment_details?on_conflict=id_payment', RequestBody, nil, Headers);
        if (Response.StatusCode <> 200) and (Response.StatusCode <> 201) then
          memLogs.Lines.Add('[!] Payment Details Bulk Upsert Error: ' + Response.ContentAsString);
      finally
        RequestBody.Free;
      end;
    end;
    
    if RecCount > 0 then memLogs.Lines.Add('Synced ' + IntToStr(RecCount) + ' Payment Details (Bulk).');
  finally
    qryLocal.Free;
    HTTP.Free;
  end;
end;

procedure TfrmMain.SyncPosTransMaster(const LastSyncStr, TargetSyncStr: String);
var
  qryLocal: TMyQuery;
  HTTP: THTTPClient;
  JSONPayload, JSONMemo: ISuperObject;
  BulkMaster: ISuperArray;
  Response: IHTTPResponse;
  RecCount: Integer;
  Headers: TNetHeaders;
  RequestBody: TStringStream;
begin
  qryLocal := TMyQuery.Create(nil);
  HTTP := THTTPClient.Create;
  try
    qryLocal.Connection := DMDB.dbInternal;
    qryLocal.SQL.Text := 
      'SELECT tm.*, (SELECT k.kodekaryawan FROM ben_hrd_karyawan_info k WHERE k.idkaryawan = tm.therapist_id AND k.active = ''Y'' LIMIT 1) as kodekaryawan ' +
      'FROM trans_master tm ' +
      'WHERE CONCAT(tm.tanggal, '' '', tm.start_time) > :LastSync AND CONCAT(tm.tanggal, '' '', tm.start_time) <= :TargetSync ORDER BY tm.tanggal ASC, tm.start_time ASC';
    qryLocal.ParamByName('LastSync').AsString := LastSyncStr;
    qryLocal.ParamByName('TargetSync').AsString := TargetSyncStr;
    qryLocal.Open;
    
    if qryLocal.IsEmpty then Exit;

    SetLength(Headers, 4);
    Headers[0] := TNameValuePair.Create('apikey', SUPABASE_KEY);
    Headers[1] := TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY);
    Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');
    Headers[3] := TNameValuePair.Create('Prefer', 'resolution=merge-duplicates');
    
    RecCount := 0;
    BulkMaster := SA();
    
    while not qryLocal.Eof do
    begin
      Application.ProcessMessages;
      JSONPayload := SO();
      JSONPayload.S['trans_id'] := qryLocal.FieldByName('trans_id').AsString;
      JSONPayload.S['kode_outlet'] := APP_OUTLETID;
      JSONPayload.S['start_time'] := qryLocal.FieldByName('start_time').AsString;
      JSONPayload.S['end_time'] := qryLocal.FieldByName('end_time').AsString;
      JSONPayload.S['tanggal'] := FormatDateTime('yyyy-mm-dd', qryLocal.FieldByName('tanggal').AsDateTime);
      JSONPayload.S['status_trans'] := qryLocal.FieldByName('status_trans').AsString;
      JSONPayload.S['nama_customer'] := qryLocal.FieldByName('nama_customer').AsString;
      JSONPayload.S['room_id'] := APP_OUTLETID + '.' + qryLocal.FieldByName('room_id').AsString;
      JSONPayload.F['subtotal'] := qryLocal.FieldByName('subtotal').AsFloat;
      
      if qryLocal.FieldByName('kodekaryawan').AsString <> '' then
        JSONPayload.S['kodekaryawan'] := qryLocal.FieldByName('kodekaryawan').AsString
      else
        JSONPayload.O['kodekaryawan'] := nil;
      
      if qryLocal.FieldByName('notes').AsString <> '' then
      begin
        try
          JSONMemo := SO(qryLocal.FieldByName('notes').AsString);
          if Assigned(JSONMemo) then
          begin
            JSONPayload.S['byrequest'] := JSONMemo.S['byrequest'];
            JSONPayload.S['typejasa'] := JSONMemo.S['typejasa'];
            JSONPayload.S['rcpt'] := JSONMemo.S['user'];
          end;
        except
        end;
      end;
      
      if (qryLocal.FieldByName('id_payment').AsString <> '') and (qryLocal.FieldByName('id_payment').AsString <> '(NONE)') then
        JSONPayload.S['id_payment'] := qryLocal.FieldByName('id_payment').AsString;

      BulkMaster.Add(JSONPayload);
        
      Inc(RecCount);
      qryLocal.Next;
    end;
    
    if BulkMaster.Length > 0 then
    begin
      RequestBody := TStringStream.Create(BulkMaster.AsJSON, TEncoding.UTF8);
      try
        Response := HTTP.Post(SUPABASE_URL + 'ot_pos_trans_master?on_conflict=trans_id', RequestBody, nil, Headers);
        if (Response.StatusCode <> 200) and (Response.StatusCode <> 201) then
          memLogs.Lines.Add('[!] Trans Master Bulk Upsert Error: ' + Response.ContentAsString);
      finally
        RequestBody.Free;
      end;
    end;
    
    if RecCount > 0 then memLogs.Lines.Add('Synced ' + IntToStr(RecCount) + ' Master Trans (Bulk).');
  finally
    qryLocal.Free;
    HTTP.Free;
  end;
end;

procedure TfrmMain.SyncPosTransDetail(const LastSyncStr, TargetSyncStr: String);
var
  qryLocal: TMyQuery;
  HTTP: THTTPClient;
  JSONPayload: ISuperObject;
  BulkDetail: ISuperArray;
  Response: IHTTPResponse;
  RecCount: Integer;
  Headers: TNetHeaders;
  RequestBody: TStringStream;
begin
  qryLocal := TMyQuery.Create(nil);
  HTTP := THTTPClient.Create;
  try
    qryLocal.Connection := DMDB.dbInternal;
    qryLocal.SQL.Text := 
      'SELECT td.*, (SELECT k.kodekaryawan FROM ben_hrd_karyawan_info k WHERE k.idkaryawan = td.teraphist_id AND k.active = ''Y'' LIMIT 1) as kodekaryawan ' +
      'FROM trans_detail td ' +
      'WHERE CONCAT(td.tanggal, '' '', td.start_time) > :LastSync AND CONCAT(td.tanggal, '' '', td.start_time) <= :TargetSync ORDER BY td.tanggal ASC, td.start_time ASC';
    qryLocal.ParamByName('LastSync').AsString := LastSyncStr;
    qryLocal.ParamByName('TargetSync').AsString := TargetSyncStr;
    qryLocal.Open;
    
    if qryLocal.IsEmpty then Exit;
    
    SetLength(Headers, 4);
    Headers[0] := TNameValuePair.Create('apikey', SUPABASE_KEY);
    Headers[1] := TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY);
    Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');
    Headers[3] := TNameValuePair.Create('Prefer', 'resolution=merge-duplicates');
    
    RecCount := 0;
    BulkDetail := SA();
    
    while not qryLocal.Eof do
    begin
      Application.ProcessMessages;
      JSONPayload := SO();
      JSONPayload.S['trans_id'] := qryLocal.FieldByName('id_trans').AsString;
      JSONPayload.S['kode_outlet'] := APP_OUTLETID;
      JSONPayload.S['tanggal'] := FormatDateTime('yyyy-mm-dd', qryLocal.FieldByName('tanggal').AsDateTime);
      JSONPayload.S['trans_type_id'] := qryLocal.FieldByName('trans_type_id').AsString;
      JSONPayload.S['produk_jasa_id'] := qryLocal.FieldByName('produk_jasa_id').AsString;
      JSONPayload.S['produk_jasa_nama'] := qryLocal.FieldByName('produk_jasa_nama').AsString;
      JSONPayload.F['disc_amount'] := qryLocal.FieldByName('disc_amount').AsFloat;
      JSONPayload.F['disc_percent'] := qryLocal.FieldByName('disc_percent').AsFloat;
      JSONPayload.F['subtotal'] := qryLocal.FieldByName('subtotal').AsFloat;
      JSONPayload.F['price'] := qryLocal.FieldByName('harga').AsFloat;
      JSONPayload.F['qty'] := qryLocal.FieldByName('quantity').AsFloat;
      JSONPayload.S['therapist_id'] := qryLocal.FieldByName('teraphist_id').AsString;
      JSONPayload.S['room_id'] := APP_OUTLETID + '.' + qryLocal.FieldByName('room_id').AsString;
      JSONPayload.S['aroma_oil'] := qryLocal.FieldByName('aroma').AsString;
      JSONPayload.I['lama'] := qryLocal.FieldByName('lama').AsInteger;
      JSONPayload.I['local_autonum'] := qryLocal.FieldByName('autonum').AsInteger;
      
      if qryLocal.FieldByName('kodekaryawan').AsString <> '' then
        JSONPayload.S['kode_karyawan'] := qryLocal.FieldByName('kodekaryawan').AsString
      else
        JSONPayload.O['kode_karyawan'] := nil;
      
      if (qryLocal.FieldByName('payment_id').AsString <> '') and (qryLocal.FieldByName('payment_id').AsString <> '(NONE)') then
        JSONPayload.S['id_payment'] := qryLocal.FieldByName('payment_id').AsString;
        
      if (qryLocal.FieldByName('id_customer').AsString <> '') and (qryLocal.FieldByName('id_customer').AsString <> '(NONE)') then
        JSONPayload.S['user_uid'] := qryLocal.FieldByName('id_customer').AsString;

      BulkDetail.Add(JSONPayload);
        
      Inc(RecCount);
      qryLocal.Next;
    end;
    
    if BulkDetail.Length > 0 then
    begin
      RequestBody := TStringStream.Create(BulkDetail.AsJSON, TEncoding.UTF8);
      try
        Response := HTTP.Post(SUPABASE_URL + 'ot_pos_trans_detail?on_conflict=kode_outlet,local_autonum', RequestBody, nil, Headers);
        if (Response.StatusCode <> 200) and (Response.StatusCode <> 201) then
          memLogs.Lines.Add('[!] Trans Detail Bulk Upsert Error: ' + Response.ContentAsString);
      finally
        RequestBody.Free;
      end;
    end;
    
    if RecCount > 0 then memLogs.Lines.Add('Synced ' + IntToStr(RecCount) + ' Detail Trans (Bulk).');
  finally
    qryLocal.Free;
    HTTP.Free;
  end;
end;

procedure TfrmMain.SyncPosTransReject(const LastSyncStr, TargetSyncStr: String);
var
  qryLocal: TMyQuery;
  HTTP: THTTPClient;
  JSONPayload: ISuperObject;
  BulkReject: ISuperArray;
  Response: IHTTPResponse;
  RecCount: Integer;
  Headers: TNetHeaders;
  RequestBody: TStringStream;
  sRejectDate: String;
begin
  qryLocal := TMyQuery.Create(nil);
  HTTP := THTTPClient.Create;
  try
    qryLocal.Connection := DMDB.dbInternal;
    qryLocal.SQL.Text := 'SELECT autonum, tanggal, waktu, jenis_jasa, keterangan, lasteditdate ' +
                         'FROM trans_reject ' +
                         'WHERE lasteditdate > :LastSync AND lasteditdate <= :TargetSync ' +
                         'ORDER BY lasteditdate ASC';
    qryLocal.ParamByName('LastSync').AsString := LastSyncStr;
    qryLocal.ParamByName('TargetSync').AsString := TargetSyncStr;
    qryLocal.Open;
    
    if qryLocal.IsEmpty then Exit;
    
    SetLength(Headers, 4);
    Headers[0] := TNameValuePair.Create('apikey', SUPABASE_KEY);
    Headers[1] := TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY);
    Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');
    Headers[3] := TNameValuePair.Create('Prefer', 'resolution=merge-duplicates');
    
    RecCount := 0;
    BulkReject := SA();
    
    while not qryLocal.Eof do
    begin
      Application.ProcessMessages;
      
      JSONPayload := SO();
      JSONPayload.I['local_autonum'] := qryLocal.FieldByName('autonum').AsInteger;
      JSONPayload.S['kode_outlet'] := APP_OUTLETID;
      JSONPayload.S['jenis_jasa'] := qryLocal.FieldByName('jenis_jasa').AsString;
      JSONPayload.S['reason'] := qryLocal.FieldByName('keterangan').AsString;
      
      // Combine tanggal (DATE) and waktu (TIME) into a full datetime string
      sRejectDate := FormatDateTime('yyyy-mm-dd', qryLocal.FieldByName('tanggal').AsDateTime) + ' ' +
                     FormatDateTime('hh:nn:ss', qryLocal.FieldByName('waktu').AsDateTime);
      JSONPayload.S['reject_date'] := sRejectDate;
      
      JSONPayload.S['lasteditdate'] := FormatDateTime('yyyy-mm-dd hh:nn:ss', qryLocal.FieldByName('lasteditdate').AsDateTime);
      
      BulkReject.Add(JSONPayload);
      Inc(RecCount);
      qryLocal.Next;
    end;
    
    if BulkReject.Length > 0 then
    begin
      RequestBody := TStringStream.Create(BulkReject.AsJSON, TEncoding.UTF8);
      try
        Response := HTTP.Post(SUPABASE_URL + 'ot_pos_trans_reject?on_conflict=kode_outlet,local_autonum', RequestBody, nil, Headers);
        if (Response.StatusCode <> 200) and (Response.StatusCode <> 201) then
          memLogs.Lines.Add('[!] Trans Reject Bulk Upsert Error: ' + Response.ContentAsString);
      finally
        RequestBody.Free;
      end;
    end;
    
    if RecCount > 0 then memLogs.Lines.Add('Synced ' + IntToStr(RecCount) + ' Reject Trans (Bulk).');
  finally
    qryLocal.Free;
    HTTP.Free;
  end;
end;

procedure TfrmMain.SyncPosTrans(const LastSyncStr, TargetSyncStr: String);
begin
  SyncPosTransPayment(LastSyncStr, TargetSyncStr);
  SyncPosTransPaymentDetails(LastSyncStr, TargetSyncStr);
  SyncPosTransMaster(LastSyncStr, TargetSyncStr);
  SyncPosTransDetail(LastSyncStr, TargetSyncStr);
  SyncPosTransReject(LastSyncStr, TargetSyncStr);
end;
