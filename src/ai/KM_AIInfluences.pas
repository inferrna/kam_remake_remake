unit KM_AIInfluences;
{$I KaM_Remake.inc}
interface
uses
  Math,
  KM_CommonClasses, KM_CommonTypes, KM_Defaults, KM_Points,
  KM_Units, KM_UnitGroups,
  KM_NavMesh, KM_NavMeshInfluences,
  KM_NavMeshFloodFill;


const
  // Avoid bulding values of specific actions (tile lock by specific action)
  AVOID_BUILDING_UNLOCK = 0;
  AVOID_BUILDING_HOUSE_OUTSIDE_LOCK = 30;
  AVOID_BUILDING_HOUSE_INSIDE_LOCK = 40;
  AVOID_BUILDING_NODE_LOCK_ROAD = 45;
  AVOID_BUILDING_NODE_LOCK_FIELD = 50;
  AVOID_BUILDING_FOREST_RANGE = 150; // Value: 255 <-> AVOID_BUILDING_FOREST_VARIANCE which may forest tiles have
  AVOID_BUILDING_FOREST_MINIMUM = 255 - AVOID_BUILDING_FOREST_RANGE; // Minimum value of forest reservation tiles
  AVOID_BUILDING_COAL_TILE = 254;


type

  //Collection of influence maps
  TKMInfluences = class
  private
    fMapX, fMapY, fPolygons: Word; // Limits of arrays

    fUpdateCityIdx, fUpdateArmyIdx: TKMHandIndex; // Update index
    fPresence: TKMWordArray; // Military presence
    fOwnership: TKMByteArray; // City mark the space around itself
    fAreas: TKMByte2Array;

    fFloodFill: TKMInfluenceFloodFill;
    fInfluenceSearch: TNavMeshInfluenceSearch;
    fNavMesh: TKMNavMesh;

    // Avoid building
    procedure InitAvoidBuilding();
    // Army presence
    function GetPresence(const aPL: TKMHandIndex; const aIdx: Word; const aGT: TGroupType): Word; inline;
    procedure SetPresence(const aPL: TKMHandIndex; const aIdx: Word; const aGT: TGroupType; const aPresence: Word); inline;
    procedure SetIncPresence(const aPL: TKMHandIndex; const aIdx: Word; const aGT: TGroupType; const aPresence: Word); inline;
    function GetAllPresences(const aPL: TKMHandIndex; const aIdx: Word): Word; inline;
    function GetEnemyGroupPresence(const aPL: TKMHandIndex; const aIdx: Word; const aGT: TGroupType): Word;
    //function GetAlliancePresence(const aPL: TKMHandIndex; aIdx: Word; const aAllianceType: TAllianceType): Word;
    procedure UpdateMilitaryPresence(const aPL: TKMHandIndex);
    // City influence
    function GetOwnership(const aPL: TKMHandIndex; const aIdx: Word): Byte; inline;
    procedure SetOwnership(const aPL: TKMHandIndex; const aIdx: Word; const aOwnership: Byte); inline;
    function GetOwnershipFromPoint(const aPL: TKMHandIndex; const aY, aX: Word): Byte; inline; // For property -> aY, aX are switched!
    procedure SetOwnershipFromPoint(const aPL: TKMHandIndex; const aY, aX: Word; const aOwnership: Byte); inline; // For property -> aY, aX are switched!
    procedure UpdateOwnership(const aPL: TKMHandIndex);
    // Common
    procedure InitArrays();
    function GetAreaEval(const aY,aX: Word): Byte;
  public
    AvoidBuilding: TKMByte2Array; //Common map of areas where building is undesired (around Store, Mines, Woodcutters)

    constructor Create(aNavMesh: TKMNavMesh);
    destructor Destroy(); override;
    procedure Save(SaveStream: TKMemoryStream);
    procedure Load(LoadStream: TKMemoryStream);

    // Avoid building
    // Army presence
    property Presence[const aPL: TKMHandIndex; const aIdx: Word; const aGT: TGroupType]: Word read GetPresence write SetPresence;
    property IncPresence[const aPL: TKMHandIndex; const aIdx: Word; const aGT: TGroupType]: Word write SetIncPresence;
    property PresenceAllGroups[const aPL: TKMHandIndex; const aIdx: Word]: Word read GetAllPresences;
    property EnemyGroupPresence[const aPL: TKMHandIndex; const aIdx: Word; const aGT: TGroupType]: Word read GetEnemyGroupPresence;
    //property AlliancePresence[const aPL: TKMHandIndex; aIdx: Word; const aAllianceType: TAllianceType]: Word read GetAlliancePresence;
    // City influence
    property Ownership[const aPL: TKMHandIndex; const aY,aX: Word]: Byte read GetOwnershipFromPoint write SetOwnershipFromPoint; // To secure compatibility with old AI
    property OwnPoly[const aPL: TKMHandIndex; const aIdx: Word]: Byte read GetOwnership write SetOwnership;
    // Common
    property InfluenceSearch: TNavMeshInfluenceSearch read fInfluenceSearch write fInfluenceSearch;
    property EvalArea[const aY,aX: Word]: Byte read GetAreaEval;

    // Avoid building
    procedure AddAvoidBuilding(aX,aY: Word; aRad: Single; aValue: Byte = 255; aDecreasing: Boolean = False; aDecreaseSpeed: Single = 1);
    procedure RemAvoidBuilding(aArea: TKMRect);
    // Army presence
    // City influence
    function GetBestOwner(const aX,aY: Word): TKMHandIndex; overload;
    function GetBestOwner(const aIdx: Word): TKMHandIndex; overload;
    //function GetAllAllianceOwnership(const aPL: TKMHandIndex; const aX,aY: Word; const aAllianceType: TAllianceType): TKMHandIndexArray;
    function GetBestAllianceOwnership(const aPL: TKMHandIndex; const aIdx: Word; const aAllianceType: TAllianceType): Byte;
    function GetOtherOwnerships(const aPL: TKMHandIndex; const aX, aY: Word): Word;

    procedure AfterMissionInit();
    procedure UpdateState(aTick: Cardinal);
    procedure Paint(aRect: TKMRect);
  end;


