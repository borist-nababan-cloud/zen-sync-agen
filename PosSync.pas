procedure TfrmMain.SyncPosTransPayment(const LastSyncStr, TargetSyncStr: String);
var
  qryLocal, qrySearchMaster, qrySearchDetail: TMyQuery;
  HTTP: THTTPClient;
  JSONPayload, JSONMember, JSONMasterRow, JSONDetailRow, JSONMemo: ISuperObject;
  BulkPayment, BulkMember, BulkLinkedMaster, BulkLinkedDetail: ISuperArray;
  Response: IHTTPResponse;
  RecCount: Integer;
  Headers: TNetHeaders;
  RequestBody: TStringStream;
  sCurIdPayment, idList: String;
begin
  qryLocal := TMyQuery.Create(nil);
  qrySearchMaster := TMyQuery.Create(nil);
  qrySearchDetail := TMyQuery.Create(nil);
  HTTP := THTTPClient.Create;
  HTTP.ConnectionTimeout := 10000;
  HTTP.ResponseTimeout := 30000;
  try
    qrySearchMaster.Connection := DMDB.dbInternal;
    qrySearchDetail.Connection := DMDB.dbInternal;
    
    qryLocal.Connection := DMDB.dbInternal;
    qryLocal.SQL.Text := 
      'SELECT * FROM trans_payment ' +
      'WHERE ((CONCAT(tanggal, '' '', waktu) > :LastSync AND CONCAT(tanggal, '' '', waktu) <= :TargetSync) ' +
      '   OR (notes REGEXP ''^[0-9]{4}-[0-9]{2}-[0-9]{2}'' AND notes > :LastSync AND notes <= :TargetSync)) ' +
      'ORDER BY tanggal ASC, waktu ASC';
    qryLocal.ParamByName('LastSync').AsString := LastSyncStr;
    qryLocal.ParamByName('TargetSync').AsString := TargetSyncStr;
    qryLocal.Open;
    
    memLogs.Lines.Add(Format('[SYNC-PAY] Local DB scan (%s to %s) -> Found %d payment(s).', 
      [LastSyncStr, TargetSyncStr, qryLocal.RecordCount]));

    if qryLocal.IsEmpty then Exit;
    
    SetLength(Headers, 4);
    Headers[0] := TNameValuePair.Create('apikey', SUPABASE_KEY);
    Headers[1] := TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY);
    Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');
    Headers[3] := TNameValuePair.Create('Prefer', 'resolution=merge-duplicates');

    RecCount := 0;
    BulkPayment := SA();
    BulkMember := SA();
    BulkLinkedMaster := SA();
    BulkLinkedDetail := SA();
    idList := '';

    while not qryLocal.Eof do
    begin
      Application.ProcessMessages;
      sCurIdPayment := qryLocal.FieldByName('id_payment').AsString;
      
      if idList = '' then
        idList := QuotedStr(sCurIdPayment)
      else
        idList := idList + ',' + QuotedStr(sCurIdPayment);

      JSONPayload := SO();
      JSONPayload.S['id_payment'] := sCurIdPayment;
      JSONPayload.S['kode_outlet'] := APP_OUTLETID;
      JSONPayload.S['tanggal'] := FormatDateTime('yyyy-mm-dd', qryLocal.FieldByName('tanggal').AsDateTime);
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
      
      // Member points tracking
      if (qryLocal.FieldByName('id_member').AsString <> '') and 
         (qryLocal.FieldByName('id_member').AsString <> '(NONE)') then
      begin
        JSONMember := SO();
        JSONMember.S['id_payment'] := sCurIdPayment;
        JSONMember.S['user_uid'] := qryLocal.FieldByName('id_member').AsString;
        JSONMember.F['point_awal'] := qryLocal.FieldByName('point_awal').AsFloat;
        JSONMember.F['tambah_point'] := qryLocal.FieldByName('tambah_point').AsFloat;
        JSONMember.F['kurang_point'] := qryLocal.FieldByName('kurang_point').AsFloat;
        JSONMember.F['sisa_point'] := qryLocal.FieldByName('sisa').AsFloat;
        BulkMember.Add(JSONMember);
      end;

      Inc(RecCount);
      qryLocal.Next;
    end;

    // 1. O(1) Local DB Batch Reconcile: Pull all trans_master records linked to payments in batch
    if idList <> '' then
    begin
      qrySearchMaster.Close;
      qrySearchMaster.SQL.Text := 
        'SELECT tm.*, (SELECT k.kodekaryawan FROM ben_hrd_karyawan_info k WHERE k.idkaryawan = tm.therapist_id AND k.active = ''Y'' LIMIT 1) as kodekaryawan ' +
        'FROM trans_master tm WHERE tm.id_payment IN (' + idList + ')';
      qrySearchMaster.Open;
      
      while not qrySearchMaster.Eof do
      begin
        JSONMasterRow := SO();
        JSONMasterRow.S['trans_id'] := qrySearchMaster.FieldByName('trans_id').AsString;
        JSONMasterRow.S['kode_outlet'] := APP_OUTLETID;
        JSONMasterRow.S['start_time'] := qrySearchMaster.FieldByName('start_time').AsString;
        JSONMasterRow.S['end_time'] := qrySearchMaster.FieldByName('end_time').AsString;
        JSONMasterRow.S['tanggal'] := FormatDateTime('yyyy-mm-dd', qrySearchMaster.FieldByName('tanggal').AsDateTime);
        JSONMasterRow.S['status_trans'] := qrySearchMaster.FieldByName('status_trans').AsString; // 'PAID'
        JSONMasterRow.S['nama_customer'] := qrySearchMaster.FieldByName('nama_customer').AsString;
        JSONMasterRow.S['room_id'] := APP_OUTLETID + '.' + qrySearchMaster.FieldByName('room_id').AsString;
        JSONMasterRow.F['subtotal'] := qrySearchMaster.FieldByName('subtotal').AsFloat;
        
        if qrySearchMaster.FieldByName('kodekaryawan').AsString <> '' then
          JSONMasterRow.S['kodekaryawan'] := qrySearchMaster.FieldByName('kodekaryawan').AsString
        else
          JSONMasterRow.Null['kodekaryawan'] := jNull;
          
        JSONMasterRow.Null['byrequest'] := jNull;
        JSONMasterRow.Null['typejasa'] := jNull;
        JSONMasterRow.Null['rcpt'] := jNull;

        if qrySearchMaster.FieldByName('notes').AsString <> '' then
        begin
          try
            JSONMemo := SO(qrySearchMaster.FieldByName('notes').AsString);
            if Assigned(JSONMemo) then
            begin
              if JSONMemo.S['byrequest'] <> '' then
                JSONMasterRow.S['byrequest'] := JSONMemo.S['byrequest'];
              if JSONMemo.S['typejasa'] <> '' then
                JSONMasterRow.S['typejasa'] := JSONMemo.S['typejasa'];
              if JSONMemo.S['user'] <> '' then
                JSONMasterRow.S['rcpt'] := JSONMemo.S['user'];
            end;
          except
          end;
        end;

        JSONMasterRow.S['id_payment'] := qrySearchMaster.FieldByName('id_payment').AsString;
        
        if qrySearchMaster.FindField('user_uid') <> nil then
        begin
          if qrySearchMaster.FieldByName('user_uid').AsString <> '' then
            JSONMasterRow.S['user_uid'] := qrySearchMaster.FieldByName('user_uid').AsString
          else
            JSONMasterRow.Null['user_uid'] := jNull;
        end
        else
          JSONMasterRow.Null['user_uid'] := jNull;

        BulkLinkedMaster.Add(JSONMasterRow);
        qrySearchMaster.Next;
      end;

      // 2. O(1) Local DB Batch Reconcile: Pull all trans_detail lines linked to payments in batch
      qrySearchDetail.Close;
      qrySearchDetail.SQL.Text := 
        'SELECT td.*, (SELECT k.kodekaryawan FROM ben_hrd_karyawan_info k WHERE k.idkaryawan = td.teraphist_id AND k.active = ''Y'' LIMIT 1) as kodekaryawan ' +
        'FROM trans_detail td WHERE td.payment_id IN (' + idList + ')';
      qrySearchDetail.Open;

      while not qrySearchDetail.Eof do
      begin
        JSONDetailRow := SO();
        JSONDetailRow.S['trans_id'] := qrySearchDetail.FieldByName('id_trans').AsString;
        JSONDetailRow.S['kode_outlet'] := APP_OUTLETID;
        JSONDetailRow.S['tanggal'] := FormatDateTime('yyyy-mm-dd', qrySearchDetail.FieldByName('tanggal').AsDateTime);
        JSONDetailRow.S['trans_type_id'] := qrySearchDetail.FieldByName('trans_type_id').AsString;
        JSONDetailRow.S['produk_jasa_id'] := qrySearchDetail.FieldByName('produk_jasa_id').AsString;
        JSONDetailRow.S['produk_jasa_nama'] := qrySearchDetail.FieldByName('produk_jasa_nama').AsString;
        JSONDetailRow.F['disc_amount'] := qrySearchDetail.FieldByName('disc_amount').AsFloat;
        JSONDetailRow.F['disc_percent'] := qrySearchDetail.FieldByName('disc_percent').AsFloat;
        JSONDetailRow.F['subtotal'] := qrySearchDetail.FieldByName('subtotal').AsFloat;
        JSONDetailRow.F['price'] := qrySearchDetail.FieldByName('harga').AsFloat;
        JSONDetailRow.F['qty'] := qrySearchDetail.FieldByName('quantity').AsFloat;
        JSONDetailRow.S['therapist_id'] := qrySearchDetail.FieldByName('teraphist_id').AsString;
        JSONDetailRow.S['room_id'] := APP_OUTLETID + '.' + qrySearchDetail.FieldByName('room_id').AsString;
        JSONDetailRow.S['aroma_oil'] := qrySearchDetail.FieldByName('aroma').AsString;
        JSONDetailRow.I['lama'] := qrySearchDetail.FieldByName('lama').AsInteger;
        JSONDetailRow.I['local_autonum'] := qrySearchDetail.FieldByName('autonum').AsInteger;
        
        if qrySearchDetail.FieldByName('kodekaryawan').AsString <> '' then
          JSONDetailRow.S['kode_karyawan'] := qrySearchDetail.FieldByName('kodekaryawan').AsString
        else
          JSONDetailRow.Null['kode_karyawan'] := jNull;
        
        JSONDetailRow.S['id_payment'] := qrySearchDetail.FieldByName('payment_id').AsString;
          
        if (qrySearchDetail.FieldByName('id_customer').AsString <> '') and (qrySearchDetail.FieldByName('id_customer').AsString <> '(NONE)') then
          JSONDetailRow.S['user_uid'] := qrySearchDetail.FieldByName('id_customer').AsString
        else
          JSONDetailRow.Null['user_uid'] := jNull;

        BulkLinkedDetail.Add(JSONDetailRow);
        qrySearchDetail.Next;
      end;
    end;

    // A. Bulk Upsert Payments to Supabase
    if BulkPayment.Length > 0 then
    begin
      RequestBody := TStringStream.Create(BulkPayment.AsJSON, TEncoding.UTF8);
      try
        Response := HTTP.Post(SUPABASE_URL + 'ot_pos_trans_payment?on_conflict=id_payment', RequestBody, nil, Headers);
        if (Response.StatusCode <> 200) and (Response.StatusCode <> 201) then
        begin
          memLogs.Lines.Add('[!] Bulk Payment Upsert Error: ' + Response.ContentAsString);
          raise Exception.Create('Payment Bulk Upsert Failed (' + IntToStr(Response.StatusCode) + '): ' + Response.ContentAsString);
        end
        else
          memLogs.Lines.Add(Format('[SYNC-PAY] Upserted %d payment header(s) to Supabase (HTTP %d).', [BulkPayment.Length, Response.StatusCode]));
      finally
        RequestBody.Free;
      end;
    end;
    
    // B. Bulk Upsert Linked Master records (reconciling status_trans = 'PAID' & id_payment)
    if BulkLinkedMaster.Length > 0 then
    begin
      RequestBody := TStringStream.Create(BulkLinkedMaster.AsJSON, TEncoding.UTF8);
      try
        Response := HTTP.Post(SUPABASE_URL + 'ot_pos_trans_master?on_conflict=trans_id', RequestBody, nil, Headers);
        if (Response.StatusCode <> 200) and (Response.StatusCode <> 201) then
        begin
          memLogs.Lines.Add('[!] Reconciled Master Bulk Upsert Error: ' + Response.ContentAsString);
          raise Exception.Create('Reconciled Master Upsert Failed (' + IntToStr(Response.StatusCode) + '): ' + Response.ContentAsString);
        end
        else
          memLogs.Lines.Add(Format('[SYNC-PAY] Reconciled and updated %d linked trans_master to PAID with id_payment (HTTP %d).', [BulkLinkedMaster.Length, Response.StatusCode]));
      finally
        RequestBody.Free;
      end;
    end;

    // C. Bulk Upsert Linked Detail records (reconciling id_payment)
    if BulkLinkedDetail.Length > 0 then
    begin
      RequestBody := TStringStream.Create(BulkLinkedDetail.AsJSON, TEncoding.UTF8);
      try
        Response := HTTP.Post(SUPABASE_URL + 'ot_pos_trans_detail?on_conflict=kode_outlet,local_autonum', RequestBody, nil, Headers);
        if (Response.StatusCode <> 200) and (Response.StatusCode <> 201) then
        begin
          memLogs.Lines.Add('[!] Reconciled Detail Bulk Upsert Error: ' + Response.ContentAsString);
          raise Exception.Create('Reconciled Detail Upsert Failed (' + IntToStr(Response.StatusCode) + '): ' + Response.ContentAsString);
        end
        else
          memLogs.Lines.Add(Format('[SYNC-PAY] Reconciled and updated %d linked trans_detail with id_payment (HTTP %d).', [BulkLinkedDetail.Length, Response.StatusCode]));
      finally
        RequestBody.Free;
      end;
    end;

    // D. Member point transactions
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
    
    if RecCount > 0 then 
      memLogs.Lines.Add(Format('[SYNC-PAY] Cycle summary: %d payment(s), %d linked master(s), %d linked detail(s) reconciled.', 
        [RecCount, BulkLinkedMaster.Length, BulkLinkedDetail.Length]));
  finally
    qryLocal.Free;
    qrySearchMaster.Free;
    qrySearchDetail.Free;
    HTTP.Free;
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
  HTTP.ConnectionTimeout := 10000;
  HTTP.ResponseTimeout := 30000;
  try
    qryLocal.Connection := DMDB.dbInternal;
    // Harmonized query: checks pd.lasteditdate, tp.waktu/tanggal, and tp.notes to ensure zero dropped slips
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
      'WHERE ((pd.lasteditdate > :LastSync AND pd.lasteditdate <= :TargetSync) ' +
      '   OR (CONCAT(tp.tanggal, '' '', tp.waktu) > :LastSync AND CONCAT(tp.tanggal, '' '', tp.waktu) <= :TargetSync) ' +
      '   OR (tp.notes REGEXP ''^[0-9]{4}-[0-9]{2}-[0-9]{2}'' AND tp.notes > :LastSync AND tp.notes <= :TargetSync)) ' +
      'ORDER BY pd.lasteditdate ASC';
    qryLocal.ParamByName('LastSync').AsString := LastSyncStr;
    qryLocal.ParamByName('TargetSync').AsString := TargetSyncStr;
    qryLocal.Open;
    
    memLogs.Lines.Add(Format('[SYNC-PAYDETAIL] Local DB scan (%s to %s) -> Found %d record(s).', 
      [LastSyncStr, TargetSyncStr, qryLocal.RecordCount]));

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
      JSONPayload.S['tanggal'] := FormatDateTime('yyyy-mm-dd', qryLocal.FieldByName('tanggal').AsDateTime);
      
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
      
      // GC handling: safely wrapped in try..except so non-critical GC lookup errors cannot abort payment slips upsert
      if (qryLocal.FieldByName('refgift').AsString <> '') and (qryLocal.FieldByName('refgift').AsString <> '(NONE)') then
      begin
        try
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
            JSONGC.Null['qrcode'] := jNull;
            JSONGC.S['pack_number'] := qryLocal.FieldByName('refgift').AsString;
            JSONGC.S['nama_gc'] := 'AUTO INSERT ' + qryLocal.FieldByName('refgift').AsString + ' ' + FloatToStr(qryLocal.FieldByName('vgift').AsFloat);
            JSONGC.F['value'] := qryLocal.FieldByName('vgift').AsFloat;
            JSONGC.S['buy_at'] := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
            JSONGC.S['expired_date'] := FormatDateTime('yyyy-mm-dd', IncDay(Now, 120));
            JSONGC.B['is_active'] := True;
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
        except
          on E: Exception do
            memLogs.Lines.Add(Format('[!] Non-fatal GC sync warning (Payment: %s, GC: %s): %s', 
              [qryLocal.FieldByName('id_payment').AsString, qryLocal.FieldByName('refgift').AsString, E.Message]));
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
        begin
          memLogs.Lines.Add('[!] Payment Details Bulk Upsert Error: ' + Response.ContentAsString);
          raise Exception.Create('Payment Details Bulk Upsert Failed (' + IntToStr(Response.StatusCode) + '): ' + Response.ContentAsString);
        end
        else
          memLogs.Lines.Add(Format('[SYNC-PAYDETAIL] Successfully upserted %d payment detail slip(s) to Supabase (HTTP %d).', [BulkPaymentDetails.Length, Response.StatusCode]));
      finally
        RequestBody.Free;
      end;
    end;
    
    if RecCount > 0 then memLogs.Lines.Add(Format('[SYNC-PAYDETAIL] Cycle completed: %d slip(s) processed.', [RecCount]));
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
  HTTP.ConnectionTimeout := 10000;
  HTTP.ResponseTimeout := 30000;
  try
    qryLocal.Connection := DMDB.dbInternal;
    qryLocal.SQL.Text := 
      'SELECT tm.*, (SELECT k.kodekaryawan FROM ben_hrd_karyawan_info k WHERE k.idkaryawan = tm.therapist_id AND k.active = ''Y'' LIMIT 1) as kodekaryawan ' +
      'FROM trans_master tm ' +
      'WHERE CONCAT(tm.tanggal, '' '', tm.start_time) > :LastSync AND CONCAT(tm.tanggal, '' '', tm.start_time) <= :TargetSync ORDER BY tm.tanggal ASC, tm.start_time ASC';
    qryLocal.ParamByName('LastSync').AsString := LastSyncStr;
    qryLocal.ParamByName('TargetSync').AsString := TargetSyncStr;
    qryLocal.Open;
    
    memLogs.Lines.Add(Format('[SYNC-MASTER] Local DB scan (%s to %s) -> Found %d record(s).', 
      [LastSyncStr, TargetSyncStr, qryLocal.RecordCount]));

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
        JSONPayload.Null['kodekaryawan'] := jNull;
      
      // Ensure all keys exist for every row to prevent PostgREST PGRST102 error
      JSONPayload.Null['byrequest'] := jNull;
      JSONPayload.Null['typejasa'] := jNull;
      JSONPayload.Null['rcpt'] := jNull;

      if qryLocal.FieldByName('notes').AsString <> '' then
      begin
        try
          JSONMemo := SO(qryLocal.FieldByName('notes').AsString);
          if Assigned(JSONMemo) then
          begin
            if JSONMemo.S['byrequest'] <> '' then
              JSONPayload.S['byrequest'] := JSONMemo.S['byrequest'];
            if JSONMemo.S['typejasa'] <> '' then
              JSONPayload.S['typejasa'] := JSONMemo.S['typejasa'];
            if JSONMemo.S['user'] <> '' then
              JSONPayload.S['rcpt'] := JSONMemo.S['user'];
          end;
        except
        end;
      end;
      
      if (qryLocal.FieldByName('id_payment').AsString <> '') and (qryLocal.FieldByName('id_payment').AsString <> '(NONE)') then
        JSONPayload.S['id_payment'] := qryLocal.FieldByName('id_payment').AsString
      else
        JSONPayload.Null['id_payment'] := jNull;

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
        begin
          memLogs.Lines.Add('[!] Trans Master Bulk Upsert Error: ' + Response.ContentAsString);
          raise Exception.Create('Trans Master Bulk Upsert Failed (' + IntToStr(Response.StatusCode) + '): ' + Response.ContentAsString);
        end
        else
          memLogs.Lines.Add(Format('[SYNC-MASTER] Successfully upserted %d master trans to Supabase (HTTP %d).', [BulkMaster.Length, Response.StatusCode]));
      finally
        RequestBody.Free;
      end;
    end;
    
    if RecCount > 0 then memLogs.Lines.Add(Format('[SYNC-MASTER] Cycle completed: %d record(s) processed.', [RecCount]));
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
  HTTP.ConnectionTimeout := 10000;
  HTTP.ResponseTimeout := 30000;
  try
    qryLocal.Connection := DMDB.dbInternal;
    qryLocal.SQL.Text := 
      'SELECT td.*, (SELECT k.kodekaryawan FROM ben_hrd_karyawan_info k WHERE k.idkaryawan = td.teraphist_id AND k.active = ''Y'' LIMIT 1) as kodekaryawan ' +
      'FROM trans_detail td ' +
      'WHERE CONCAT(td.tanggal, '' '', td.start_time) > :LastSync AND CONCAT(td.tanggal, '' '', td.start_time) <= :TargetSync ORDER BY td.tanggal ASC, td.start_time ASC';
    qryLocal.ParamByName('LastSync').AsString := LastSyncStr;
    qryLocal.ParamByName('TargetSync').AsString := TargetSyncStr;
    qryLocal.Open;
    
    memLogs.Lines.Add(Format('[SYNC-DETAIL] Local DB scan (%s to %s) -> Found %d record(s).', 
      [LastSyncStr, TargetSyncStr, qryLocal.RecordCount]));

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
        JSONPayload.Null['kode_karyawan'] := jNull;
      
      if (qryLocal.FieldByName('payment_id').AsString <> '') and (qryLocal.FieldByName('payment_id').AsString <> '(NONE)') then
        JSONPayload.S['id_payment'] := qryLocal.FieldByName('payment_id').AsString
      else
        JSONPayload.Null['id_payment'] := jNull;
        
      if (qryLocal.FieldByName('id_customer').AsString <> '') and (qryLocal.FieldByName('id_customer').AsString <> '(NONE)') then
        JSONPayload.S['user_uid'] := qryLocal.FieldByName('id_customer').AsString
      else
        JSONPayload.Null['user_uid'] := jNull;

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
        begin
          memLogs.Lines.Add('[!] Trans Detail Bulk Upsert Error: ' + Response.ContentAsString);
          raise Exception.Create('Trans Detail Bulk Upsert Failed (' + IntToStr(Response.StatusCode) + '): ' + Response.ContentAsString);
        end
        else
          memLogs.Lines.Add(Format('[SYNC-DETAIL] Successfully upserted %d detail trans to Supabase (HTTP %d).', [BulkDetail.Length, Response.StatusCode]));
      finally
        RequestBody.Free;
      end;
    end;
    
    if RecCount > 0 then memLogs.Lines.Add(Format('[SYNC-DETAIL] Cycle completed: %d record(s) processed.', [RecCount]));
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
  HTTP.ConnectionTimeout := 10000;
  HTTP.ResponseTimeout := 30000;
  try
    qryLocal.Connection := DMDB.dbInternal;
    qryLocal.SQL.Text := 'SELECT autonum, tanggal, waktu, jenis_jasa, keterangan, lasteditdate ' +
                         'FROM trans_reject ' +
                         'WHERE lasteditdate > :LastSync AND lasteditdate <= :TargetSync ' +
                         'ORDER BY lasteditdate ASC';
    qryLocal.ParamByName('LastSync').AsString := LastSyncStr;
    qryLocal.ParamByName('TargetSync').AsString := TargetSyncStr;
    qryLocal.Open;
    
    memLogs.Lines.Add(Format('[SYNC-REJECT] Local DB scan (%s to %s) -> Found %d record(s).', 
      [LastSyncStr, TargetSyncStr, qryLocal.RecordCount]));

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
      JSONPayload.S['tanggal'] := FormatDateTime('yyyy-mm-dd', qryLocal.FieldByName('tanggal').AsDateTime);
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
        begin
          memLogs.Lines.Add('[!] Trans Reject Bulk Upsert Error: ' + Response.ContentAsString);
          raise Exception.Create('Trans Reject Bulk Upsert Failed (' + IntToStr(Response.StatusCode) + '): ' + Response.ContentAsString);
        end
        else
          memLogs.Lines.Add(Format('[SYNC-REJECT] Successfully upserted %d reject record(s) to Supabase (HTTP %d).', [BulkReject.Length, Response.StatusCode]));
      finally
        RequestBody.Free;
      end;
    end;
    
    if RecCount > 0 then memLogs.Lines.Add(Format('[SYNC-REJECT] Cycle completed: %d record(s) processed.', [RecCount]));
  finally
    qryLocal.Free;
    HTTP.Free;
  end;
