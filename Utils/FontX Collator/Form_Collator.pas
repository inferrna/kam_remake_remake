﻿unit Form_Collator;
{$I ..\..\KaM_Remake.inc}
interface
uses
  {$IFDEF WDC} Windows, {$ENDIF} //Declared first to get TBitmap overriden with VCL version
  {$IFDEF FPC} lconvencoding, {$ENDIF}
  SysUtils, Classes, Graphics, Controls, Forms, Dialogs, ExtCtrls, StdCtrls, Spin, StrUtils,
  KM_CommonTypes, KM_Defaults, KM_FontCollator, KM_ResFonts, KM_ResFontsEdit, KM_ResPalettes,
  Vcl.ComCtrls;


type
  TForm1 = class(TForm)
    Label4: TLabel;
    Image1: TImage;
    btnSave: TButton;
    dlgSave: TSaveDialog;
    btnExportTex: TButton;
    dlgOpen: TOpenDialog;
    btnImportTex: TButton;
    GroupBox1: TGroupBox;
    sePadding: TSpinEdit;
    Label5: TLabel;
    rgSizeX: TRadioGroup;
    rgSizeY: TRadioGroup;
    cbCells: TCheckBox;
    ListBox1: TListBox;
    btnCollate: TButton;
    ListBox2: TListBox;
    Label1: TLabel;
    Label2: TLabel;
    Label6: TLabel;
    tbAtlas: TTrackBar;
    procedure btnSaveClick(Sender: TObject);
    procedure btnExportTexClick(Sender: TObject);
    procedure btnImportTexClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btnCollateClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ListBox1Click(Sender: TObject);
    procedure tbAtlasChange(Sender: TObject);
  private
    fFontData: TKMFontSpecEdit;
    fFontCollator: TKMFontCollator;
  end;


var
  Form1: TForm1;


implementation
{$R *.dfm}


procedure TForm1.FormCreate(Sender: TObject);
var
  I: Integer;
begin
  Caption := 'KaM FontX Collator (' + GAME_REVISION + ')';
  ExeDir := ExtractFilePath(ParamStr(0));

  fFontCollator := TKMFontCollator.Create;

  //Scan fonts folder
  fFontCollator.ListFonts(ExeDir + '..\..\' + TKMFontSpec.FONTS_FOLDER);

  //Available fonts
  for I := 0 to fFontCollator.Fonts.Count - 1 do
    ListBox1.Items.Add(fFontCollator.Fonts[I]);
end;


procedure TForm1.FormDestroy(Sender: TObject);
begin
  FreeAndNil(fFontCollator);
  FreeAndNil(fFontData);
end;


procedure TForm1.ListBox1Click(Sender: TObject);
begin
  ListBox2.Clear;
  ListBox2.Items.Text := fFontCollator.FontCodepages(ListBox1.ItemIndex);
  ListBox2.SelectAll;
end;


procedure TForm1.btnSaveClick(Sender: TObject);
begin
  dlgSave.DefaultExt := TKMFontSpec.DEFAULT_EXT;
  dlgSave.FileName := ListBox1.Items[ListBox1.ItemIndex];
  dlgSave.InitialDir := ExpandFileName(ExeDir + '..\..\' + TKMFontSpec.FONTS_FOLDER);
  if not dlgSave.Execute then Exit;

  fFontData.SaveToFontX(dlgSave.FileName);
end;


procedure TForm1.btnCollateClick(Sender: TObject);
var
  I, K: Integer;
  files: TKMStringArray;
begin
  if ListBox1.ItemIndex = -1 then Exit;

  //Recreate clean Font
  FreeAndNil(fFontData);
  fFontData := TKMFontSpecEdit.Create(fntArial); //fntArial, why not, it looks like we dont care

  K := 0;
  SetLength(files, ListBox2.Count);
  for I := 0 to ListBox2.Count - 1 do
  if ListBox2.Selected[I] then
  begin
    files[K] := ListBox2.Items[I];
    Inc(K);
  end;
  SetLength(files, K);

  if K = 0 then Exit;

  fFontCollator.Collate(ListBox1.ItemIndex,
                   StrToInt(rgSizeX.Items[rgSizeX.ItemIndex]),
                   StrToInt(rgSizeY.Items[rgSizeY.ItemIndex]),
                   sePadding.Value,
                   files,
                   fFontData);

  tbAtlas.Max := fFontData.AtlasCount - 1;

  fFontData.ExportAtlasBmp(Image1.Picture.Bitmap, tbAtlas.Position, cbCells.Checked);
  Image1.Repaint;
end;


procedure TForm1.tbAtlasChange(Sender: TObject);
begin
  fFontData.ExportAtlasBmp(Image1.Picture.Bitmap, tbAtlas.Position, cbCells.Checked);
  Image1.Repaint;
end;


procedure TForm1.btnExportTexClick(Sender: TObject);
begin
  dlgSave.DefaultExt := 'png';
  if not dlgSave.Execute then Exit;

  fFontData.ExportAtlasPng(dlgSave.FileName, tbAtlas.Position);
end;


procedure TForm1.btnImportTexClick(Sender: TObject);
begin
  if not dlgOpen.Execute then Exit;

  fFontData.ImportPng(dlgOpen.FileName, tbAtlas.Position);
end;


end.