implementation
uses
  Classes, Graphics, SysUtils,
  KM_RenderAux, KM_Resource,
  KM_Terrain, KM_Houses, KM_HouseCollection,
  KM_Hand, KM_HandsCollection, KM_ResHouses,
  KM_AIFields;


const
  GROUPS = 4;
  INIT_HOUSE_INFLUENCE = 255;
  MAX_INFLUENCE_DISTANCE = 150;

{ TKMInfluenceMaps }
constructor TKMInfluences.Create(aNavMesh: TKMNavMesh);
begin
  inherited Create();

  fNavMesh := aNavMesh;
  fUpdateCityIdx := 0;
  fUpdateArmyIdx := 0;
  fFloodFill := TKMInfluenceFloodFill.Create(False); // Check if True is better
  fInfluenceSearch := TNavMeshInfluenceSearch.Create(False);
end;


destructor TKMInfluences.Destroy();
begin
  fFloodFill.Free;
  fInfluenceSearch.Free;
  inherited;
end;


procedure TKMInfluences.Save(SaveStream: TKMemoryStream);
var
  PCount: Word;
  Y, Len: Integer;
begin
  PCount := gHands.Count;

  SaveStream.WriteA('Influences');
  SaveStream.Write(PCount);
  SaveStream.Write(fMapX);
  SaveStream.Write(fMapY);
  SaveStream.Write(fPolygons);
  SaveStream.Write(fUpdateCityIdx);
  SaveStream.Write(fUpdateArmyIdx);

  SaveStream.WriteA('AvoidBuilding');
  for Y := 0 to fMapY - 1 do
    SaveStream.Write(AvoidBuilding[Y,0], fMapX * SizeOf(AvoidBuilding[0,0]));

  SaveStream.WriteA('Ownership');
  Len := Length(fOwnership);
  SaveStream.Write(Len);
  SaveStream.Write(fOwnership[0], SizeOf(fOwnership[0]) * Len);

  SaveStream.WriteA('ArmyPresence');
  Len := Length(fPresence);
  SaveStream.Write(Len);
  SaveStream.Write(fPresence[0], SizeOf(fPresence[0]) * Len);

  SaveStream.WriteA('AreasEvaluation');
  for Y := 0 to fMapY - 1 do
    SaveStream.Write(fAreas[Y,0], fMapX * SizeOf(fAreas[0,0]));
  //Len := Length(fAreas);
  //SaveStream.Write(Len);
  //SaveStream.Write(fAreas[0], SizeOf(fAreas[0]) * Len);
end;


