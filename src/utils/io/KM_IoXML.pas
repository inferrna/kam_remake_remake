unit KM_IoXML;
{$I KaM_Remake.inc}
interface

{$IFDEF WDC}
{$DEFINE USE_SIMLE_XML}
{$ENDIF}
uses
  Classes, SysUtils, LazLogger, KM_Log

  {$IFDEF USE_SIMLE_XML}
  , Xml.VerySimple // (Attributes can be only 'string', which is not convenient)
  {$ELSE}
  , xmlreader, laz2_DOM, laz2_XMLRead, laz2_XMLWrite
  {$ENDIF}
  ;

  // We might try NativeXML (compatible with Android and iOS ?)

type
  {$IFDEF USE_SIMLE_XML}
  TKMXmlDomDocument = TXmlVerySimple;
//  TKMXmlAttribute = Xml.VerySimple.TXmlAttribute;
  {$ELSE}
  TKMXmlDomDocument = TXMLDocument;
  {$ENDIF}

  TKMXmlNode = class;

  TKMSimpleVariant = record
  private
    // Internal representation is always a string
    fValue: string;
    {$IFDEF USE_SIMLE_XML}
    function ToSimpleVariant: TSimpleVariant;
    {$ENDIF}
  public
    class operator Implicit(const A: Boolean): TKMSimpleVariant;
    class operator Implicit(const A: Cardinal): TKMSimpleVariant;
    class operator Implicit(const A: Integer): TKMSimpleVariant;
    class operator Implicit(const A: Single): TKMSimpleVariant;
    class operator Implicit(const A: string): TKMSimpleVariant;
    class operator Implicit(const A: TDateTime): TKMSimpleVariant;
    function AsBoolean: Boolean; overload;
    function AsBoolean(aDefault: Boolean): Boolean; overload;
    function AsCardinal: Cardinal; overload;
    function AsCardinal(aDefault: Cardinal): Cardinal; overload;
    function AsDateTime: TDateTime;
    function AsFloat: Single; overload;
    function AsFloat(aDefault: Single): Single; overload;
    function AsInteger: Integer; overload;
    function AsInteger(aDefault: Integer): Integer; overload;
    function AsString: string; overload;
    function AsString(aDefault: string): string; overload;
  end;


  TKMXmlDocument = class
  private
    fDocument: TKMXmlDomDocument;
    fRoot: TKMXmlNode;
    cNode: TDOMNode;
    function GetText: String;
    procedure SetText(const aText: string);
    procedure ApplyDefaultSettings;
  public
    constructor Create(const aRoot: string = 'Root');
    destructor Destroy; override;

    property Root: TKMXmlNode read fRoot;

    procedure LoadFromFile(const aFilename: string; aRoot: string  = 'Root'; aReadOnly: Boolean = True);
    procedure SaveToFile(const aFilename: string; aCompressed: Boolean = False);

    property Text: string read GetText write SetText;
  end;


  {$IFDEF USE_SIMPLE_XML}
  TKMXmlNode = class(Xml.VerySimple.TXmlNode)
  {$ELSE}
  TKMXmlNode = class(TDOMElement)
  {$ENDIF}
  protected
    function GetAttrib(const AttrName: String): TKMSimpleVariant;
    procedure SetAttrib(const AttrName: String; const AttrValue: TKMSimpleVariant);
    function GetChildsCount: Integer;
    function GetChild(const aIndex: Integer): TKMXmlNode;
  public
    function AddChild(const Name: String): TKMXmlNode; {$IFDEF WDC}reintroduce;{$ENDIF}
    function FindNode(const Name: String): TKMXmlNode; {$IFNDEF  USE_SIMPLE_XML}reintroduce;{$ENDIF}
    function AddOrFindChild(const aChildNodeName: string): TKMXmlNode;
    function HasAttribute(const AttrName: String): Boolean; {$IFDEF WDC}reintroduce;{$ENDIF}
    function HasChild(const Name: String): Boolean; {$IFDEF WDC}reintroduce;{$ENDIF}
    property Attributes[const AttrName: String]: TKMSimpleVariant read GetAttrib write SetAttrib;
    property ChildsCount: Integer read GetChildsCount;
    property Childs[const aIndex: Integer]: TKMXmlNode read GetChild;
  end;


implementation
uses
  Variants, DateUtils, StrUtils;


