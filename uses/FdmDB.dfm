object dmDB: TdmDB
  OldCreateOrder = False
  OnCreate = DataModuleCreate
  Height = 408
  Width = 725
  object dbInternal: TMyConnection
    Options.OptimizedBigInt = True
    Pooling = True
    LoginPrompt = False
    Left = 40
    Top = 168
  end
  object dbExternal: TMyConnection
    Left = 40
    Top = 88
  end
  object vRequest: TRESTRequest
    Client = vClient
    Params = <>
    Response = vResponse
    SynchronizedEvents = False
    Left = 221
    Top = 64
  end
  object vPOST: TRESTRequest
    Client = vClient
    Method = rmPOST
    Params = <>
    Response = vResponse
    SynchronizedEvents = False
    Left = 500
    Top = 68
  end
  object vClient: TRESTClient
    Accept = 'application/json, text/plain; q=0.9, text/html;q=0.8,'
    AcceptCharset = 'UTF-8, *;q=0.8'
    BaseURL = 'https://member.zenfamilyspa.net/api/pointmembers'
    Params = <>
    HandleRedirects = True
    RaiseExceptionOn500 = False
    Left = 164
    Top = 112
  end
  object vResponse: TRESTResponse
    RootElement = 'data'
    Left = 164
    Top = 164
  end
  object vPUT: TRESTRequest
    Client = vClient
    Method = rmPUT
    Params = <>
    Response = vResponse
    SynchronizedEvents = False
    Left = 440
    Top = 64
  end
  object vDELETE: TRESTRequest
    Client = vClient
    Method = rmDELETE
    Params = <>
    Response = vResponse
    SynchronizedEvents = False
    Left = 304
    Top = 64
  end
  object vPATCH: TRESTRequest
    Client = vClient
    Method = rmPATCH
    Params = <>
    Response = vResponse
    SynchronizedEvents = False
    Left = 380
    Top = 64
  end
end
