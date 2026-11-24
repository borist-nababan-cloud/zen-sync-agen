// ==============================================================================
// RateSync.pas - Guest Rating Dual Synchronization Routine
// Target 1: Legacy n8n Webhook (https://n8nserver.zenfamilyspa.id/webhook/postzenguestrating)
// Target 2: Supabase REST API (public.ot_pos_guest_rating)
// Architecture: Non-blocking, fault-tolerant, strictly silent logging to memLogs
// ==============================================================================

procedure TfrmMain.SyncGuestRating;
var
  qryLocal, qryMaster, qryPayment, qryUpdate: TMyQuery;
  HTTP: THTTPClient;
  JSONN8N, JSONSupa: ISuperObject;
  N8NHeaders, SupaHeaders: TNetHeaders;
  N8NBodyStream, SupaBodyStream: TStringStream;
  N8NResp, SupaResp: IHTTPResponse;
  sRatingCode, sIdPayment, sTransId, sRoomId, sTherapistId, sKodeKaryawan, sIdMember: String;
  sTanggalStr: String;
  dtTanggal: TDateTime;
  bN8NOk, bSupaOk: Boolean;
  ProcessedCount: Integer;
begin
  if not dmDB.dbInternal.Connected then
  begin
    Exit; // Silent exit if local DB is offline; tmrConnectDB watchdog handles reconnection
  end;

  qryLocal := TMyQuery.Create(nil);
  qryMaster := TMyQuery.Create(nil);
  qryPayment := TMyQuery.Create(nil);
  qryUpdate := TMyQuery.Create(nil);
  HTTP := THTTPClient.Create;
  HTTP.ConnectionTimeout := 8000;
  HTTP.ResponseTimeout := 15000;

  try
    qryLocal.Connection := dmDB.dbInternal;
    qryMaster.Connection := dmDB.dbInternal;
    qryPayment.Connection := dmDB.dbInternal;
    qryUpdate.Connection := dmDB.dbInternal;

    // 1. Scan for pending local ratings (up to 10 records per cycle)
    qryLocal.SQL.Text := 
      'SELECT ratingcode, id_payment, trans_id, isupload, uploadtime ' +
      'FROM ben_guest_rating ' +
      'WHERE isupload = ''N'' ' +
      'ORDER BY uploadtime ASC LIMIT 10';
    qryLocal.Open;

    if qryLocal.IsEmpty then
      Exit; // Silent exit when no new ratings are queued

    memLogs.Lines.Add(Format('[RATE-SYNC] Detected %d pending guest rating(s). Processing dual-sync...', [qryLocal.RecordCount]));

    // Setup headers for n8n Webhook
    SetLength(N8NHeaders, 2);
    N8NHeaders[0] := TNameValuePair.Create('zenwebhook', 'ZenSpa168');
    N8NHeaders[1] := TNameValuePair.Create('Content-Type', 'application/json');

    // Setup headers for Supabase REST API
    SetLength(SupaHeaders, 4);
    SupaHeaders[0] := TNameValuePair.Create('apikey', SUPABASE_KEY);
    SupaHeaders[1] := TNameValuePair.Create('Authorization', 'Bearer ' + SUPABASE_KEY);
    SupaHeaders[2] := TNameValuePair.Create('Content-Type', 'application/json');
    SupaHeaders[3] := TNameValuePair.Create('Prefer', 'resolution=merge-duplicates');

    ProcessedCount := 0;

    while not qryLocal.Eof do
    begin
      Application.ProcessMessages;

      sRatingCode := qryLocal.FieldByName('ratingcode').AsString;
      sIdPayment := qryLocal.FieldByName('id_payment').AsString;
      sTransId := qryLocal.FieldByName('trans_id').AsString;
      sRoomId := '';
      sTherapistId := '';
      sKodeKaryawan := '';
      sIdMember := '';
      sTanggalStr := FormatDateTime('yyyy-mm-dd', Date);

      try
        // 2. Relational Enrichment: trans_master (room, therapist, tanggal, kodekaryawan)
        if sTransId <> '' then
        begin
          qryMaster.Close;
          qryMaster.SQL.Text := 
            'SELECT tm.tanggal, tm.room_id, tm.therapist_id, ' +
            '  (SELECT k.kodekaryawan FROM ben_hrd_karyawan_info k WHERE k.idkaryawan = tm.therapist_id AND k.active = ''Y'' LIMIT 1) as kodekaryawan ' +
            'FROM trans_master tm WHERE tm.trans_id = :TransId LIMIT 1';
          qryMaster.ParamByName('TransId').AsString := sTransId;
          qryMaster.Open;

          if not qryMaster.IsEmpty then
          begin
            sRoomId := qryMaster.FieldByName('room_id').AsString;
            sTherapistId := qryMaster.FieldByName('therapist_id').AsString;
            sKodeKaryawan := qryMaster.FieldByName('kodekaryawan').AsString;
            dtTanggal := qryMaster.FieldByName('tanggal').AsDateTime;
            if dtTanggal > 0 then
              sTanggalStr := FormatDateTime('yyyy-mm-dd', dtTanggal);
          end;
        end;

        // 3. Relational Enrichment: trans_payment (member identification)
        if sIdPayment <> '' then
        begin
          qryPayment.Close;
          qryPayment.SQL.Text := 
            'SELECT tp.id_member, tp.tanggal FROM trans_payment tp WHERE tp.id_payment = :IdPayment LIMIT 1';
          qryPayment.ParamByName('IdPayment').AsString := sIdPayment;
          qryPayment.Open;

          if not qryPayment.IsEmpty then
          begin
            sIdMember := qryPayment.FieldByName('id_member').AsString;
            if (sIdMember = '(NONE)') or (sIdMember = 'NONE') then
              sIdMember := '';
          end;
        end;

        bN8NOk := False;
        bSupaOk := False;

        // 4. Dispatch Channel 1: Legacy n8n Webhook
        try
          JSONN8N := SO();
          JSONN8N.S['ratingcode'] := sRatingCode;
          JSONN8N.S['kodeoutlet'] := APP_OUTLETID;
          JSONN8N.S['idpayment'] := sIdPayment;
          JSONN8N.S['transid'] := sTransId;
          JSONN8N.S['trdetails'] := sTherapistId;
          JSONN8N.S['roomdetails'] := sRoomId;
          JSONN8N.S['tanggal'] := sTanggalStr;
          JSONN8N.S['idmember'] := sIdMember;

          N8NBodyStream := TStringStream.Create(JSONN8N.AsJSON(False, False), TEncoding.UTF8);
          try
            N8NResp := HTTP.Post('https://n8nserver.zenfamilyspa.id/webhook/postzenguestrating', N8NBodyStream, nil, N8NHeaders);
            if (N8NResp <> nil) and (N8NResp.StatusCode in [200, 201, 204]) then
            begin
              bN8NOk := True;
              memLogs.Lines.Add(Format('[RATE-N8N] %s -> n8n SUCCESS (HTTP %d)', [sRatingCode, N8NResp.StatusCode]));
            end
            else
            begin
              memLogs.Lines.Add(Format('[RATE-N8N-WARN] %s -> n8n returned HTTP %d', [sRatingCode, N8NResp.StatusCode]));
            end;
          finally
            N8NBodyStream.Free;
          end;
        except
          on E: Exception do
            memLogs.Lines.Add(Format('[RATE-N8N-ERROR] %s -> n8n failed: %s', [sRatingCode, E.Message]));
        end;

        // 5. Dispatch Channel 2: Supabase (ot_pos_guest_rating)
        try
          JSONSupa := SO();
          JSONSupa.S['kode_outlet'] := APP_OUTLETID;
          JSONSupa.S['ratingcode'] := sRatingCode;
          JSONSupa.S['id_payment'] := sIdPayment;
          JSONSupa.S['trans_id'] := sTransId;
          JSONSupa.S['tanggal'] := sTanggalStr;

          if sKodeKaryawan <> '' then
            JSONSupa.S['kodekaryawan'] := sKodeKaryawan
          else
            JSONSupa.Null['kodekaryawan'] := jNull;

          if sIdMember <> '' then
            JSONSupa.S['user_uid'] := sIdMember
          else
            JSONSupa.Null['user_uid'] := jNull;

          if sRoomId <> '' then
            JSONSupa.S['room_id'] := sRoomId
          else
            JSONSupa.Null['room_id'] := jNull;

          JSONSupa.S['isupload'] := 'Y';
          JSONSupa.S['uploadtime'] := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);

          SupaBodyStream := TStringStream.Create(JSONSupa.AsJSON(False, False), TEncoding.UTF8);
          try
            SupaResp := HTTP.Post(SUPABASE_URL + 'ot_pos_guest_rating?on_conflict=ratingcode', SupaBodyStream, nil, SupaHeaders);
            if (SupaResp <> nil) and (SupaResp.StatusCode in [200, 201, 204]) then
            begin
              bSupaOk := True;
              memLogs.Lines.Add(Format('[RATE-SUPA] %s -> Supabase SUCCESS (HTTP %d)', [sRatingCode, SupaResp.StatusCode]));
            end
            else
            begin
              memLogs.Lines.Add(Format('[RATE-SUPA-WARN] %s -> Supabase returned HTTP %d: %s', [sRatingCode, SupaResp.StatusCode, SupaResp.ContentAsString]));
            end;
          finally
            SupaBodyStream.Free;
          end;
        except
          on E: Exception do
            memLogs.Lines.Add(Format('[RATE-SUPA-ERROR] %s -> Supabase failed: %s', [sRatingCode, E.Message]));
        end;

        // 6. Update local DB flag when at least one destination succeeded (or both)
        if bN8NOk or bSupaOk then
        begin
          qryUpdate.Close;
          qryUpdate.SQL.Text := 
            'UPDATE ben_guest_rating SET isupload = ''Y'', uploadtime = NOW() WHERE ratingcode = :RatingCode';
          qryUpdate.ParamByName('RatingCode').AsString := sRatingCode;
          qryUpdate.ExecSQL;
          Inc(ProcessedCount);
          memLogs.Lines.Add(Format('[RATE-SYNC] %s successfully flagged as uploaded in local MySQL.', [sRatingCode]));
        end
        else
        begin
          memLogs.Lines.Add(Format('[RATE-SYNC-HOLD] %s preserved with isupload=''N'' for retry on next cycle.', [sRatingCode]));
        end;

      except
        on E: Exception do
          memLogs.Lines.Add(Format('[RATE-ROW-ERROR] Error processing ratingcode %s: %s', [sRatingCode, E.Message]));
      end;

      qryLocal.Next;
    end;

    if ProcessedCount > 0 then
      memLogs.Lines.Add(Format('[RATE-SYNC] Completed cycle: %d rating record(s) synced.', [ProcessedCount]));

  finally
    qryLocal.Free;
    qryMaster.Free;
    qryPayment.Free;
    qryUpdate.Free;
    HTTP.Free;
  end;
end;