{ TKMXMLDocument }
constructor TKMXmlDocument.Create(const aRoot: string = 'Root');
var
  tel: TDOMElement;
  Ptr: ^TKMXmlNode;
begin
  inherited Create;

  fDocument := TKMXmlDomDocument.Create;

  ApplyDefaultSettings;

  {$IFDEF USE_SIMPLE_XML}
  if aRoot <> '' then
    fRoot := TKMXmlNode(fDocument.AddChild(aRoot));
  {$ELSE}
  if aRoot <> '' then
  begin
    //fRoot := TKMXmlNode.create(fDocument);
    //fRoot.appendChild(fDocument.CreateElement(aRoot));
    //fDocument.AppendChild(fRoot);
    tel := fDocument.CreateElement(aRoot);
    Ptr := @tel;
    fRoot := Ptr^;
    fDocument.AppendChild(fRoot);
  end;
  {$ENDIF}
end;


destructor TKMXmlDocument.Destroy;
begin
  fDocument.Free;

  inherited;
end;


procedure TKMXmlDocument.ApplyDefaultSettings;
begin
  {$IFDEF USE_SIMPLE_XML}
  fDocument.Version := '1.0';
  fDocument.Encoding := 'UTF-8';
  fDocument.Options := [doNodeAutoIndent]; // Do not write BOM
  {$ELSE}
  fDocument.XMLVersion := '1.0';
  {$ENDIF}
end;


procedure TKMXmlDocument.LoadFromFile(const aFilename: string; aRoot: string  = 'Root'; aReadOnly: Boolean = True);
begin
  {$IFDEF USE_SIMPLE_XML}
    // When no file exists we create an empty XML and let caller handle it
    // e.g. by reading default values from it
    if FileExists(aFilename) then
    begin
      fDocument.LoadFromFile(aFilename);
      fRoot := TKMXmlNode(fDocument.ChildNodes.FindNode(aRoot));
      ApplyDefaultSettings;
      // Create root if it's missing, so that XML could be processed and default parameters created
      if fRoot = nil then
        fRoot := TKMXmlNode(fDocument.ChildNodes.Add(aRoot));
    end;
  {$ELSE}
    // When no file exists we create an empty XML and let caller handle it
    // e.g. by reading default values from it
    if FileExists(aFilename) then
    begin
      ReadXMLFile(fDocument, aFilename);
      ApplyDefaultSettings;
      cNode := fDocument.DocumentElement.FindNode(aRoot);
      fRoot := TKMXmlNode.Create(fDocument);
      // Create root if it's missing, so that XML could be processed and default parameters created
      if cNode <> nil then
         fRoot.AppendChild(cNode);
    end;
  {$ENDIF}
end;


procedure TKMXmlDocument.SaveToFile(const aFilename: string; aCompressed: Boolean = False);
begin
  ForceDirectories(ExtractFilePath(ExpandFileName(aFilename)));
  {$IFDEF USE_SIMPLE_XML}
  fDocument.SaveToFile(aFilename);
  {$ELSE}
  if fDocument <> nil then
  begin
     //fDocument.ReplaceChild(Root, fDocument.GetChildNodes.Item[0]);
     gLog.AddTime(Format('Try to save to ''%s''', [aFilename]));
     gLog.AddTime('Tree with ' + IntToStr(Root.GetChildNodes.Count) + ' children');
     gLog.AddTime('Tree with ' + IntToStr(Root.GetChildNodes.Item[0].GetChildNodes.Count) + ' children');
     WriteXMLFile(fDocument, aFilename);
     gLog.AddTime(Format('saved to ''%s''', [aFilename]));
  end;
  {$ENDIF}
end;


function TKMXmlDocument.GetText: String;
begin
  {$IFDEF USE_SIMPLE_XML}
  Result := fDocument.Xml;
  {$ELSE}
  Result := fDocument.ToString;
  {$ENDIF}
end;

procedure TKMXmlDocument.SetText(const aText: string);
{$IFNDEF USE_SIMPLE_XML}
var S: TStringStream;
{$ENDIF}
begin
  {$IFDEF USE_SIMPLE_XML}
  fDocument.Xml := aText;
  {$ELSE}
  S := TStringStream.Create(aText);
  ReadXMLFile(fDocument, S);
  {$ENDIF}
