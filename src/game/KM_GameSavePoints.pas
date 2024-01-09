unit KM_GameSavePoints;
{$I KaM_Remake.inc}
interface
uses
  SyncObjs, Generics.Collections,
  KM_CommonClasses, KM_WorkerThread
  {$IFDEF FPC}
  {$IFDEF UNIX}
  , KM_CommonUtils
  {$ENDIF}
  , KM_Sort
  {$ENDIF}
  ;

type
  TKMSavePoint = class
  private
    fStreamCompressed: TKMemoryStream; // Compressed stream of a game save (save point)
    fTick: Cardinal;
    // Opened spectator menu, viewports position etc...
  public
    constructor Create(aStream: TKMemoryStream; aTick: Cardinal);
    destructor Destroy; override;

    property StreamCompressed: TKMemoryStream read fStreamCompressed;
    property Tick: Cardinal read fTick;
  end;

  TKMSavePointCollection = class
  private
    fAsyncThreadsCnt: longint; //Number of worker threads working atm. Used to make saves or create compressed savepoints
    fWaitCS: TCriticalSection;
    fSaveCS: TCriticalSection;
    fSavePoints: TDictionary<Cardinal, TKMSavePoint>;
    //Properties to restore after load saved replay
    fLastTick: Cardinal;

    function GetCount: Integer;
    function GetSavePoint(aTick: Cardinal): TKMSavePoint;
    function GetStream(aTick: Cardinal): TKMemoryStream;
    function GetLastTick: Cardinal;
    procedure SetLastTick(const aLastTick: Cardinal);

    procedure NewSavePointAndFree(aStream: TKMemoryStream; aTick: Cardinal);

    procedure SaveToFile(aFileName: UnicodeString);
  public
    constructor Create;
    destructor Destroy; override;

    property LastTick: Cardinal read GetLastTick write SetLastTick;
    procedure Clear;

    procedure Lock;
    procedure Unlock;

    property Count: Integer read GetCount;
    property SavePoint[aTick: Cardinal]: TKMSavePoint read GetSavePoint;
    property Stream[aTick: Cardinal]: TKMemoryStream read GetStream; default;
    function Contains(aTick: Cardinal): Boolean;
    procedure FillTicks(aTicksList: TList<Cardinal>);

    procedure NewSavePointAsyncAndFree(var aStream: TKMemoryStream; aTick: Cardinal; aWorkerThread: TKMWorkerThread);

    function LatestPointTickBefore(aTick: Cardinal): Cardinal;

    procedure Save(aSaveStream: TKMemoryStream);
    procedure Load(aLoadStream: TKMemoryStream);

    procedure SaveToFileAsync(const aFileName: UnicodeString; aWorkerThread: TKMWorkerThread);
    procedure LoadFromFile(const aFileName: UnicodeString);
  end;


implementation
uses
  SysUtils, Classes;


type
  NewSavePointAndFreeProcType = procedure(aStream: TKMemoryStream; aTick: Cardinal) of object;

  NewSavePointAndFreeTask = class(TKMWorkerThreadTaskBase)
  private
    Proc: NewSavePointAndFreeProcType;
    Stream: TKMemoryStream;
    Tick: Cardinal;
  public
    constructor Create(aProc: NewSavePointAndFreeProcType; aStream: TKMemoryStream; aTick: Cardinal); overload;

    procedure exec; override;
  end;

  SaveToFileProcType = procedure(aFileName: UnicodeString) of object;

  SaveToFileTask = class(TKMWorkerThreadTaskBase)
  private
    Proc: SaveToFileProcType;
    FileName: UnicodeString;
  public
    constructor Create(aProc: SaveToFileProcType; aFileName: UnicodeString);

    procedure exec;
  end;


{ TKMSavePoint }
constructor TKMSavePoint.Create(aStream: TKMemoryStream; aTick: Cardinal);
begin
  inherited Create;

  fStreamCompressed := aStream;
  fTick := aTick;
end;


destructor TKMSavePoint.Destroy;
begin
  fStreamCompressed.Free;

  inherited;
end;


{ TKMSavePointCollection }
constructor TKMSavePointCollection.Create;
begin
  inherited;

  fSaveCS := TCriticalSection.Create;
  fWaitCS := TCriticalSection.Create;
  fSavePoints := TDictionary<Cardinal, TKMSavePoint>.Create;
  fLastTick := 0;
end;


