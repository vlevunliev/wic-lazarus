unit WicDemoMain;
{ Демо: отваря всичко, което Windows може да декодира, показва EXIF и
  записва в друг формат. Контролите се създават в кода, затова няма .lfm. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  WicImaging, WicLCL;

type
  TMainForm = class(TForm)
  private
    FImage: TImage;
    FInfo: TMemo;
    FStatus: TLabel;
    FMaxSide: TComboBox;
    FCurrent: TWicImage;
    FFileName: string;
    FHaveImage: Boolean;
    FKeepMeta: TCheckBox;
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure CodecsClick(Sender: TObject);
    procedure ShowInfo(const FileName: string);
  public
    constructor Create(TheOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

function MakeButton(AOwner: TWinControl; const ACaption: string; AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent := AOwner;
  Result.Caption := ACaption;
  Result.AutoSize := True;
  Result.Align := alLeft;
  Result.BorderSpacing.Around := 4;
  Result.OnClick := AOnClick;
end;

constructor TMainForm.Create(TheOwner: TComponent);
var
  Bar: TPanel;
  Split: TSplitter;
begin
  inherited CreateNew(TheOwner);
  Caption := 'WIC демо: Windows работи за нас';
  Width := 1100;
  Height := 720;
  Position := poScreenCenter;

  Bar := TPanel.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 40;
  Bar.BevelOuter := bvNone;

  // alLeft подрежда по Left, затова им даваме нарастващи стойности
  MakeButton(Bar, 'Отвори...', @OpenClick).Left := 0;
  FMaxSide := TComboBox.Create(Self);
  FMaxSide.Parent := Bar;
  FMaxSide.Align := alLeft;
  FMaxSide.Left := 100;
  FMaxSide.Width := 120;
  FMaxSide.BorderSpacing.Around := 6;
  FMaxSide.Style := csDropDownList;
  FMaxSide.Items.CommaText := '"Пълен размер",800,1600,2560,4096';
  FMaxSide.ItemIndex := 2;
  MakeButton(Bar, 'Запиши като...', @SaveClick).Left := 300;
  FKeepMeta := TCheckBox.Create(Self);
  FKeepMeta.Parent := Bar;
  FKeepMeta.Align := alLeft;
  FKeepMeta.Left := 350;
  FKeepMeta.BorderSpacing.Around := 6;
  FKeepMeta.Caption := 'запази EXIF/GPS';
  FKeepMeta.Checked := True;
  MakeButton(Bar, 'Кодеци на машината', @CodecsClick).Left := 400;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Bar;
  FStatus.Align := alClient;
  FStatus.Layout := tlCenter;
  FStatus.BorderSpacing.Left := 8;
  FStatus.Caption := 'Отвори снимка (JPEG, PNG, TIFF, HEIC, WebP, RAW... каквото има Windows)';

  FInfo := TMemo.Create(Self);
  FInfo.Parent := Self;
  FInfo.Align := alRight;
  FInfo.Width := 380;
  FInfo.ScrollBars := ssBoth;
  FInfo.ReadOnly := True;
  FInfo.WordWrap := False;
  FInfo.Font.Name := 'Consolas';

  Split := TSplitter.Create(Self);
  Split.Parent := Self;
  Split.Align := alRight;

  FImage := TImage.Create(Self);
  FImage.Parent := Self;
  FImage.Align := alClient;
  FImage.Center := True;
  FImage.Proportional := True;
  FImage.Stretch := True;
end;

procedure TMainForm.ShowInfo(const FileName: string);
var
  I: TWicPhotoInfo;
  L: TStringList;
begin
  FInfo.Lines.BeginUpdate;
  try
    FInfo.Lines.Clear;
    I := WicGetPhotoInfo(FileName);
    FInfo.Lines.Add('Камера:     ' + Trim(I.Make + ' ' + I.Model));
    FInfo.Lines.Add('Снимана:    ' + I.DateTaken);
    FInfo.Lines.Add('Ориентация: ' + IntToStr(I.Orientation));
    if I.ExposureTime > 0 then
      if I.ExposureTime < 1 then
        FInfo.Lines.Add(Format('Експонация: 1/%d s', [Round(1 / I.ExposureTime)]))
      else
        FInfo.Lines.Add(Format('Експонация: %g s', [I.ExposureTime]));
    if I.FNumber > 0 then FInfo.Lines.Add(Format('Бленда:     f/%g', [I.FNumber]));
    if I.ISO > 0 then FInfo.Lines.Add(Format('ISO:        %d', [I.ISO]));
    if I.FocalLength > 0 then FInfo.Lines.Add(Format('Фокус:      %g mm', [I.FocalLength]));
    if I.HasGPS then
      FInfo.Lines.Add(Format('GPS:        %.6f, %.6f', [I.Latitude, I.Longitude]));
    FInfo.Lines.Add('');
    FInfo.Lines.Add('--- всички метаданни ---');
    L := TStringList.Create;
    try
      WicDumpMetadata(FileName, L);
      FInfo.Lines.AddStrings(L);
    finally
      L.Free;
    end;
  finally
    FInfo.Lines.EndUpdate;
  end;
end;

procedure TMainForm.OpenClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  T0: QWord;
  MaxSide, W, H: Integer;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Filter := WicOpenDialogFilter + '|Всички файлове|*.*';
    if not Dlg.Execute then Exit;
    MaxSide := StrToIntDef(FMaxSide.Text, 0);
    Screen.BeginWaitCursor;
    try
      T0 := GetTickCount64;
      WicGetImageSize(Dlg.FileName, W, H);
      FCurrent := WicLoad(Dlg.FileName, MaxSide);
      WicImageToBitmap(FCurrent, FImage.Picture.Bitmap);
      FHaveImage := True;
      FFileName := Dlg.FileName;
      FStatus.Caption := Format('%s   оригинал %dx%d, показан %dx%d, %d ms',
        [ExtractFileName(Dlg.FileName), W, H, FCurrent.Width, FCurrent.Height,
         GetTickCount64 - T0]);
      ShowInfo(Dlg.FileName);
    finally
      Screen.EndWaitCursor;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.SaveClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  Q: string;
begin
  if not FHaveImage then Exit;
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Filter := 'JPEG|*.jpg|PNG|*.png|TIFF|*.tif|BMP|*.bmp|JPEG-XR|*.jxr|HEIC (ако има кодек)|*.heic|JPEG XL (ако има кодек)|*.jxl';
    Dlg.DefaultExt := 'jpg';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    Q := '90';
    if SameText(ExtractFileExt(Dlg.FileName), '.jpg') or
       SameText(ExtractFileExt(Dlg.FileName), '.heic') then
      if not InputQuery('Качество', 'Качество 1..100:', Q) then Exit;
    if FKeepMeta.Checked then
      WicSaveWithMetadataFrom(FCurrent, Dlg.FileName, FFileName, StrToIntDef(Q, 90) / 100)
    else
      WicSave(FCurrent, Dlg.FileName, StrToIntDef(Q, 90) / 100);
    FStatus.Caption := 'Записано: ' + Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.CodecsClick(Sender: TObject);
var
  C: TWicCodecInfoArray;
  I: Integer;
begin
  C := WicListCodecs;
  FInfo.Lines.BeginUpdate;
  try
    FInfo.Lines.Clear;
    FInfo.Lines.Add(Format('Кодеци на тази машина: %d', [Length(C)]));
    FInfo.Lines.Add('');
    for I := 0 to High(C) do
      FInfo.Lines.Add(Format('%s %s'#13#10'    %s', [BoolToStr(C[I].IsEncoder, 'ЗАПИС ', 'ЧЕТЕНЕ'),
        C[I].FriendlyName, C[I].Extensions]));
  finally
    FInfo.Lines.EndUpdate;
  end;
end;

end.