end;


{ TKMXmlNode }
function TKMXmlNode.AddChild(const Name: String): TKMXmlNode;
{$IFNDEF USE_SIMPLE_XML}
var
  tel: TDOMNode;
  Ptr: ^TKMXmlNode;
  txml: TKMXmlNode;
{$ENDIF}
begin
  {$IFDEF USE_SIMPLE_XML}
  Result := TKMXmlNode(inherited AddChild(Name));
  {$ELSE}
  tel := self.AppendChild(FOwnerDocument.CreateElement(Name));
  Ptr := @tel;
  txml := Ptr^;
  Result := TKMXmlNode(txml);
  {$ENDIF}
end;


function TKMXmlNode.FindNode(const Name: String): TKMXmlNode;
{$IFNDEF USE_SIMPLE_XML}
var
  tel: TDOMNode;
  Ptr: ^TKMXmlNode;
  txml: TKMXmlNode;
{$ENDIF}
begin
  {$IFDEF USE_SIMPLE_XML}
  Result := TKMXmlNode(ChildNodes.Find(Name));
  {$ELSE}
  tel := inherited FindNode(Name);
  Ptr := @tel;
  txml := Ptr^;
  Result := TKMXmlNode(txml);
  {$ENDIF}
end;


function TKMXmlNode.AddOrFindChild(const aChildNodeName: string): TKMXmlNode;
begin
  if not HasChild(aChildNodeName) then
  begin
    Result := AddChild(aChildNodeName);
    {$IFDEF DEBUG}
    Assert(Result <> nil, 'Added nil for '+aChildNodeName);
   {$ENDIF}
  end
  else
  begin
    Result := FindNode(aChildNodeName);
    {$IFDEF DEBUG}
    Assert(Result <> nil, 'Found nil for '+aChildNodeName);
    {$ENDIF}
  end;
end;



function TKMXmlNode.HasAttribute(const AttrName: String): Boolean;
begin
  Result := inherited HasAttribute(AttrName);
end;


function TKMXmlNode.HasChild(const Name: String): Boolean;
var i : Integer;
begin
  {$IFDEF DEBUG}
  Assert(self <> nil);
  {$ENDIF}
  {$IFDEF USE_SIMPLE_XML}
  Result := inherited HasChild(Name);
  {$ELSE}
  Result := False;
  for i := 0 to ChildsCount-1 do
  begin
    {$IFDEF DEBUG}
    Assert(ChildNodes[i] <> nil, 'Node '+IntToStr(i)+' is nil');
    {$ENDIF}
    Result := ChildNodes[i].NodeName = Name;
    if Result then
    begin
      gLog.AddTime('Found ' + Name);
      Break;
    end;
    //{$IFDEF DEBUG}
    //else
    //  gLog.AddTime(IntToStr(i)+' '+ChildNodes[i].NodeName + ' is not equal ' + Name);
    //{$ENDIF}
  end;
  {$ENDIF}
end;


function TKMXmlNode.GetAttrib(const AttrName: String): TKMSimpleVariant;
{$IFDEF USE_SIMPLE_XML}
var
  sv: TSimpleVariant;
{$ENDIF}
begin
  {$IFDEF USE_SIMPLE_XML}
  sv := inherited GetAttr(AttrName);
  Result.fValue := sv.AsString;
  {$ELSE}
  Result.fValue := inherited GetAttribute(AttrName);
  {$ENDIF}
end;


procedure TKMXmlNode.SetAttrib(const AttrName: String; const AttrValue: TKMSimpleVariant);
begin
  {$IFDEF USE_SIMPLE_XML}
  inherited SetAttr(AttrName, AttrValue.ToSimpleVariant);
  {$ELSE}
  {$IFDEF DEBUG}
  gLog.AddTime('Set '+AttrName+' to '+AttrValue.AsString);
  {$ENDIF}
  inherited SetAttribute(AttrName, AttrValue.AsString);
  {$ENDIF}
end;


function TKMXmlNode.GetChildsCount: Integer;
begin
  Result := ChildNodes.Count;
end;


function TKMXmlNode.GetChild(const aIndex: Integer): TKMXmlNode;
begin
  Result := TKMXmlNode(ChildNodes[aIndex]);
end;