destructor TKMSavePointCollection.Destroy;
begin
  {$IFDEF WDC}
  // Wait till all threads release waitLock
  while True do
  begin
    fWaitCS.Enter;
    try
      if fAsyncThreadsCnt = 0 then
        Break;
    finally
      fWaitCS.Leave;
    end;
    Sleep(100);
  end;
  {$ENDIF}

  Lock; // Lock even in destructor
  try
    Clear;
    fSavePoints.Free; // TKMList will free all objects of the list
  finally
    Unlock;
  end;
  fSaveCS.Free;
  fWaitCS.Free;

  inherited;
end;


function TKMSavePointCollection.GetCount: Integer;
begin
  if Self = nil then Exit(0);

  Lock;
  try
    Result := fSavePoints.Count;
  finally
    Unlock;
  end;
end;


function TKMSavePointCollection.GetLastTick: Cardinal;
begin
  if Self = nil then Exit(0);

  Result := fLastTick;
end;


procedure TKMSavePointCollection.SetLastTick(const aLastTick: Cardinal);
begin
  if Self = nil then Exit;

  fLastTick := aLastTick;
end;


procedure TKMSavePointCollection.Clear;
var
  savePoint: TKMSavePoint;
begin
  if Self = nil then Exit;

  Lock;
  try
    for savePoint in fSavePoints.Values do
      savePoint.Free;

    fSavePoints.Clear;
  finally
    Unlock;
  end;
end;


function TKMSavePointCollection.Contains(aTick: Cardinal): Boolean;
begin
  if Self = nil then Exit(False);

  Lock;
  try
    Result := fSavePoints.ContainsKey(aTick);
  finally
    Unlock;
  end;
end;


procedure TKMSavePointCollection.FillTicks(aTicksList: TList<Cardinal>);
var
  Tick: Cardinal;
begin
  if Self = nil then Exit;

  Lock;
  try
    for Tick in fSavePoints.Keys do
      aTicksList.Add(Tick);
  finally
    Unlock;
  end;
end;


function TKMSavePointCollection.GetSavePoint(aTick: Cardinal): TKMSavePoint;
begin
  Result := nil;
  if Self = nil then Exit;

  Lock;
  try
    if fSavePoints.ContainsKey(aTick) then
      Result := fSavePoints[aTick];
  finally
    Unlock;
  end;
end;


function TKMSavePointCollection.GetStream(aTick: Cardinal): TKMemoryStream;
var
  savePoint: TKMSavePoint;
begin
  Result := nil;
  if Self = nil then Exit;

  Lock;
  try
    if fSavePoints.TryGetValue(aTick, savePoint) then
      Result := savePoint.StreamCompressed;
  finally
    Unlock;
  end;
end;


constructor NewSavePointAndFreeTask.Create(aProc: NewSavePointAndFreeProcType; aStream: TKMemoryStream; aTick: Cardinal);
begin
  inherited Create('NewSavePointAsyncAndFree');

  Proc := aProc;
  Stream := aStream;
  Tick := aTick;
end;


procedure NewSavePointAndFreeTask.exec;
begin
  Proc(Stream, Tick);
end;


procedure TKMSavePointCollection.NewSavePointAndFree(aStream: TKMemoryStream; aTick: Cardinal);
var
  S: TKMemoryStream;
begin
  S := TKMemoryStreamBinary.Create;
  try
    aStream.SaveToStreamCompressed(S);
  finally
    aStream.Free;
  end;

  // fSavePoints could be accessed by different threads
  Lock;
  try
    fSavePoints.Add(aTick, TKMSavePoint.Create(S, aTick));
  finally
    Unlock;
  end;
  // Decrease thread counter
  AtomicDecrement(fAsyncThreadsCnt);
end;


procedure TKMSavePointCollection.NewSavePointAsyncAndFree(var aStream: TKMemoryStream; aTick: Cardinal; aWorkerThread: TKMWorkerThread);
begin
  // fSavePoints could be accessed by different threads
  Lock;
  try
    // Check if we don't have same tick save here too, since we work in multithread environment
    if fSavePoints.ContainsKey(aTick) then Exit;
  finally
    Unlock;
  end;
  // Increase save threads counter in main thread
  AtomicIncrement(fAsyncThreadsCnt);
  aWorkerThread.Enqueue(NewSavePointAndFreeTask.Create(Self.NewSavePointAndFree, aStream, aTick));
  aStream := nil; //So caller doesn't use it by mistake
end;


{$IFDEF FPC}
function CompareKeys(const aKey1, aKey2): Integer;
var
  k1: Cardinal absolute aKey1;
  k2: Cardinal absolute aKey2;