end;

procedure TfrmMain.SyncPosGCSold(const LastSyncStr, TargetSyncStr: String);
var
  qryLocal: TMyQuery;
  HTTP: THTTPClient;
  JSONGC: ISuperObject;
  BulkGC: ISuperArray;
  Response: IHTTPResponse;
  RecCount, BatchCount: Integer;
  Headers: TNetHeaders;
  RequestBody: TStringStream;
  sStartDate, sEndDate, sGCNumber, sPack, sMember, sQRCode, sPakai, sPayBuy, sPayUsed, sOutBuy, sOutUsed: String;
  bUsed, bActive: Boolean;
  dtBuyAt, dtExpired: TDateTime;
begin
  sStartDate := Copy(LastSyncStr, 1, 10);
  sEndDate := Copy(TargetSyncStr, 1, 10);

  qryLocal := TMyQuery.Create(nil);
  HTTP := THTTPClient.Create;
  HTTP.ConnectionTimeout := 10000;
  HTTP.ResponseTimeout := 30000;
  try
    qryLocal.Connection := DMDB.dbInternal;
    qryLocal.SQL.Text :=
      'SELECT s.*, ' +
      '  (SELECT d.paket_number FROM gc_detail d WHERE d.gc_number = s.gc_number LIMIT 1) AS pack_number ' +
      'FROM gc_sold s ' +
      'WHERE s.gc_number IS NOT NULL AND s.gc_number <> '''' AND s.gc_number <> ''(NONE)'' ' +
      '  AND s.tgl_jual >= :StartDate AND s.tgl_jual <= :EndDate ' +
      'ORDER BY s.autonum ASC';
    qryLocal.ParamByName('StartDate').AsString := sStartDate;
    qryLocal.ParamByName('EndDate').AsString := sEndDate;
    qryLocal.Open;

    memLogs.Lines.Add(Format('[SYNC-GC] Local DB scan (%s to %s) -> Found %d sold GC(s).',
      [sStartDate, sEndDate, qryLocal.RecordCount]));

    if qryLocal.IsEmpty then Exit;

    SetLength(Headers, 4);
    Headers[0] := TNameValuePair.Create('apikey', SUPABASE_KEY);
    Headers[1] := TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY);
    Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');
    // Insert-only: mencegah menimpa has_used=true jika GC sudah dipakai di cabang lain
    Headers[3] := TNameValuePair.Create('Prefer', 'resolution=ignore-duplicates');

    RecCount := 0;
    BatchCount := 0;
    BulkGC := SA();

    while not qryLocal.Eof do
    begin
      Application.ProcessMessages;

      sGCNumber := Trim(qryLocal.FieldByName('gc_number').AsString);
      sPack := Trim(qryLocal.FieldByName('pack_number').AsString);
      sMember := Trim(qryLocal.FieldByName('id_members').AsString);
      sPakai := UpperCase(Trim(qryLocal.FieldByName('pakai').AsString));
      bUsed := (sPakai = 'Y');
      bActive := (UpperCase(Trim(qryLocal.FieldByName('aktif').AsString)) <> 'N');

      JSONGC := SO();
      if (sMember <> '') and (sMember <> '(NONE)') then
        JSONGC.S['user_uid'] := sMember
      else
        JSONGC.Null['user_uid'] := jNull;

      JSONGC.S['gc_number'] := sGCNumber;
      JSONGC.S['gc_barcode'] := sGCNumber;

      sQRCode := Trim(qryLocal.FieldByName('notes').AsString);
      if (sQRCode <> '') and (sQRCode <> '(NONE)') then
        JSONGC.S['qrcode'] := sQRCode
      else
        JSONGC.Null['qrcode'] := jNull;

      if (sPack <> '') and (sPack <> '(NONE)') then
        JSONGC.S['pack_number'] := sPack
      else
        JSONGC.Null['pack_number'] := jNull;

      JSONGC.S['nama_gc'] := qryLocal.FieldByName('nama_menu').AsString;
      JSONGC.F['value'] := qryLocal.FieldByName('harga_jasa').AsFloat;

      if (not qryLocal.FieldByName('tgl_jual').IsNull) and (FormatDateTime('yyyy', qryLocal.FieldByName('tgl_jual').AsDateTime) <> '2000') then
      begin
        dtBuyAt := qryLocal.FieldByName('tgl_jual').AsDateTime;
        JSONGC.S['buy_at'] := FormatDateTime('yyyy-mm-dd"T"00:00:00"+07:00"', dtBuyAt);
      end
      else if (not qryLocal.FieldByName('tanggal').IsNull) and (FormatDateTime('yyyy', qryLocal.FieldByName('tanggal').AsDateTime) <> '2000') then
      begin
        dtBuyAt := qryLocal.FieldByName('tanggal').AsDateTime;
        JSONGC.S['buy_at'] := FormatDateTime('yyyy-mm-dd"T"00:00:00"+07:00"', dtBuyAt);
      end
      else
      begin
        dtBuyAt := Now;
        JSONGC.Null['buy_at'] := jNull;
      end;

      // expired_date selalu 120 hari dari tanggal beli (tgl_jual / buy_at)
      dtExpired := IncDay(dtBuyAt, 120);
      JSONGC.S['expired_date'] := FormatDateTime('yyyy-mm-dd', dtExpired);
      JSONGC.B['is_active'] := bActive;

      JSONGC.B['has_used'] := bUsed;
      if bUsed and (not qryLocal.FieldByName('tgl_pakai').IsNull) and (FormatDateTime('yyyy', qryLocal.FieldByName('tgl_pakai').AsDateTime) <> '2000') then
        JSONGC.S['used_at'] := FormatDateTime('yyyy-mm-dd"T"00:00:00"+07:00"', qryLocal.FieldByName('tgl_pakai').AsDateTime)
      else
        JSONGC.Null['used_at'] := jNull;

      sPayBuy := Trim(qryLocal.FieldByName('payment_jual').AsString);
      if (sPayBuy <> '') and (sPayBuy <> '(NONE)') then
        JSONGC.S['id_payment_buy'] := sPayBuy
      else
        JSONGC.Null['id_payment_buy'] := jNull;

      sPayUsed := Trim(qryLocal.FieldByName('payment_pakai').AsString);
      if bUsed and (sPayUsed <> '') and (sPayUsed <> '(NONE)') then
        JSONGC.S['id_payment_used'] := sPayUsed
      else
        JSONGC.Null['id_payment_used'] := jNull;

      sOutBuy := Trim(qryLocal.FieldByName('outlet_jual').AsString);
      if (sOutBuy <> '') and (sOutBuy <> '(NONE)') then
        JSONGC.S['kode_outlet_buy'] := sOutBuy
      else
        JSONGC.S['kode_outlet_buy'] := APP_OUTLETID;

      sOutUsed := Trim(qryLocal.FieldByName('outlet_pakai').AsString);
      if bUsed and (sOutUsed <> '') and (sOutUsed <> '(NONE)') then
        JSONGC.S['kode_outlet_used'] := sOutUsed
      else
        JSONGC.Null['kode_outlet_used'] := jNull;

      BulkGC.Add(JSONGC);
      Inc(RecCount);

      if BulkGC.Length >= 50 then
      begin
        Inc(BatchCount);
        RequestBody := TStringStream.Create(BulkGC.AsJSON, TEncoding.UTF8);
        try
          Response := HTTP.Post(SUPABASE_URL + 'ot_pos_gc_transaction?on_conflict=gc_number', RequestBody, nil, Headers);
          if (Response.StatusCode <> 200) and (Response.StatusCode <> 201) then
          begin
            memLogs.Lines.Add(Format('[!] GC Sold Batch %d Error: %s', [BatchCount, Response.ContentAsString]));
            raise Exception.Create('GC Sold Bulk Sync Failed (' + IntToStr(Response.StatusCode) + '): ' + Response.ContentAsString);
          end
          else
            memLogs.Lines.Add(Format('[SYNC-GC] Batch %d synced %d GC(s) with ignore-duplicates (HTTP %d).',
              [BatchCount, BulkGC.Length, Response.StatusCode]));
        finally
          RequestBody.Free;
        end;
        BulkGC := SA();
      end;

      qryLocal.Next;
    end;

    if BulkGC.Length > 0 then
    begin
      Inc(BatchCount);
      RequestBody := TStringStream.Create(BulkGC.AsJSON, TEncoding.UTF8);
      try
        Response := HTTP.Post(SUPABASE_URL + 'ot_pos_gc_transaction?on_conflict=gc_number', RequestBody, nil, Headers);
        if (Response.StatusCode <> 200) and (Response.StatusCode <> 201) then
        begin
          memLogs.Lines.Add(Format('[!] GC Sold Final Batch %d Error: %s', [BatchCount, Response.ContentAsString]));
          raise Exception.Create('GC Sold Bulk Sync Failed (' + IntToStr(Response.StatusCode) + '): ' + Response.ContentAsString);
        end
        else
          memLogs.Lines.Add(Format('[SYNC-GC] Final Batch %d synced %d GC(s) with ignore-duplicates (HTTP %d).',
            [BatchCount, BulkGC.Length, Response.StatusCode]));
      finally
        RequestBody.Free;
      end;
    end;

    if RecCount > 0 then
      memLogs.Lines.Add(Format('[SYNC-GC] Cycle completed: %d sold GC(s) processed.', [RecCount]));
  finally
    qryLocal.Free;
    HTTP.Free;
  end;
end;

procedure TfrmMain.SyncPosTrans(const LastSyncStr, TargetSyncStr: String);
var
  bHasError: Boolean;
  FS: TFormatSettings;
  dtLast: TDateTime;
  sPosLookbackStr: String;
begin
  bHasError := False;

  // Compute a 2-hour Safe Lookback Buffer for POS real-time updates.
  // This guarantees that any payment finalized with past timestamps, cashier clock drift,
  // or retrospective status updates are unconditionally caught and reconciled.
  FS := TFormatSettings.Create('en-US');
  FS.DateSeparator := '-';
  FS.TimeSeparator := ':';
  FS.ShortDateFormat := 'yyyy-mm-dd';

  if TryStrToDateTime(LastSyncStr, dtLast, FS) then
  begin
    // Look back 2 hours (IncHour -2)
    sPosLookbackStr := FormatDateTime('yyyy-mm-dd hh:nn:ss', IncHour(dtLast, -2));
  end
  else
    sPosLookbackStr := LastSyncStr;

  memLogs.Lines.Add(Format('[POS-SYNC] Window: %s to %s (Lookback Anchor: %s)', [LastSyncStr, TargetSyncStr, sPosLookbackStr]));

  try
    SyncPosTransPayment(sPosLookbackStr, TargetSyncStr);
  except
    on E: Exception do 
    begin
      memLogs.Lines.Add('[!] Error SyncPosTransPayment: ' + E.Message);
      bHasError := True;
    end;
  end;

  try
    SyncPosTransPaymentDetails(sPosLookbackStr, TargetSyncStr);
  except
    on E: Exception do 
    begin
      memLogs.Lines.Add('[!] Error SyncPosTransPaymentDetails: ' + E.Message);
      bHasError := True;
    end;
  end;

  try
    SyncPosTransMaster(sPosLookbackStr, TargetSyncStr);
  except
    on E: Exception do 
    begin
      memLogs.Lines.Add('[!] Error SyncPosTransMaster: ' + E.Message);
      bHasError := True;
    end;
  end;

  try
    SyncPosTransDetail(sPosLookbackStr, TargetSyncStr);
  except
    on E: Exception do 
    begin
      memLogs.Lines.Add('[!] Error SyncPosTransDetail: ' + E.Message);
      bHasError := True;
    end;
  end;

  try
    SyncPosTransReject(sPosLookbackStr, TargetSyncStr);
  except
    on E: Exception do 
    begin
      memLogs.Lines.Add('[!] Error SyncPosTransReject: ' + E.Message);
      bHasError := True;
    end;
  end;

  try
    SyncPosGCSold(sPosLookbackStr, TargetSyncStr);
  except
    on E: Exception do
    begin
      memLogs.Lines.Add('[!] Error SyncPosGCSold: ' + E.Message);
      bHasError := True;
    end;
  end;

  if bHasError then
    raise Exception.Create('POS Sync cycle had one or more failed sub-processes. Chunk anchor preserved for retry.');
end;