procedure TKMInfluences.Load(LoadStream: TKMemoryStream);
var
  PCount: Word;
  Y, Len: Integer;
begin
  LoadStream.ReadAssert('Influences');
  LoadStream.Read(PCount);
  LoadStream.Read(fMapX);
  LoadStream.Read(fMapY);
  LoadStream.Read(fPolygons);
  LoadStream.Read(fUpdateCityIdx);
  LoadStream.Read(fUpdateArmyIdx);

  LoadStream.ReadAssert('AvoidBuilding');
  SetLength(AvoidBuilding, fMapY, fMapX);
  for Y := 0 to fMapY - 1 do
    LoadStream.Read(AvoidBuilding[Y,0], fMapX * SizeOf(AvoidBuilding[0,0]));

  LoadStream.ReadAssert('Ownership');
  LoadStream.Read(Len);
  SetLength(fOwnership, Len);
  LoadStream.Read(fOwnership[0], SizeOf(fOwnership[0]) * Len);

  LoadStream.ReadAssert('ArmyPresence');
  LoadStream.Read(Len);
  SetLength(fPresence, Len);
  LoadStream.Read(fPresence[0], SizeOf(fPresence[0]) * Len);

  LoadStream.ReadAssert('AreasEvaluation');
  SetLength(fAreas, fMapY, fMapX);
  for Y := 0 to fMapY - 1 do
    LoadStream.Read(fAreas[Y,0], fMapX * SizeOf(fAreas[0,0]));
  //LoadStream.Read(Len);
  //SetLength(fAreas, Len);
  //LoadStream.Read(fAreas[0], SizeOf(fAreas[0]) * Len);
end;




//Make the area around to be avoided by common houses
procedure TKMInfluences.AddAvoidBuilding(aX,aY: Word; aRad: Single; aValue: Byte = 255; aDecreasing: Boolean = False; aDecreaseSpeed: Single = 1);
var
  X,Y: Integer;
  Dist, MaxDist: Single;
begin
  if (aRad = 0) then
    Exit;
  MaxDist := Sqr(aRad);
  for Y := Max(aY - Ceil(aRad), 1) to Min(aY + Ceil(aRad), fMapY - 1) do
  for X := Max(aX - Ceil(aRad), 1) to Min(aX + Ceil(aRad), fMapX - 1) do
    if (AvoidBuilding[Y,X] = 0) OR (AvoidBuilding[Y,X] >= AVOID_BUILDING_FOREST_MINIMUM) then // Protect reservation tiles
    begin
      Dist := Sqr(aX-X) + Sqr(aY-Y);
      if (Dist <= MaxDist) then
      begin
        if aDecreasing then
          //AvoidBuilding[Y,X] := Min(AvoidBuilding[Y,X] + Max(0, Round((1 - Dist * MaxDistInv) * aValue)), 255)
          AvoidBuilding[Y,X] := Min(AvoidBuilding[Y,X] + Max(0, Round(aValue - Dist * aDecreaseSpeed)), 255)
        else
          AvoidBuilding[Y,X] := Min(AvoidBuilding[Y,X] + aValue, 255);
      end;
    end;
end;


procedure TKMInfluences.RemAvoidBuilding(aArea: TKMRect);
var
  X,Y: Integer;
begin
  for Y := Max(aArea.Top , 1) to Min(aArea.Bottom, fMapY - 1) do
  for X := Max(aArea.Left, 1) to Min(aArea.Right , fMapX - 1) do
    if (AvoidBuilding[Y,X] = AVOID_BUILDING_COAL_TILE) then // It is not used otherwise anyway
      AvoidBuilding[Y,X] := 0;
end;


//AI should avoid certain areas, keeping them for special houses
procedure TKMInfluences.InitAvoidBuilding();
  procedure CheckAndMarkMine(aX,aY: Integer; aHT: THouseType);
  var
    X,Y,X2,Y2: Integer;
  begin
    for Y := Max(1,aY-3) to Min(fMapY-1,aY-1) do
    for X := Max(1,aX-1) to Min(fMapX-1,aX+1) do
      if   ((aHT = ht_IronMine) AND (gTerrain.TileIsIron(X,Y) > 1))
        OR ((aHT = ht_GoldMine) AND (gTerrain.TileIsGold(X,Y) > 1)) then
      begin
        for Y2 := aY to Min(fMapY-1,aY+1) do
        for X2 := Max(1,aX-2) to Min(fMapX-1,aX+1+Byte(aHT = ht_IronMine)) do
          AvoidBuilding[Y2, X2] := $FF;
        Exit;
      end;
  end;
