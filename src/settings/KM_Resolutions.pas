unit KM_Resolutions;

{$I KaM_Remake.inc}
interface

//uses ptcgraph;

type
  TKMScreenRes = record
    Width, Height, RefRate: SmallInt;
  end;

  TKMScreenResIndex = record
    ResId, RefId: Integer; // Allow for -1, when index not found
  end;

  // Store resolution and list of its allowed refresh rates
  TKMScreenResData = record
    Width, Height: Word;
    RefRateCount: Integer;
    RefRate: array of Word;
  end;

  TKMResolutions = class
  private
    fCount: Integer;
    fItems: array of TKMScreenResData;
    fNeedsRestoring: Boolean;

    function GetItem(aIndex: Integer): TKMScreenResData;
    procedure ReadAvailable;
    procedure Sort;
    function SupportedRes(aWidth, aHeight, aRate, aBPP: Word): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Restore; //restores resolution used before program was started

    property Count: Integer read fCount; //Used by UI
    property Items[aIndex: Integer]: TKMScreenResData read GetItem; //Used by UI

    function IsValid(const aResolution: TKMScreenRes): Boolean; //Check, if resolution is correct
    function FindCorrect(const aResolution: TKMScreenRes): TKMScreenRes; //Try to find correct resolution
    function GetResolutionIDs(const aResolution: TKMScreenRes): TKMScreenResIndex;  //prepares IDs for TMainSettings
    procedure SetResolution(const aResolution: TKMScreenRes); //Apply the resolution
  end;


implementation
uses
  Math,
  {$IFDEF MSWindows} Windows, {$ENDIF}
  KM_Defaults;


{ TKMResolutions }
constructor TKMResolutions.Create;
begin
  inherited;

  ReadAvailable;
  Sort;
end;


destructor TKMResolutions.Destroy;
begin
  Restore;

  inherited;
end;


function TKMResolutions.SupportedRes(aWidth, aHeight, aRate, aBPP: Word): Boolean;
begin
  Result := (aBPP = 32) and (aWidth > aHeight)
    and (aWidth >= MIN_RESOLUTION_WIDTH)
    and (aHeight >= MIN_RESOLUTION_HEIGHT)
    and (aRate > 0);
end;


procedure TKMResolutions.ReadAvailable;
//{$IFDEF MSWindows}
var
  I, M, N: Integer;
//{$ENDIF}
begin
  //{$IFDEF MSWindows}
  //Use PTCGraph
  SetLength(fItems, 3);
  N := 0;
  fItems[N].Width := 1366;
  fItems[N].Height := 768;
  fItems[N].RefRateCount := 1;
  SetLength(fItems[N].RefRate, 1);
  fItems[N].RefRate[0] := 60;
  N := 1;
  fItems[N].Width := 1680;
  fItems[N].Height := 1050;
  fItems[N].RefRateCount := 1;
  SetLength(fItems[N].RefRate, 1);
  fItems[N].RefRate[0] := 60;
  N := 2;
  fItems[N].Width := 1600;
  fItems[N].Height := 900;
  fItems[N].RefRateCount := 1;
  SetLength(fItems[N].RefRate, 1);
  fItems[N].RefRate[0] := 60;
  fCount := 3;
end;


procedure TKMResolutions.Sort;
var
  I, J, K: Integer;
  tempScreenResData: TKMScreenResData;
  tempRefRate: Word;
begin
  for I := 0 to fCount - 1 do
  begin
    for J := 0 to fItems[I].RefRateCount - 1 do
    begin
      //firstly, refresh rates for each resolution are being sorted
      K:=J;  //iterator will be modified, but we don't want to lose it
      while ((K>0) and (fItems[I].RefRate[K] < fItems[I].RefRate[K-1]) and
           //excluding zero values from sorting, so they are kept at the end of array
             (fItems[I].RefRate[K] > 0)) do
      begin
        //Exchange places
        tempRefRate := fItems[I].RefRate[K];
        fItems[I].RefRate[K] := fItems[I].RefRate[K-1];
        fItems[I].RefRate[K-1] := tempRefRate;
        dec(K);
      end;
    end;

    if I = 0 then Continue;
    J := I;  //iterator will be modified, but we don't want to lose it
    //moving resolution to its final position
    while ((J>0) and (((fItems[J].Width < fItems[J-1].Width) and
         //excluding zero values from sorting, so they are kept at the end of array
           (fItems[J].Width > 0) and (fItems[J].Height > 0)) or
           ((fItems[J].Width = fItems[J-1].Width) and
           (fItems[J].Height < fItems[J-1].Height)))) do
    begin
      //Exchange places
      tempScreenResData := fItems[J];
      fItems[J] := fItems[J-1];
      fItems[J-1] := tempScreenResData;
      dec(J);
    end;
  end;
end;


function TKMResolutions.GetItem(aIndex: Integer): TKMScreenResData;
begin
  Assert(InRange(aIndex, 0, fCount - 1));
  Result := fItems[aIndex];
end;


procedure TKMResolutions.Restore;
begin
  if not fNeedsRestoring then Exit;
  //TODO: set resolution via SDL
  //ChangeDisplaySettings(DEVMODE(nil^), 0);
  fNeedsRestoring := False;
end;


function TKMResolutions.IsValid(const aResolution: TKMScreenRes): Boolean;
begin
  Result := GetResolutionIDs(aResolution).RefID <> -1;
end;


procedure TKMResolutions.SetResolution(const aResolution: TKMScreenRes);

begin
  //Double-check anything we get from outside
  Assert(IsValid(aResolution));

//  TODO: set resolution via SDL
//  ZeroMemory(@deviceMode, SizeOf(deviceMode));
//  with deviceMode do
//  begin
//    dmSize := SizeOf(TDeviceMode);
//    dmPelsWidth := aResolution.Width;
//    dmPelsHeight := aResolution.Height;
//    dmBitsPerPel := 32;
//    dmDisplayFrequency := aResolution.RefRate;
//    dmFields := DM_DISPLAYFREQUENCY or DM_BITSPERPEL or DM_PELSWIDTH or DM_PELSHEIGHT;
//  end;
//
//  ChangeDisplaySettings(deviceMode, CDS_FULLSCREEN);
//
  fNeedsRestoring := True; //Resolution was changed so we must restore it when we exit
end;


function TKMResolutions.FindCorrect(const aResolution: TKMScreenRes): TKMScreenRes;
{$IFDEF MSWindows}
var
  devMode: TDevMode;
{$ENDIF}
begin
  //1. Try to reuse current resolution
  //PTCGraph

  //2. Try to use first available resolution
  if fCount > 0 then
  begin
    Result.Width := fItems[0].Width;
    Result.Height := fItems[0].Height;
    Result.RefRate := fItems[0].RefRate[0];
  end
  else
  //3. Fallback to windowed mode
  begin
    Result.Width := -1;
    Result.Height := -1;
    Result.RefRate := -1;
  end;
end;


//we need to set this IDs in settings, so we don't work on "physical" values
//and everything is kept inside this class, not in TMainSettings
function TKMResolutions.GetResolutionIDs(const aResolution: TKMScreenRes): TKMScreenResIndex;
var
  I, J: Integer;
begin
  Result.ResID := -1;
  Result.RefID := -1;

  for I := 0 to fCount - 1 do
    if (fItems[I].Width = aResolution.Width)
    and (fItems[I].Height = aResolution.Height) then
      for J := 0 to fItems[I].RefRateCount - 1 do
        if fItems[I].RefRate[J] = aResolution.RefRate then
        begin
          Result.ResID := I;
          Result.RefID := J;
          Exit;
        end;
end;


end.