{ ToSimpleVariant}
{$IFDEF USE_SIMPLE_XML}
function TKMSimpleVariant.ToSimpleVariant: TSimpleVariant;
begin
  Result := TSimpleVariant.New(fValue);
end;
{$ENDIF}

function TKMSimpleVariant.AsBoolean: Boolean;
begin
  Result := StrToBool(fValue);
end;

function TKMSimpleVariant.AsBoolean(aDefault: Boolean): Boolean;
begin
  Result := StrToBoolDef(fValue, aDefault);
end;

function TKMSimpleVariant.AsCardinal: Cardinal;
begin
  Result := StrToInt64(fValue);
end;

function TKMSimpleVariant.AsCardinal(aDefault: Cardinal): Cardinal;
begin
  Result := StrToInt64Def(fValue, aDefault);
end;

function TKMSimpleVariant.AsDateTime: TDateTime;
var
  v: Variant;
begin
  // This is very slow in Analyzer
  // VarToDateTime seems to be much faster and provide same accuracy
  {try
    Result := StrToDateTime(fValue);
  except}
    try
      v := fValue;
      {$IFDEF WDC}
      Result := VarToDateTime(v);
      {$ELSE}
      Result := StrToDateTime(fValue);
      {$ENDIF}
    except
      Result := 0;
    end;
  //end;
end;

function TKMSimpleVariant.AsFloat: Single;
var
  str: string;
begin
  str := StringReplace(fValue, '.', FormatSettings.DecimalSeparator, [rfReplaceAll]);
  str := StringReplace(str, ',', FormatSettings.DecimalSeparator, [rfReplaceAll]);
  Result := StrToFloat(str);
end;

function TKMSimpleVariant.AsFloat(aDefault: Single): Single;
var
  str: string;
begin
  str := StringReplace(fValue, '.', FormatSettings.DecimalSeparator, [rfReplaceAll]);
  str := StringReplace(str, ',', FormatSettings.DecimalSeparator, [rfReplaceAll]);
  Result := StrToFloatDef(str, aDefault);
end;

function TKMSimpleVariant.AsInteger: Integer;
begin
  //writeln('Cast '+fValue+' as integer');
  if fValue = '' then
    Result := 0
  else
    Result := StrToInt(fValue)
end;

function TKMSimpleVariant.AsInteger(aDefault: Integer): Integer;
begin
  Result := StrToIntDef(fValue, aDefault);
end;

function TKMSimpleVariant.AsString: string;
begin
  Result := fValue;
end;

function TKMSimpleVariant.AsString(aDefault: string): string;
begin
  if fValue <> '' then
    Result := fValue
  else
    Result := aDefault;
end;

class operator TKMSimpleVariant.Implicit(const A: Boolean): TKMSimpleVariant;
const
  BOOL_STR: array [Boolean] of string = ('False', 'True');
begin
  Result.fValue := BOOL_STR[A];
end;

class operator TKMSimpleVariant.Implicit(const A: Cardinal): TKMSimpleVariant;
begin
  Result.fValue := '$' + IntToHex(A, 8);
end;

class operator TKMSimpleVariant.Implicit(const A: Integer): TKMSimpleVariant;
begin
  Result.fValue := IntToStr(A);
end;

class operator TKMSimpleVariant.Implicit(const A: Single): TKMSimpleVariant;
var
  str: string;
  fs: TFormatSettings;
begin
  {$IFDEF WDC}
  fs := TFormatSettings.Create;
  {$ENDIF}
  fs.DecimalSeparator := '.';

  str := FormatFloat('0.0000', A, fs);

  Result.fValue := str;
end;

class operator TKMSimpleVariant.Implicit(const A: string): TKMSimpleVariant;
begin
  Result.fValue := A;
end;

class operator TKMSimpleVariant.Implicit(const A: TDateTime): TKMSimpleVariant;
begin
  // Still prone to localization issues
  //Result.fValue := FormatDateTime('yyyy.mm.dd hh:nn:ss', A);

  // Custom code ensures we ALWAYS get the same format
  Result.fValue := IntToStr(YearOf(A)) + '.' + IntToStr(MonthOf(A)) + '.' + IntToStr(DayOf(A)) + ' ' +
                   IntToStr(HourOf(A)) + ':' + IntToStr(MinuteOf(A)) + ':' + IntToStr(SecondOf(A));
end;


end.