var
  H: TKMHouse;
  I,X,Y: Integer;
begin
  for Y := 0 to fMapY - 1 do
  for X := 0 to fMapX - 1 do
    AvoidBuilding[Y,X] := 0;

  //Avoid areas where Gold/Iron mines should be
  for Y := 3 to fMapY - 2 do
  for X := 2 to fMapX - 2 do
    if gTerrain.CanPlaceHouse(KMPoint(X,Y), ht_IronMine) then
      CheckAndMarkMine(X,Y, ht_IronMine)
    else if gTerrain.CanPlaceHouse(KMPoint(X,Y), ht_GoldMine) then
      CheckAndMarkMine(X,Y, ht_GoldMine);

  //Avoid Coal fields
  for Y := 1 to fMapY - 1 do
  for X := 1 to fMapX - 1 do
   AvoidBuilding[Y,X] := AvoidBuilding[Y,X] or (Byte(gTerrain.TileIsCoal(X, Y) > 1) * AVOID_BUILDING_COAL_TILE);

  //Leave free space BELOW all players Stores
  for I := 0 to gHands.Count - 1 do
  begin
    H := gHands[I].FindHouse(ht_Store);
    if (H <> nil) then
    for Y := Max(H.Entrance.Y + 1, 1) to Min(H.Entrance.Y + 2, fMapY - 1) do
    for X := Max(H.Entrance.X - 1, 1) to Min(H.Entrance.X + 1, fMapX - 1) do
      AvoidBuilding[Y,X] := AvoidBuilding[Y,X] or $FF;
  end;
end;




function TKMInfluences.GetAllPresences(const aPL: TKMHandIndex; const aIdx: Word): Word;
var
  Idx: Integer;
  GT: TGroupType;
begin
  Result := 0;
  Idx := (aPL*fPolygons + aIdx) shl 2;
  for GT := Low(TGroupType) to High(TGroupType) do
    Result := Min(High(Word), Result + fPresence[Idx + Byte(GT)]);
end;


function TKMInfluences.GetPresence(const aPL: TKMHandIndex; const aIdx: Word; const aGT: TGroupType): Word;
begin
  Result := fPresence[((aPL*fPolygons + aIdx) shl 2) + Byte(aGT)];
end;


procedure TKMInfluences.SetPresence(const aPL: TKMHandIndex; const aIdx: Word; const aGT: TGroupType; const aPresence: Word);
begin
  fPresence[((aPL*fPolygons + aIdx) shl 2) + Byte(aGT)] := aPresence;
end;


procedure TKMInfluences.SetIncPresence(const aPL: TKMHandIndex; const aIdx: Word; const aGT: TGroupType; const aPresence: Word);
var
  Idx: Integer;
begin
  Idx := ((aPL*fPolygons + aIdx) shl 2) + Byte(aGT);
  fPresence[Idx] := fPresence[Idx] + aPresence;
end;


function TKMInfluences.GetEnemyGroupPresence(const aPL: TKMHandIndex; const aIdx: Word; const aGT: TGroupType): Word;
var
  PL: TKMHandIndex;
begin
  Result := 0;
  for PL := 0 to gHands.Count - 1 do
    if gHands[PL].Enabled AND (gHands[aPL].Alliances[PL] = at_Enemy) then
      Result := Result + Presence[PL, aIdx, aGT];
end;


procedure TKMInfluences.UpdateMilitaryPresence(const aPL: TKMHandIndex);
const
  EACH_X_MEMBER_COEF = 10;
  MAX_DISTANCE = 20;
var
  I, K, Cnt: Integer;
  GT: TGroupType;
  G: TKMUnitGroup;
  U: TKMUnit;
  PointArr: TKMWordArray;
