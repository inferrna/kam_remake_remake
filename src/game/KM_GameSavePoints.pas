unit KM_GameSavePoints;
{$I KaM_Remake.inc}
interface
uses
  Generics.Collections,
  KM_CommonClasses, KM_WorkerThread;

type
  TKMSavePoint = class
  private
    fStream: TKMemoryStream;
    fTick: Cardinal;
    // Opened spectator menu, viewports position etc...
  public
    constructor Create(aStream: TKMemoryStream; aTick: Cardinal);
    destructor Destroy(); override;

    property Stream: TKMemoryStream read fStream;
    property Tick: Cardinal read fTick;
  end;

  TKMSavePointCollection = class
  private
    fSavePoints: TDictionary<Cardinal, TKMSavePoint>;
    //Properties to restore after load saved replay
    fLastTick: Cardinal;

    function GetCount(): Integer;
    function GetSavePoint(aTick: Cardinal): TKMSavePoint;
    function GetStream(aTick: Cardinal): TKMemoryStream;
  public
    constructor Create();
    destructor Destroy; override;

    property LastTick: Cardinal read fLastTick write fLastTick;
    procedure Clear;

    property Count: Integer read GetCount;
    property SavePoint[aTick: Cardinal]: TKMSavePoint read GetSavePoint;
    property Stream[aTick: Cardinal]: TKMemoryStream read GetStream; default;
    function Contains(aTick: Cardinal): Boolean;
    procedure FillTicks(aTicksList: TList<Cardinal>);

    procedure NewSavePoint(aStream: TKMemoryStream; aTick: Cardinal);

    procedure Save(aSaveStream: TKMemoryStream);
    procedure Load(aLoadStream: TKMemoryStream);

    procedure SaveToFileAsync(const aFileName: UnicodeString; aWorkerThread: TKMWorkerThread);
    procedure LoadFromFile(const aFileName: UnicodeString);
  end;

implementation
uses
  SysUtils, Classes;

{ TKMSavedReplays }
constructor TKMSavePointCollection.Create();
begin
  inherited;

  fSavePoints := TDictionary<Cardinal, TKMSavePoint>.Create();
  fLastTick := 0;
end;


destructor TKMSavePointCollection.Destroy();
begin
  Clear;
  fSavePoints.Free; // TKMList will free all objects of the list

  inherited;
end;


function TKMSavePointCollection.GetCount(): Integer;
begin
  Result := fSavePoints.Count;
end;


procedure TKMSavePointCollection.Clear;
var
  Replay: TKMSavePoint;
begin
  for Replay in fSavePoints.Values do
    Replay.Free;

  fSavePoints.Clear;
end;


function TKMSavePointCollection.Contains(aTick: Cardinal): Boolean;
begin
  Result := fSavePoints.ContainsKey(aTick);
end;


procedure TKMSavePointCollection.FillTicks(aTicksList: TList<Cardinal>);
var
  Tick: Cardinal;
begin
  for Tick in fSavePoints.Keys do
    aTicksList.Add(Tick);
end;


function TKMSavePointCollection.GetSavePoint(aTick: Cardinal): TKMSavePoint;
begin
  Result := nil;
  if fSavePoints.ContainsKey(aTick) then
    Result := fSavePoints[aTick];
end;


function TKMSavePointCollection.GetStream(aTick: Cardinal): TKMemoryStream;
var
  Rpl: TKMSavePoint;
begin
  Result := nil;
  if fSavePoints.TryGetValue(aTick, Rpl) then
    Result := Rpl.Stream;
end;


procedure TKMSavePointCollection.NewSavePoint(aStream: TKMemoryStream; aTick: Cardinal);
begin
  fSavePoints.Add(aTick, TKMSavePoint.Create(aStream, aTick) );
end;


procedure TKMSavePointCollection.Save(aSaveStream: TKMemoryStream);
var
  keyArray : TArray<Cardinal>;
  key: Cardinal;
  rpl: TKMSavePoint;
begin
  aSaveStream.PlaceMarker('SavedReplays');
  aSaveStream.Write(fLastTick);
  aSaveStream.Write(fSavePoints.Count);

  keyArray := fSavePoints.Keys.ToArray;
  TArray.Sort<Cardinal>(keyArray);

  for key in keyArray do
  begin
    aSaveStream.PlaceMarker('SavePoint');
    aSaveStream.Write(key);
    rpl := fSavePoints.Items[key];
    aSaveStream.Write(Cardinal(rpl.fStream.Size));
    aSaveStream.CopyFrom(rpl.fStream, 0);
  end;
end;


procedure TKMSavePointCollection.SaveToFileAsync(const aFileName: UnicodeString; aWorkerThread: TKMWorkerThread);
var
  S: TKMemoryStreamBinary;
begin
  S := TKMemoryStreamBinary.Create;
  Save(S);
  TKMemoryStream.AsyncSaveToFileCompressedAndFree(S, aFileName, 'SavedReplaysCompressed', aWorkerThread);
end;


procedure TKMSavePointCollection.LoadFromFile(const aFileName: UnicodeString);
var
  S: TKMemoryStreamBinary;
begin
  if not FileExists(aFileName) then Exit;

  S := TKMemoryStreamBinary.Create;
  try
    S.LoadFromFileCompressed(aFileName, 'SavedReplaysCompressed');
    Load(S);
  finally
    S.Free;
  end;
end;


procedure TKMSavePointCollection.Load(aLoadStream: TKMemoryStream);
var
  I, cnt: Integer;
  tick, size: Cardinal;
  rpl: TKMSavePoint;
  stream: TKMemoryStream;
begin
  fSavePoints.Clear;

  aLoadStream.CheckMarker('SavedReplays');
  aLoadStream.Read(fLastTick);
  aLoadStream.Read(cnt);

  for I := 0 to cnt - 1 do
  begin
    aLoadStream.CheckMarker('SavePoint');
    aLoadStream.Read(tick);
    aLoadStream.Read(size);

    stream := TKMemoryStreamBinary.Create;
    stream.CopyFrom(aLoadStream, size);

    rpl := TKMSavePoint.Create(stream, tick);

    fSavePoints.Add(tick, rpl);
  end;
end;


{ TKMSavedReplay }
constructor TKMSavePoint.Create(aStream: TKMemoryStream; aTick: Cardinal);
begin
  inherited Create;

  fStream := aStream;
  fTick := aTick;
end;


destructor TKMSavePoint.Destroy();
begin
  fStream.Free;

  inherited;
end;


end.
