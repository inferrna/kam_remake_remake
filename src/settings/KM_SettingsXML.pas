unit KM_SettingsXML;
{$I KaM_Remake.inc}
interface
uses
  KM_Settings,
  KM_IoXML;

type
  // Common implementation for settings stored and loaded from XML
  TKMSettingsXML = class(TKMSettings)
  private
    fXML: TKMXmlDocument;
  protected
    fRoot: TKMXmlNode;
    //property fRoot: TKMXmlNode write fXML.fRoot;
    procedure LoadFromFile(const aPath: string); override;
    procedure SaveToFile(const aPath: UnicodeString); override;
  public
    constructor Create;
    destructor Destroy; override;
  end;


implementation
uses
  SysUtils,
  KM_Defaults,
  KM_FileIO,
  KM_CommonUtils,
  KM_Log;


{ TKMSettingsXML }
constructor TKMSettingsXML.Create;
begin
  gLog.AddTime('Called TKMSettingsXML.Create');
  fXML := TKMXmlDocument.Create;
  //fRoot := fXML.Root; //TODO: create empty XML of nstart if no file found
  // Prefer to store XML settings in the shared folder
  inherited Create(slShared);
end;


destructor TKMSettingsXML.Destroy;
begin
  inherited;

  fXML.Free;
end;


procedure TKMSettingsXML.LoadFromFile(const aPath: string);
begin
  inherited;
  gLog.AddTime('Called TKMSettingsXML.LoadFromFile '+aPath);
  fXML.LoadFromFile(aPath);
  fRoot := fXML.Root;
end;


procedure TKMSettingsXML.SaveToFile(const aPath: UnicodeString);
begin
  inherited;
  fXML.SaveToFile(aPath);
end;


end.