begin
  InitArrays();

  SetLength(PointArr,16);
  for I := 0 to fPolygons-1 do
    for GT := Low(TGroupType) to High(TGroupType) do
      Presence[aPL,I,GT] := 0;

  for I := 0 to gHands[aPL].UnitGroups.Count-1 do
  begin
    G := gHands[aPL].UnitGroups.Groups[I];
    if (G = nil) OR G.IsDead then
      continue;
    K := 0;
    Cnt := 0;
    while (K < G.Count) do
    begin
      U := G.Members[K];
      if (U <> nil) AND not U.IsDeadOrDying then
      begin
        if (Length(PointArr) <= Cnt) then
          SetLength(PointArr, Cnt + 16);
        PointArr[Cnt] := gAIFields.NavMesh.KMPoint2Polygon[ U.GetPosition ];
        Cnt := Cnt + 1;
      end;
      K := K + EACH_X_MEMBER_COEF; // Pick each X member (Huge groups cover large areas so be sure that influence will be accurate)
    end;

    if (Cnt > 0) then
      //fFloodFill.MilitaryPresence(aPL, gAIFields.Eye.ArmyEvaluation.GroupStrength(G), MAX_DISTANCE, Cnt-1, G.GroupType, PointArr);
      fFloodFill.MilitaryPresence(aPL, Max(G.Count,30), MAX_DISTANCE, Cnt-1, G.GroupType, PointArr);
  end;
end;






function TKMInfluences.GetOwnership(const aPL: TKMHandIndex; const aIdx: Word): Byte;
begin
  Result := fOwnership[aPL * fPolygons + aIdx];
end;


procedure TKMInfluences.SetOwnership(const aPL: TKMHandIndex; const aIdx: Word; const aOwnership: Byte);
begin
  fOwnership[aPL * fPolygons + aIdx] := aOwnership;
end;


function TKMInfluences.GetOwnershipFromPoint(const aPL: TKMHandIndex; const aY, aX: Word): Byte;
begin
  Result := GetOwnership(aPL, fNavMesh.Point2Polygon[aY,aX]);
end;


procedure TKMInfluences.SetOwnershipFromPoint(const aPL: TKMHandIndex; const aY, aX: Word; const aOwnership: Byte);
begin
  SetOwnership(aPL, fNavMesh.Point2Polygon[aY,aX], aOwnership);
end;


function TKMInfluences.GetBestOwner(const aX,aY: Word): TKMHandIndex;
begin
  Result := GetBestOwner( fNavMesh.Point2Polygon[aY,aX] );
end;


function TKMInfluences.GetBestOwner(const aIdx: Word): TKMHandIndex;
var
  PL: TKMHandIndex;
  Best: Integer;
begin
  Result := PLAYER_NONE;
  if not AI_GEN_INFLUENCE_MAPS OR (aIdx = High(Word)) then
    Exit;

  Best := 0;
  for PL := 0 to gHands.Count - 1 do
    if (OwnPoly[PL,aIdx] > Best) then
    begin
      Best := OwnPoly[PL,aIdx];
      Result := PL;
    end;
end;


//function TKMInfluences.GetAllAllianceOwnership(const aPL: TKMHandIndex; const aX,aY: Word; const aAllianceType: TAllianceType): TKMHandIndexArray;
//var
//  PL: TKMHandIndex;
//  I,K,Idx, Cnt: Integer;
//  Output: TKMHandIndexArray;
//begin
//  SetLength(Result,0);
//  if not AI_GEN_INFLUENCE_MAPS then
//    Exit;
//
//  SetLength(Output, MAX_HANDS);
//  Cnt := 0;
//  Idx := fNavMesh.Point2Polygon[aY,aX];
//  for PL := 0 to gHands.Count - 1 do
//    if (aPL <> PL) AND (gHands[aPL].Alliances[PL] = aAllianceType) AND (OwnPoly[PL,Idx] > 0) then
//    begin
//      Output[Cnt] := OwnPoly[PL,Idx];
//      Cnt := Cnt + 1;
//    end;
//  SetLength(Output, MAX_HANDS);
//  // Sort results by influence (in real game 1 <-> 3 elements)
//  for I := Cnt - 1 downto 0 do
//    for K := 0 to I - 1 do
//      if (OwnPoly[ Output[K],Idx ] < OwnPoly[ Output[K+1],Idx ]) then
//      begin
//        PL := Output[K];
//        Output[K] := Output[K+1];
//        Output[K+1] := K;
//      end;
//  Result := Output;
//end;


function TKMInfluences.GetBestAllianceOwnership(const aPL: TKMHandIndex; const aIdx: Word; const aAllianceType: TAllianceType): Byte;
var
  PL: TKMHandIndex;
