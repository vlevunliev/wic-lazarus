{ ============================================================================
  WicLCL.pas - мост между WicImaging и LCL (TBitmap / TPicture)

  uses WicImaging, WicLCL;

  WicLoadBitmap('C:\Снимки\IMG_1234.HEIC', Image1.Picture.Bitmap, 1600);
  WicSaveBitmap(Image1.Picture.Bitmap, 'C:\out\snimka.jpg', 0.85);
  ============================================================================ }
unit WicLCL;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, GraphType, IntfGraphics, FPImage, WicImaging;

{ TWicImage -> TBitmap (32 bpp с алфа). }
procedure WicImageToBitmap(const Img: TWicImage; Bmp: TBitmap);

{ TBitmap -> TWicImage. Работи за всеки PixelFormat; без алфа -> 255. }
function WicImageFromBitmap(Bmp: TBitmap): TWicImage;

{ Зарежда директно в TBitmap, с изправяне по EXIF и смаляване по избор. }
procedure WicLoadBitmap(const FileName: string; Bmp: TBitmap;
  MaxSide: Integer = 0; AutoRotate: Boolean = True);

{ Удобство за TImage: WicLoadPicture(FN, Image1.Picture, 1920) }
procedure WicLoadPicture(const FileName: string; Pic: TPicture;
  MaxSide: Integer = 0; AutoRotate: Boolean = True);

{ Записва TBitmap във формата по разширението. Quality 0..1 за JPEG/HEIF. }
procedure WicSaveBitmap(Bmp: TBitmap; const FileName: string; Quality: Single = 0.9);

{ Филтър за TOpenDialog от реално наличните на машината декодери, напр.
  'Всички изображения|*.jpg;*.png;*.heic|JPEG Decoder|*.jpg;*.jpeg|...' }
function WicOpenDialogFilter(const AllCaption: string = 'Всички изображения'): string;

implementation

procedure WicImageToBitmap(const Img: TWicImage; Bmp: TBitmap);
var
  Raw: TRawImage;
begin
  Raw.Init;
  Raw.Description.Init_BPP32_B8G8R8A8_BIO_TTB(Img.Width, Img.Height);
  Raw.CreateData(False);
  // 32 bpp: редът винаги е Width*4 байта, без допълване
  if Raw.DataSize > 0 then
    Move(Img.Pixels[0], Raw.Data^, Raw.DataSize);
  Bmp.LoadFromRawImage(Raw, True);   // Bmp поема Raw.Data
end;

function WicImageFromBitmap(Bmp: TBitmap): TWicImage;
var
  Intf: TLazIntfImage;
  X, Y: Integer;
  C: TFPColor;
  P: PByte;
begin
  Result := Default(TWicImage);
  Result.Width := Bmp.Width;
  Result.Height := Bmp.Height;
  SetLength(Result.Pixels, Result.Width * Result.Height * 4);
  if Length(Result.Pixels) = 0 then Exit;
  Intf := Bmp.CreateIntfImage;
  try
    P := @Result.Pixels[0];
    for Y := 0 to Result.Height - 1 do
      for X := 0 to Result.Width - 1 do
      begin
        C := Intf.Colors[X, Y];
        P[0] := C.Blue shr 8;
        P[1] := C.Green shr 8;
        P[2] := C.Red shr 8;
        P[3] := C.Alpha shr 8;
        Inc(P, 4);
      end;
  finally
    Intf.Free;
  end;
end;

procedure WicLoadBitmap(const FileName: string; Bmp: TBitmap;
  MaxSide: Integer; AutoRotate: Boolean);
begin
  WicImageToBitmap(WicLoad(FileName, MaxSide, AutoRotate), Bmp);
end;

procedure WicLoadPicture(const FileName: string; Pic: TPicture;
  MaxSide: Integer; AutoRotate: Boolean);
var
  B: TBitmap;
begin
  B := TBitmap.Create;
  try
    WicLoadBitmap(FileName, B, MaxSide, AutoRotate);
    Pic.Assign(B);
  finally
    B.Free;
  end;
end;

procedure WicSaveBitmap(Bmp: TBitmap; const FileName: string; Quality: Single);
begin
  WicSave(WicImageFromBitmap(Bmp), FileName, Quality);
end;

function ExtToMasks(const Exts: string): string;
begin
  // '.jpg,.jpeg' (Windows) или '.jpg;.jpeg' (Wine) -> '*.jpg;*.jpeg'
  Result := StringReplace(Exts, ',', ';', [rfReplaceAll]);
  Result := StringReplace(Result, ' ', '', [rfReplaceAll]);
  Result := '*' + StringReplace(Result, ';', ';*', [rfReplaceAll]);
end;

function WicOpenDialogFilter(const AllCaption: string): string;
var
  Codecs: TWicCodecInfoArray;
  I: Integer;
  All, Parts: string;
begin
  Codecs := WicListCodecs;
  All := '';
  Parts := '';
  for I := 0 to High(Codecs) do
    if not Codecs[I].IsEncoder and (Codecs[I].Extensions <> '') then
    begin
      if All <> '' then All := All + ';';
      All := All + ExtToMasks(Codecs[I].Extensions);
      Parts := Parts + '|' + Codecs[I].FriendlyName + '|' + ExtToMasks(Codecs[I].Extensions);
    end;
  Result := AllCaption + '|' + All + Parts;
end;

end.