begin
  if      k1 < k2 then Result := -1
  else if k1 > k2 then Result := +1
  else                 Result :=  0;
end;
{$ENDIF}

procedure TKMSavePointCollection.Save(aSaveStream: TKMemoryStream);
var
  keyArray : TArray<Cardinal>;
  key: Cardinal;
  savePoint: TKMSavePoint;
begin
  if Self = nil then Exit;

  Lock;
  try
    aSaveStream.PlaceMarker('SavePoints');
    aSaveStream.Write(fLastTick);
    aSaveStream.Write(fSavePoints.Count);

    keyArray := fSavePoints.Keys.ToArray;
    {$IFNDEF FPC}
    TArray.Sort<Cardinal>(keyArray);
    {$ELSE}
    SortCustom(keyArray, Low(keyArray), High(keyArray), SizeOf(keyArray[0]), CompareKeys);
    {$ENDIF}

    // todo: potential OutOfMemory error in this cycle
    for key in keyArray do
    begin
      aSaveStream.PlaceMarker('SavePoint');
      aSaveStream.Write(key);
      savePoint := fSavePoints.Items[key];
      aSaveStream.Write(Cardinal(savePoint.fStreamCompressed.Size));
      aSaveStream.CopyFrom(savePoint.fStreamCompressed, 0);
    end;
  finally
    Unlock;
  end;
end;


procedure TKMSavePointCollection.SaveToFile(aFileName: UnicodeString);
var
  localStream: TKMemoryStream;
begin
  localStream := TKMemoryStreamBinary.Create;
  try
    Save(localStream); // Save has Lock / Unlock inside already
    // Decrease thread counter since we saved all data into thread local stream
    AtomicDecrement(fAsyncThreadsCnt);
    localStream.SaveToFile(aFileName);
  finally
    localStream.Free;
  end;
end;


constructor SaveToFileTask.Create(aProc: SaveToFileProcType; aFileName: UnicodeString);
begin
  inherited Create('Save SavePoints');

  Proc := aProc;
  FileName := aFileName;
end;


procedure SaveToFileTask.exec;
begin
  Proc(FileName);
end;


procedure TKMSavePointCollection.SaveToFileAsync(const aFileName: UnicodeString; aWorkerThread: TKMWorkerThread);
begin
  if Self = nil then Exit;
   // Increase save threads counter in main thread
  AtomicIncrement(fAsyncThreadsCnt);
  aWorkerThread.Enqueue(SaveToFileTask.Create(Self.SaveToFile, aFileName));
end;


procedure TKMSavePointCollection.Lock;
begin
  if Self = nil then Exit;

  fSaveCS.Enter;
end;


procedure TKMSavePointCollection.Unlock;
begin
  if Self = nil then Exit;

  fSaveCS.Leave;
end;


procedure TKMSavePointCollection.LoadFromFile(const aFileName: UnicodeString);
var
  S: TKMemoryStream;
begin
  if Self = nil then Exit;
  if not FileExists(aFileName) then Exit;

  S := TKMemoryStreamBinary.Create;
  try
    S.LoadFromFile(aFileName);
    Load(S);
  finally
    S.Free;
  end;
end;


// Get latest savepoint tick, before aTick
// 0 - if not found
function TKMSavePointCollection.LatestPointTickBefore(aTick: Cardinal): Cardinal;
var
  key: Cardinal;
begin
  Result := 0;
  if Self = nil then Exit;

  Lock;
  try
    for key in fSavePoints.Keys do
      if (key <= aTick) and (key > Result) then
        Result := key;
  finally
    Unlock;
  end;
end;

procedure TKMSavePointCollection.Load(aLoadStream: TKMemoryStream);
var
  I, cnt: Integer;
  tick, size: Cardinal;
  savePoint: TKMSavePoint;
  stream: TKMemoryStream;
begin
  if Self = nil then Exit;

  Lock;
  try
    fSavePoints.Clear;

    aLoadStream.CheckMarker('SavePoints');
    aLoadStream.Read(fLastTick);
    aLoadStream.Read(cnt);

    for I := 0 to cnt - 1 do
    begin
      aLoadStream.CheckMarker('SavePoint');
      aLoadStream.Read(tick);
      aLoadStream.Read(size);

      stream := TKMemoryStreamBinary.Create;
      stream.CopyFrom(aLoadStream, size);

      savePoint := TKMSavePoint.Create(stream, tick);

      fSavePoints.Add(tick, savePoint);
    end;
  finally
    Unlock;
  end;
end;


end.