begin
  Result := 0;
  if not AI_GEN_INFLUENCE_MAPS then
    Exit;

  for PL := 0 to gHands.Count - 1 do
    if (aPL <> PL) AND (gHands[aPL].Alliances[PL] = aAllianceType) AND (OwnPoly[PL,aIdx] > Result) then
      Result := OwnPoly[PL,aIdx];
end;


function TKMInfluences.GetOtherOwnerships(const aPL: TKMHandIndex; const aX, aY: Word): Word;
var
  PL: TKMHandIndex;
  Idx: Word;
begin
  Result := 0;
  if not AI_GEN_INFLUENCE_MAPS then
    Exit;

  Idx := fNavMesh.Point2Polygon[aY,aX];
  Result := 0;
  for PL := 0 to gHands.Count - 1 do
    if (PL <> aPL) then
      Result := Result + OwnPoly[PL,Idx];
end;


// Here is the main reason for reworking influences: only 1 flood fill for city per a update + ~25x less elements in array
procedure TKMInfluences.UpdateOwnership(const aPL: TKMHandIndex);
var
  I, Idx, Cnt: Integer;
  H: TKMHouse;
  IdxArray: TKMWordArray;
begin
  InitArrays();

  //Clear array (again is better to clear less than 2000 polygons instead of 255*255 tiles)
  for Idx := 0 to fPolygons - 1 do
    OwnPoly[aPL, Idx] := 0;

  // Create array of polygon indexes
  SetLength(IdxArray, gHands[aPL].Houses.Count);
  Cnt := 0;
  for I := 0 to gHands[aPL].Houses.Count - 1 do
  begin
    H := gHands[aPL].Houses[I];
    if not H.IsDestroyed AND (H.HouseType <> ht_WatchTower) AND (H.HouseType <> ht_Woodcutters) then
    begin
        IdxArray[Cnt] := fNavMesh.KMPoint2Polygon[ H.GetPosition ];
        Cnt := Cnt + 1;
    end;
  end;

  if (Cnt > 0) then
    fFloodFill.HouseInfluence(aPL, INIT_HOUSE_INFLUENCE, MAX_INFLUENCE_DISTANCE, Cnt - 1, IdxArray);
end;


function TKMInfluences.GetAreaEval(const aY,aX: Word): Byte;
begin
  Result := fAreas[aY,aX];
end;


//function TKMInfluences.GetAreaEval(const aY,aX: Word): Byte;
//var
//  Idx: Integer;
//begin
//  Idx := fNavMesh.Point2Polygon[aY,aX];
//  Result := fAreas[Idx];
//end;



procedure TKMInfluences.InitArrays();
var
  I: Integer;
begin
  if (fPolygons <> Length(gAIFields.NavMesh.Polygons)) then
  begin
    fPolygons := Length(gAIFields.NavMesh.Polygons);
    SetLength(fPresence, gHands.Count * fPolygons * GROUPS);
    SetLength(fOwnership, gHands.Count * fPolygons);
    for I := 0 to Length(fPresence) - 1 do
      fPresence[I] := 0;
    for I := 0 to Length(fOwnership) - 1 do
      fOwnership[I] := 0;
  end;
end;


procedure TKMInfluences.AfterMissionInit();
  //procedure InitAreas();
  //const
  //  RAD = 6;
  //var
  //  cnt: Word;
  //  X,Y, X0,Y0: Integer;
  //begin
  //  for Y := 1 to fMapY - 1 do
  //  for X := 1 to fMapX - 1 do
  //  begin
  //    cnt := 0;
  //    for Y0 := Max(1, Y - RAD) to Min(Y + RAD, fMapY - 1) do
  //    for X0 := Max(1, X - RAD) to Min(X + RAD, fMapX - 1) do
  //      cnt := cnt + Byte(  gRes.Tileset.TileIsWalkable( gTerrain.Land[Y0, X0].Terrain )  );
  //    fAreas[Y,X] := Min(255,cnt) * Byte(  gRes.Tileset.TileIsWalkable( gTerrain.Land[Y, X].Terrain )  );
  //    fAreas[Y,X] := Min(255,cnt) * Byte(  gRes.Tileset.TileIsWalkable( gTerrain.Land[Y, X].Terrain )  );
  //  end;
  //end;
  procedure InitAreas();
  const
    RAD = 6;
    MAX_ELEMENTS = (RAD+1) * (RAD+1) * 4;
  var
    X,Y, X0,Y0, cnt: Integer;
  begin
    for Y := 1 to fMapY - 1 do
    for X := 1 to fMapX - 1 do
    begin
      cnt := MAX_ELEMENTS;
      for Y0 := Max(1, Y - RAD) to Min(Y + RAD, fMapY - 1) do
      for X0 := Max(1, X - RAD) to Min(X + RAD, fMapX - 1) do
        cnt := cnt - Byte(  not gRes.Tileset.TileIsWalkable( gTerrain.Land[Y0, X0].Terrain )  );
      fAreas[Y,X] := Max(0, Min(255,cnt) * Byte(  gRes.Tileset.TileIsWalkable( gTerrain.Land[Y, X].Terrain )  ));
      fAreas[Y,X] := Max(0, Min(255,cnt) * Byte(  gRes.Tileset.TileIsWalkable( gTerrain.Land[Y, X].Terrain )  ));
    end;
  end;
  //procedure InitNavMeshAreas();
  //var
  //  WAD: TKMWalkableAreasDetector;
  //begin
  //  if AI_GEN_INFLUENCE_MAPS then
  //  begin
  //    WAD := TKMWalkableAreasDetector.Create(True);
  //    try
  //      WAD.MarkPolygons();
  //      fAreas := WAD.WalkableAreas;
  //    finally
  //      WAD.Free;
  //    end;
  //  end;
  //end;
var
  PL: TKMHandIndex;
begin
  fMapX := gTerrain.MapX;
  fMapY := gTerrain.MapY;
  SetLength(AvoidBuilding, fMapY, fMapX);
  InitAvoidBuilding();
  InitArrays();
  if AI_GEN_INFLUENCE_MAPS then
    for PL := 0 to gHands.Count - 1 do
      UpdateOwnership(PL);
  SetLength(fAreas, fMapY, fMapX);
  InitAreas();
  //InitNavMeshAreas();
end;


procedure TKMInfluences.UpdateState(aTick: Cardinal);
begin
  // City:
  if aTick mod 150 = 15 then // Update every 15 sec 1 player
  begin
    fUpdateCityIdx := (fUpdateCityIdx + 1) mod gHands.Count;
    UpdateOwnership(fUpdateCityIdx);
  end;
  // Army:
  if (aTick mod 5 = 0) then // Update every 0.5 sec 1 player
  begin
    fUpdateArmyIdx := (fUpdateArmyIdx + 1) mod gHands.Count;
    UpdateMilitaryPresence(fUpdateArmyIdx);
  end;
end;


//Render debug symbols
procedure TKMInfluences.Paint(aRect: TKMRect);
var
  PL{, WatchedPL}: TKMHandIndex;
  I{, Cnt}: Word;
  X,Y: Integer;
  PolyArr: TPolygonArray;
  NodeArr: TNodeArray;
  Col: Cardinal;

  //MaxW,MinW: Word;
  //B: Byte;
begin
  //for Y := 1 to fMapY - 1 do
  //for X := 1 to fMapX - 1 do
  //begin
  //  Col := fAreas[Y,X] * 65793 OR $80000000;
  //  gRenderAux.Quad(X, Y, Col);
  //end;
  //PolyArr := fNavMesh.Polygons;
  //NodeArr := fNavMesh.Nodes;
  //  MaxW := 0;
  //  MinW := High(Word);
  //  for I := Low(fAreas) to High(fAreas) do
  //    if (fAreas[I] > MaxW) then
  //      MaxW := fAreas[I]
  //    else if (fAreas[I] < MinW) then
  //      MinW := fAreas[I];
  //  for I := Low(fAreas) to High(fAreas) do
  //  begin
  //    B := Round((fAreas[I] - MinW)/(MaxW - MinW)*255);
  //    Col := $FFFFFF OR (B shl 24);
  //
  //    //NavMesh polys coverage
  //    gRenderAux.TriangleOnTerrain(
  //      NodeArr[PolyArr[I].Indices[0]].Loc.X,
  //      NodeArr[PolyArr[I].Indices[0]].Loc.Y,
  //      NodeArr[PolyArr[I].Indices[1]].Loc.X,
  //      NodeArr[PolyArr[I].Indices[1]].Loc.Y,
  //      NodeArr[PolyArr[I].Indices[2]].Loc.X,
  //      NodeArr[PolyArr[I].Indices[2]].Loc.Y, Col);
  //  end;



  if not AI_GEN_NAVMESH OR not AI_GEN_INFLUENCE_MAPS then
    Exit;

  if OVERLAY_AVOID then
    for Y := aRect.Top to aRect.Bottom do
    for X := aRect.Left to aRect.Right do
    begin
      Col := AvoidBuilding[Y,X] * 65793 OR $80000000;
      gRenderAux.Quad(X, Y, Col);
    end;

  if OVERLAY_INFLUENCE OR OVERLAY_OWNERSHIP then
  begin
    PolyArr := fNavMesh.Polygons;
    NodeArr := fNavMesh.Nodes;
    for I := 0 to fPolygons - 1 do
    begin
      PL := GetBestOwner(I);
      if (PL = PLAYER_NONE) then
        continue
      else
        Col := (gHands[PL].FlagColor AND $FFFFFF) OR (OwnPoly[PL,I] shl 24);

      //NavMesh polys coverage
      gRenderAux.TriangleOnTerrain(
        NodeArr[PolyArr[I].Indices[0]].Loc.X,
        NodeArr[PolyArr[I].Indices[0]].Loc.Y,
        NodeArr[PolyArr[I].Indices[1]].Loc.X,
        NodeArr[PolyArr[I].Indices[1]].Loc.Y,
        NodeArr[PolyArr[I].Indices[2]].Loc.X,
        NodeArr[PolyArr[I].Indices[2]].Loc.Y, Col);
    end;
  end;

  if OVERLAY_AI_COMBAT then
  begin
    //WatchedPL := gMySpectator.HandIndex;
    //if (WatchedPL = PLAYER_NONE) then
    //  Exit;
    //
    //PolyArr := fNavMesh.Polygons;
    //NodeArr := fNavMesh.Nodes;
    //
    //for PL := 0 to gHands.Count - 1 do
    //begin
    //  if (WatchedPL = PL) then
    //    Col := $0000FF00 // Green
    //  else if (gHands[WatchedPL].Alliances[PL] = at_Ally) then
    //    Col := $00FF0000 // Blue
    //  else
    //    Col := $000000FF; // Red
    //
    //  for I := 0 to fPolygons - 1 do
    //  begin
    //    Cnt := PresenceAllGroups[PL,I];
    //    if (Cnt > 0) then
    //    begin
    //      Cnt := Min(Cnt,$5F);
    //      //NavMesh polys coverage
    //      gRenderAux.TriangleOnTerrain(
    //        NodeArr[PolyArr[I].Indices[0]].Loc.X,
    //        NodeArr[PolyArr[I].Indices[0]].Loc.Y,
    //        NodeArr[PolyArr[I].Indices[1]].Loc.X,
    //        NodeArr[PolyArr[I].Indices[1]].Loc.Y,
    //        NodeArr[PolyArr[I].Indices[2]].Loc.X,
    //        NodeArr[PolyArr[I].Indices[2]].Loc.Y, (Col OR (Cnt shl 24)) ); // (Col OR $50000000)
    //    end;
    //  end;
    //end;
    //for I := 0 to fPolygons - 1 do
    //begin
    //  BestCnt := 0;
    //  for PL := 0 to gHands.Count - 1 do
    //  begin
    //    Cnt := PresenceAllGroups[PL,I];
    //    if (Cnt > BestCnt) then
    //    begin
    //      BestCnt := Cnt;
    //      if (WatchedPL = PL) then
    //        Col := $0000FF00 // Green
    //      else if (gHands[WatchedPL].Alliances[PL] = at_Ally) then
    //        Col := $00FF0000 // Blue
    //      else
    //        Col := $000000FF; // Red
    //    end;
    //  end;
    //  if (BestCnt > 0) then
    //  begin
    //    BestCnt := Min(BestCnt,$9F);
    //    //NavMesh polys coverage
    //    gRenderAux.TriangleOnTerrain(
    //      NodeArr[PolyArr[I].Indices[0]].Loc.X,
    //      NodeArr[PolyArr[I].Indices[0]].Loc.Y,
    //      NodeArr[PolyArr[I].Indices[1]].Loc.X,
    //      NodeArr[PolyArr[I].Indices[1]].Loc.Y,
    //      NodeArr[PolyArr[I].Indices[2]].Loc.X,
    //      NodeArr[PolyArr[I].Indices[2]].Loc.Y, (Col OR (BestCnt shl 24)) );
    //  end;
    //end;
  end;
end;








end.
