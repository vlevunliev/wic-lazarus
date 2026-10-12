program wictest;
{ Конзолен тест за WicImaging.
  Изход (ExitCode) = брой провалени проверки, 0 = всичко е наред.
  Под Wine някои проверки се прескачат (SKIP), защото Wine не чете EXIF от
  JPEG, не изброява метаданни и пренебрегва JPEG ImageQuality.
  На истински Windows всички проверки са задължителни. }
{$mode objfpc}{$H+}
{$codepage utf8}

uses
  Windows, SysUtils, Classes, WicImaging;

var
  Fails: Integer = 0;
  Skips: Integer = 0;
  IsWine: Boolean = False;

procedure Ok(Cond: Boolean; const Msg: string);
begin
  if Cond then
    WriteLn('  OK   ', Msg)
  else
  begin
    WriteLn('  FAIL ', Msg);
    Inc(Fails);
  end;
end;

{ Задължително на Windows, информативно под Wine }
procedure OkWin(Cond: Boolean; const Msg: string);
begin
  if Cond or not IsWine then
    Ok(Cond, Msg)
  else
  begin
    WriteLn('  SKIP ', Msg, '  (ограничение на Wine)');
    Inc(Skips);
  end;
end;

function Px(const Img: TWicImage; X, Y: Integer): LongWord;
begin
  Result := PLongWord(@Img.Pixels[(Y * Img.Width + X) * 4])^;
end;

function Near(A, B: LongWord; Tol: Integer = 40): Boolean;
var
  I: Integer;
begin
  for I := 0 to 3 do
    if Abs(Integer((A shr (I * 8)) and $FF) - Integer((B shr (I * 8)) and $FF)) > Tol then
      Exit(False);
  Result := True;
end;

function ReadFileText(const FN: string): string;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(FN);
    Result := L.Text;
  finally
    L.Free;
  end;
end;

// 'r,g,b' срещу 'r,g,b' с допуск
function NearRgb(const A, B: string; Tol: Integer): Boolean;
var
  LA, LB: TStringList;
  k: Integer;
begin
  LA := TStringList.Create;
  LB := TStringList.Create;
  try
    LA.CommaText := A;
    LB.CommaText := B;
    Result := (LA.Count = 3) and (LB.Count = 3);
    if Result then
      for k := 0 to 2 do
        if Abs(StrToInt(LA[k]) - StrToInt(LB[k])) > Tol then Result := False;
  finally
    LA.Free;
    LB.Free;
  end;
end;

function FileSz(const FN: string): Int64;
var
  F: TSearchRec;
begin
  Result := 0;
  if FindFirst(FN, faAnyFile, F) = 0 then
  begin
    Result := F.Size;
    FindClose(F);
  end;
end;

procedure CheckPhotoInfo(const FN: string; Mandatory: Boolean);
var
  Info: TWicPhotoInfo;
  procedure T(C: Boolean; const M: string);
  begin
    if Mandatory then Ok(C, FN + ': ' + M) else OkWin(C, FN + ': ' + M);
  end;
begin
  Info := WicGetPhotoInfo(FN);
  WriteLn(Format('  %s -> Make=%s Model=%s Date=%s Orient=%d Exp=%g F=%g ISO=%d FL=%g GPS=%s %.6f,%.6f',
    [FN, Info.Make, Info.Model, Info.DateTaken, Info.Orientation, Info.ExposureTime, Info.FNumber,
     Info.ISO, Info.FocalLength, BoolToStr(Info.HasGPS, True), Info.Latitude, Info.Longitude]));
  T(Info.Make = 'Canon', 'Make');
  T(Info.Model = 'EOS 5D Mark IV', 'Model');
  T(Info.Orientation = 6, 'Orientation = 6');
  // под-директориите exif/gps: Wine ги чете само от TIFF
  OkWin(Info.DateTaken = '2026:10:10 17:35:00', FN + ': DateTaken');
  OkWin(Abs(Info.ExposureTime - 0.004) < 1e-9, FN + ': ExposureTime 1/250');
  OkWin(Abs(Info.FNumber - 2.8) < 1e-9, FN + ': FNumber 2.8');
  OkWin(Info.ISO = 400, FN + ': ISO 400');
  OkWin(Abs(Info.FocalLength - 50) < 1e-9, FN + ': FocalLength 50');
  OkWin(Info.HasGPS and (Abs(Info.Latitude - 42.698083) < 1e-5) and
    (Abs(Info.Longitude - 23.323) < 1e-5), FN + ': GPS = София (42.698083, 23.323)');
end;

procedure DumpHas(const FN, Needle, Msg: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    WicDumpMetadata(FN, L);
    OkWin(Pos(Needle, L.Text) > 0, Msg);
  finally
    L.Free;
  end;
end;

{ Записан файл: изправен, с очакваните размери и с основните EXIF полета }
procedure CheckSavedMeta(const FN: string; EW, EH, EOrient: Integer);
var
  Info: TWicPhotoInfo;
  W, H: Integer;
  B: Boolean;
begin
  B := WicGetImageSize(FN, W, H);
  // Изходният файл е JPEG: под Wine не се изправя, затова OkWin
  OkWin(B and (W = EW) and (H = EH), Format('%s: %dx%d (очаквано %dx%d)', [FN, W, H, EW, EH]));
  Info := WicGetPhotoInfo(FN);
  WriteLn(Format('       %s -> Make=%s Model=%s Date=%s Orient=%d ISO=%d Exp=%g F=%g FL=%g GPS=%s %.6f,%.6f',
    [FN, Info.Make, Info.Model, Info.DateTaken, Info.Orientation, Info.ISO, Info.ExposureTime,
     Info.FNumber, Info.FocalLength, BoolToStr(Info.HasGPS, True), Info.Latitude, Info.Longitude]));
  Ok(Info.Orientation = EOrient, Format('%s: ориентация %d', [FN, Info.Orientation]));
  OkWin((Info.Make = 'Canon') and (Info.Model = 'EOS 5D Mark IV'), FN + ': камера');
  OkWin(Info.DateTaken = '2026:10:10 17:35:00', FN + ': дата ' + Info.DateTaken);
  OkWin((Info.ISO = 400) and (Abs(Info.ExposureTime - 0.004) < 1e-6) and
    (Abs(Info.FNumber - 2.8) < 1e-6) and (Abs(Info.FocalLength - 50) < 1e-6), FN + ': ISO/експонация/бленда/фокус');
  OkWin(Info.HasGPS and (Abs(Info.Latitude - 42.698083) < 1e-4) and (Abs(Info.Longitude - 23.323) < 1e-4),
    FN + ': GPS');
end;

var
  Codecs: TWicCodecInfoArray;
  I, O, W, H: Integer;
  B: Boolean;
  Img, Img2: TWicImage;
  L: TStringList;
  HB: HBITMAP;
  BM: Windows.TBitmap;
  S1, S2: Int64;
  UName: string;
  Info: TWicPhotoInfo;
  ExOpt: TWicExportOptions;
  ExRes: TWicExportResult;
begin
  DefaultSystemCodePage := CP_UTF8;   // както прави LazUTF8 в Lazarus
  IsWine := GetProcAddress(GetModuleHandle('ntdll.dll'), 'wine_get_version') <> nil;
  if IsWine then WriteLn('(Wine засечен: някои проверки ще са SKIP)');

  WriteLn('== Структури');
  Ok(SizeOf(TWicPropVariant) = 24, Format('SizeOf(PROPVARIANT) = %d', [SizeOf(TWicPropVariant)]));
  Ok(SizeOf(TWicPropBag2) = 40, Format('SizeOf(PROPBAG2) = %d', [SizeOf(TWicPropBag2)]));

  WriteLn('== Кодеци');
  Codecs := WicListCodecs;
  for I := 0 to High(Codecs) do
    WriteLn(Format('  %s  %-32s %s', [BoolToStr(Codecs[I].IsEncoder, 'ENC', 'DEC'),
      Codecs[I].FriendlyName, Codecs[I].Extensions]));
  Ok(Length(Codecs) > 0, 'има кодеци');
  Ok(WicCanDecode('.jpg') and WicCanDecode('png') and WicCanEncode('.PNG') and WicCanDecode('.tiff'),
    'jpg/png/tiff поддръжка');
  Ok(not WicCanDecode('.xyz'), 'непознато разширение = False');

  WriteLn('== Ориентация 1..8 от TIFF (без загуби; пикселите се сверяват от Python)');
  for O := 1 to 8 do
  begin
    Img := WicLoad(Format('orient%d.tif', [O]));
    if O >= 5 then
      Ok((Img.Width = 300) and (Img.Height = 400), Format('orient%d.tif: %dx%d (очаквано 300x400)', [O, Img.Width, Img.Height]))
    else
      Ok((Img.Width = 400) and (Img.Height = 300), Format('orient%d.tif: %dx%d (очаквано 400x300)', [O, Img.Width, Img.Height]));
    WicSave(Img, Format('out_t%d.png', [O]));
  end;
  Img := WicLoad('orient6.tif', 0, False);
  Ok((Img.Width = 400) and (Img.Height = 300), 'AutoRotate=False оставя суровите размери');

  WriteLn('== Ориентация 1..8 от JPEG (EXIF в APP1)');
  for O := 1 to 8 do
  begin
    Img := WicLoad(Format('orient%d.jpg', [O]));
    if O >= 5 then B := (Img.Width = 300) and (Img.Height = 400)
    else B := (Img.Width = 400) and (Img.Height = 300);
    OkWin(B, Format('orient%d.jpg: %dx%d', [O, Img.Width, Img.Height]));
  end;

  WriteLn('== Смаляване');
  Img := WicLoad('orient1.tif', 100);
  Ok((Img.Width = 100) and (Img.Height = 75), Format('MaxSide=100 -> %dx%d', [Img.Width, Img.Height]));
  Img := WicLoad('orient6.tif', 100);
  Ok((Img.Width = 75) and (Img.Height = 100), Format('MaxSide=100 + rot90 -> %dx%d', [Img.Width, Img.Height]));
  // orient6 = 90° по часовника: оригиналният горен ляв (червен) квадрант отива горе вдясно
  Ok(Near(Px(Img, 69, 5), $FFFFFF00), Format('жълтият маркер от горе вляво е отишъл горе вдясно (%.8x)', [Px(Img, 69, 5)]));
  Ok(Near(Px(Img, 45, 40), $FFFF0000), Format('след смаляване и завъртане горе вдясно е червено (%.8x)', [Px(Img, 45, 40)]));
  Img := WicLoad('orient1.tif', 1000);
  Ok(Img.Width = 400, 'MaxSide по-голям от снимката не уголемява');
  Img := WicResize(WicLoad('orient1.jpg', 0, False), 40, 30, wiFant);
  Ok((Img.Width = 40) and (Img.Height = 30), 'WicResize 40x30');
  Ok(Near(Px(Img, 2, 28), $FF0000FF) and Near(Px(Img, 37, 27), $FFFFFFFF), 'WicResize запазва цветовете');

  WriteLn('== Размер без декодиране');
  B := WicGetImageSize('orient6.tif', W, H);
  Ok(B and (W = 300) and (H = 400), Format('orient6.tif -> %dx%d', [W, H]));
  B := WicGetImageSize('orient6.tif', W, H, False);
  Ok(B and (W = 400), Format('orient6.tif сурово -> %dx%d', [W, H]));
  B := WicGetImageSize('orient6.jpg', W, H);
  OkWin(B and (W = 300) and (H = 400), Format('orient6.jpg -> %dx%d', [W, H]));
  Ok(not WicGetImageSize('nema_go.jpg', W, H), 'липсващ файл -> False');
  Ok(WicGetFrameCount('orient1.jpg') = 1, 'FrameCount = 1');

  WriteLn('== Алфа и формати');
  Img := WicLoad('alpha.png');
  Ok((Img.Width = 64) and (Img.Height = 32), 'alpha.png 64x32');
  Ok(Px(Img, 5, 5) = $800A141E, Format('BGRA пиксел = %.8x (очаквано 800A141E, права алфа)', [Px(Img, 5, 5)]));
  WicSave(Img, 'rt.png');
  WicSave(Img, 'rt.tif');
  WicSave(Img, 'rt.bmp');
  Img2 := WicLoad('rt.png');
  Ok(Px(Img2, 5, 5) = $800A141E, 'PNG round-trip без загуби, вкл. алфа');
  Img2 := WicLoad('rt.tif');
  Ok(Px(Img2, 5, 5) = $800A141E, Format('TIFF round-trip (%.8x)', [Px(Img2, 5, 5)]));
  Img2 := WicLoad('rt.bmp');
  Ok((Img2.Width = 64) and ((Px(Img2, 5, 5) and $FFFFFF) = $0A141E), 'BMP round-trip (цвят)');
  WicSave(WicLoad('orient1.tif'), 'rt.jpg', 0.9);
  Img2 := WicLoad('rt.jpg');
  Ok((Img2.Width = 400) and Near(Px(Img2, 300, 50), $FF00FF00), 'JPEG запис и обратно четене');

  WriteLn('== JPEG качество');
  Img := WicLoad('orient1.jpg', 0, False);
  for I := 0 to High(Img.Pixels) do   // шум, за да има какво да компресира
    if I mod 4 <> 3 then Img.Pixels[I] := Byte(Img.Pixels[I] xor ((QWord(I) * 2654435761) shr 27));
  WicSave(Img, 'q30.jpg', 0.3);
  WicSave(Img, 'q95.jpg', 0.95);
  S1 := FileSz('q30.jpg');
  S2 := FileSz('q95.jpg');
  OkWin((S1 > 0) and (S2 > S1), Format('q30=%d байта < q95=%d байта (ImageQuality действа)', [S1, S2]));

  WriteLn('== Конвертиране и кирилица в пътя');
  UName := 'снимка_ёж.tif';
  WicConvert('orient6.tif', UName, 120);
  B := WicGetImageSize(UName, W, H, False);
  Ok(B and (W = 90) and (H = 120), Format('%s -> %dx%d (изправена и смалена)', [UName, W, H]));
  WicConvert(UName, 'изход.png');
  B := WicGetImageSize('изход.png', W, H);
  Ok(B and (W = 90) and (H = 120), Format('кирилица -> кирилица: %dx%d', [W, H]));

  WriteLn('== HBITMAP');
  Img := WicLoad('alpha.png');
  HB := WicToHBITMAP(Img, True);
  Ok((HB <> 0) and (GetObject(HB, SizeOf(BM), @BM) > 0) and (BM.bmWidth = 64) and (BM.bmBitsPixel = 32),
    'DIB section 64x32x32');
  Ok(PLongWord(PByte(BM.bmBits) + (5 * 64 + 5) * 4)^ = $80050A0F, Format('премултиплициран пиксел = %.8x',
    [PLongWord(PByte(BM.bmBits) + (5 * 64 + 5) * 4)^]));
  DeleteObject(HB);

  WriteLn('== EXIF');
  CheckPhotoInfo('exif6.tif', True);    // базовото IFD Wine го чете от TIFF
  CheckPhotoInfo('orient6.jpg', False); // Wine не чете APP1 от JPEG

  L := TStringList.Create;
  try
    WicDumpMetadata('exif6.tif', L);
    WriteLn('  Пълен dump на exif6.tif (', L.Count, ' реда):');
    for I := 0 to L.Count - 1 do
      WriteLn('    ', L[I]);
    OkWin(L.Count >= 10, 'dump има съдържание');
  finally
    L.Free;
  end;

  WriteLn('== Метаданни при запис (meta_src.jpg: rot90, миниатюра, автор, GPS)');
  OkWin(WicLoadEmbeddedThumbnail('meta_src.jpg', Img), 'изходният файл има вградена миниатюра');

  WicConvert('meta_src.jpg', 'm_none.jpg', 200, 0.9, wmNone);
  B := WicGetImageSize('m_none.jpg', W, H);
  OkWin(B and (W = 150) and (H = 200), Format('wmNone: изправена и смалена %dx%d', [W, H]));
  Ok(WicGetPhotoInfo('m_none.jpg').Make = '', 'wmNone: няма EXIF');
  Ok(not WicGetPhotoInfo('m_none.jpg').HasGPS, 'wmNone: няма GPS');

  WicConvert('meta_src.jpg', 'm_basic.jpg', 200, 0.9, wmBasic);
  CheckSavedMeta('m_basic.jpg', 150, 200, 1);
  DumpHas('m_basic.jpg', 'Ivan Petrov', 'wmBasic: авторът е копиран');

  WicConvert('meta_src.jpg', 'm_basic.tif', 200, 0.9, wmBasic);
  CheckSavedMeta('m_basic.tif', 150, 200, 1);

  WicConvert('meta_src.jpg', 'm_all.jpg', 200, 0.9, wmAll);
  CheckSavedMeta('m_all.jpg', 150, 200, 1);
  OkWin(WicGetPhotoInfo('m_all.jpg').Software = 'PIL test', 'wmAll: Software е копиран');
  DumpHas('m_all.jpg', 'Ivan Petrov', 'wmAll: авторът е копиран');
  DumpHas('m_all.jpg', 'Test shot', 'wmAll: описанието е копирано');
  DumpHas('m_all.jpg', '{ushort=40962} = 150', 'wmAll: PixelXDimension обновен на 150');
  DumpHas('m_all.jpg', '{ushort=40963} = 200', 'wmAll: PixelYDimension обновен на 200');
  OkWin(not WicLoadEmbeddedThumbnail('m_all.jpg', Img), 'wmAll: остарялата миниатюра е махната');

  WicConvert('meta_src.jpg', 'm_all_cross.tif', 200, 0.9, wmAll);
  CheckSavedMeta('m_all_cross.tif', 150, 200, 1);

  // Сурови пиксели без завъртане: ориентацията трябва да се запази
  WicSaveWithMetadataFrom(WicLoad('meta_src.jpg', 0, False), 'm_raw_all.jpg',
    'meta_src.jpg', 0.9, wmAll, False);
  B := WicGetImageSize('m_raw_all.jpg', W, H);
  OkWin(B and (W = 300) and (H = 400), Format('wmAll, PixelsUpright=False: ориентацията е запазена (%dx%d)', [W, H]));
  OkWin(WicLoadEmbeddedThumbnail('m_raw_all.jpg', Img), 'wmAll без промяна: миниатюрата е запазена');
  WicSaveWithMetadataFrom(WicLoad('meta_src.jpg', 0, False), 'm_raw_basic.jpg',
    'meta_src.jpg', 0.9, wmBasic, False);
  OkWin(WicGetPhotoInfo('m_raw_basic.jpg').Orientation = 6, 'wmBasic, PixelsUpright=False: ориентация 6');

  // Редакция в паметта и запис с метаданните на оригинала
  Img := WicLoad('meta_src.jpg');
  for I := 0 to (Img.Width * 4) * 10 - 1 do Img.Pixels[I] := 0;   // черна ивица
  WicSaveWithMetadataFrom(Img, 'm_edited.jpg', 'meta_src.jpg');
  CheckSavedMeta('m_edited.jpg', 300, 400, 1);

  for O := 0 to 1 do
  begin
    if O = 0 then UName := '.heic' else UName := '.jxl';
    if not WicCanEncode(UName) then
    begin
      WriteLn('  INFO няма работещ енкодер за ', UName, ' (регистриран: ',
        BoolToStr(WicCanDecode(UName), 'да', 'не'), ' декодер)');
      Continue;
    end;
    if UName = '.heic' then
    begin
      // HEIF държи EXIF под /ifd: проверяваме го като TIFF
      WicConvert('meta_src.jpg', 'm_basic.heic', 200, 0.85, wmBasic);
      CheckSavedMeta('m_basic.heic', 150, 200, 1);
    end;
    try
      WicConvert('meta_src.jpg', 'm_basic' + UName, 200, 0.85, wmBasic);
      Info := WicGetPhotoInfo('m_basic' + UName);
      B := WicGetImageSize('m_basic' + UName, W, H);
      WriteLn(Format('  INFO %s -> %dx%d Make=%s Model=%s Date=%s ISO=%d GPS=%s %.6f,%.6f',
        [UName, W, H, Info.Make, Info.Model, Info.DateTaken, Info.ISO,
         BoolToStr(Info.HasGPS, True), Info.Latitude, Info.Longitude]));
      L := TStringList.Create;
      try
        WicDumpMetadata('m_basic' + UName, L);
        WriteLn('  INFO ', UName, ' dump: ', L.Count, ' реда');
        for I := 0 to L.Count - 1 do
          WriteLn('       ', L[I]);
      finally
        L.Free;
      end;
    except
      on E: Exception do WriteLn('  INFO ', UName, ' грешка: ', E.Message);
    end;
  end;

  // Защита: източник = цел не бива да унищожава оригинала
  try
    WicConvert('meta_src.jpg', 'meta_src.jpg', 100);
    Ok(False, 'източник = цел трябва да хвърли');
  except
    on E: EWicError do Ok(WicGetImageSize('meta_src.jpg', W, H, False) and (W = 400),
      'източник = цел: отказ, оригиналът е непокътнат');
  end;
  // Защита: ранна грешка не трие чужд съществуващ файл
  L := TStringList.Create;
  try
    L.Text := 'moj fajl';
    L.SaveToFile('keep.xyz');
  finally
    L.Free;
  end;
  try
    WicSave(WicLoad('alpha.png'), 'keep.xyz');
  except
    on EWicError do ;
  end;
  Ok(FileExists('keep.xyz'), 'неуспешен запис не трие съществуващ файл');
  SysUtils.DeleteFile('keep.xyz');

  WriteLn('== Превю и бърза миниатюра (за подбор)');
  Img := WicLoadPreviewW('orient6.jpg');
  OkWin((Img.Width = 300) and (Img.Height = 400), Format('WicLoadPreviewW без вградено превю -> цялото, изправено %dx%d', [Img.Width, Img.Height]));
  Img := WicLoadPreviewW('orient6.jpg', 100);
  OkWin((Img.Width = 75) and (Img.Height = 100), Format('WicLoadPreviewW MaxSide=100 -> %dx%d', [Img.Width, Img.Height]));
  Img := WicLoadThumbW('meta_src.jpg', 400);
  OkWin((Img.Width = 120) and (Img.Height = 160), Format('WicLoadThumbW: вградената 160x120, завъртяна по EXIF -> %dx%d', [Img.Width, Img.Height]));
  Img := WicLoadThumbW('thumb_prerot.jpg', 400);
  OkWin((Img.Width = 120) and (Img.Height = 160), Format('вече завъртяна миниатюра не се върти втори път -> %dx%d', [Img.Width, Img.Height]));
  Img := WicLoadThumbW('meta_src.jpg', 160, 500);
  OkWin((Img.Width = 120) and (Img.Height = 160), Format('миниатюрата е под MinThumbSide -> цялата снимка, смалена %dx%d', [Img.Width, Img.Height]));
  Img := WicLoadThumbW('alpha.png', 32);
  Ok((Img.Width = 32) and (Img.Height = 16), Format('PNG без миниатюра -> смалено %dx%d', [Img.Width, Img.Height]));
  OkWin(WicReadMetadataW('meta_src.jpg', '/app1/ifd/{ushort=315}') = 'Ivan Petrov', 'WicReadMetadataW: автор = ' + WicReadMetadataW('meta_src.jpg', '/app1/ifd/{ushort=315}'));
  Ok(WicReadMetadataW('meta_src.jpg', '/app1/ifd/{ushort=9999}') = '', 'WicReadMetadataW: липсващ таг -> празно');
  Ok(WicReadMetadataW('nema_go.jpg', '/ifd') = '', 'WicReadMetadataW: липсващ файл -> празно, без изключение');
  OkWin(WicGetPhotoInfo('meta_src.jpg').Lens = 'EF50mm f/1.8 STM', 'обектив = ' + WicGetPhotoInfo('meta_src.jpg').Lens);

  WriteLn('== Цветови профил -> sRGB (сверено с littlecms)');
  WriteLn('  adobe.tif: ', WicColorInfoW('adobe.tif'), '   srgb_icc.tif: ', WicColorInfoW('srgb_icc.tif'),
    '   orient1.tif: ', WicColorInfoW('orient1.tif'));
  OkWin(Pos('ICC', WicColorInfoW('adobe.tif')) = 1, 'Adobe RGB профилът е разпознат');
  Ok(WicColorInfoW('srgb_icc.tif') = 'sRGB / без профил', 'вграден sRGB профил = без преобразуване');
  Ok(WicColorInfoW('orient1.tif') = 'sRGB / без профил', 'без профил = sRGB');
  Img := WicLoadBestW('adobe.tif', 0, True, @B);
  OkWin(B, 'Adobe RGB: имало е преобразуване');
  L := TStringList.Create;
  try
    L.Delimiter := ' ';
    L.DelimitedText := Trim(ReadFileText('adobe_expected.txt'));
    for I := 0 to 4 do
    begin
      W := Px(Img, I * 40 + 20, 20);
      UName := Format('%d,%d,%d', [(W shr 16) and $FF, (W shr 8) and $FF, W and $FF]);
      // Цвят 4 (Adobe RGB 40,200,40) е извън гамата на sRGB: всеки модул го изрязва по свой
      // начин (Windows дава 0,202,12, littlecms 0,201,0 - на око един и същ). Затова там допуск 15.
      if I = 3 then
        OkWin(NearRgb(UName, L[I], 15), Format('цвят %d (извън гамата на sRGB): WIC %s, littlecms %s', [I + 1, UName, L[I]]))
      else
        OkWin(NearRgb(UName, L[I], 3), Format('цвят %d: WIC %s, littlecms %s', [I + 1, UName, L[I]]));
    end;
  finally
    L.Free;
  end;
  Img := WicLoadBestW('adobe.tif');
  Ok(Px(Img, 2 * 40 + 20, 20) = $FFC83C3C, 'без ToSrgb пикселите не се пипат (200,60,60)');
  Img := WicLoadBestW('srgb_icc.tif', 0, True, @B);
  Ok(not B and (Px(Img, 2 * 40 + 20, 20) = $FFC83C3C), 'sRGB профил: без преобразуване, пикселите непокътнати');

  WriteLn('== Експорт: един файл');
  ExOpt := WicDefaultExportOptions;
  ExOpt.MaxSide := 200;
  ExRes := WicExportFileW('meta_src.jpg', 'ex_nogps.jpg', ExOpt);
  OkWin((ExRes.Width = 150) and (ExRes.Height = 200), Format('изправено и смалено %dx%d', [ExRes.Width, ExRes.Height]));
  Info := WicGetPhotoInfo('ex_nogps.jpg');
  OkWin((Info.Make = 'Canon') and (Info.ISO = 400) and (Info.DateTaken = '2026:10:10 17:35:00'), 'без GPS: камерата, ISO и датата остават');
  Ok(not Info.HasGPS, 'без GPS: местоположението е махнато');
  DumpHas('ex_nogps.jpg', 'Ivan Petrov', 'без GPS: авторът остава');
  ExOpt.StripGps := False;
  WicExportFileW('meta_src.jpg', 'ex_gps.jpg', ExOpt);
  OkWin(WicGetPhotoInfo('ex_gps.jpg').HasGPS, 'със GPS: местоположението е запазено');
  ExOpt.StripGps := True;
  ExOpt.Metadata := wmBasic;
  WicExportFileW('meta_src.jpg', 'ex_basic_nogps.tif', ExOpt);
  Info := WicGetPhotoInfo('ex_basic_nogps.tif');
  OkWin((Info.Make = 'Canon') and not Info.HasGPS, 'основни без GPS, към TIFF');
  ExOpt.Metadata := wmNone;
  WicExportFileW('meta_src.jpg', 'ex_none.jpg', ExOpt);
  Ok((WicGetPhotoInfo('ex_none.jpg').Make = '') and not WicGetPhotoInfo('ex_none.jpg').HasGPS, 'без метаданни');
  ExOpt := WicDefaultExportOptions;
  ExRes := WicExportFileW('adobe.tif', 'ex_adobe.jpg', ExOpt);
  OkWin(ExRes.ColorConverted, 'Adobe RGB -> sRGB при експорт');
  OkWin(WicColorInfoW('ex_adobe.jpg') = 'sRGB / без профил', 'резултатът е без стария профил: ' + WicColorInfoW('ex_adobe.jpg'));
  ExOpt.ToSrgb := False;
  ExRes := WicExportFileW('adobe.tif', 'ex_adobe_keep.tif', ExOpt);
  Ok(not ExRes.ColorConverted, 'без ToSrgb: без преобразуване');
  for UName in ['ex_nogps.jpg', 'ex_gps.jpg', 'ex_basic_nogps.tif', 'ex_none.jpg', 'ex_adobe.jpg', 'ex_adobe_keep.tif'] do
    SysUtils.DeleteFile(UName);

  WriteLn('== Черна вградена миниатюра (HDR от телефон)');
  Img := WicLoadThumbW('black_thumb.jpg', 160);
  B := (Img.Width = 120) and (Img.Height = 160);
  OkWin(B and not Near(Px(Img, 60, 80), $FF000000, 20), Format('черната миниатюра е отхвърлена, взета е снимката: %dx%d, пиксел %.8x',
    [Img.Width, Img.Height, Px(Img, 60, 80)]));
  Img := WicLoadThumbW('meta_src.jpg', 400);
  OkWin((Img.Width = 120) and (Img.Height = 160), 'истинската миниатюра продължава да се ползва');

  WriteLn('== Най-добро изображение и декодер за RAW');
  Img := WicLoadBestW('orient6.jpg', 100);
  OkWin((Img.Width = 75) and (Img.Height = 100), Format('WicLoadBestW без превю = смаленото изображение %dx%d', [Img.Width, Img.Height]));
  Img := WicLoadBestW('orient6.tif');
  Ok((Img.Width = 300) and (Img.Height = 400), Format('WicLoadBestW пълен размер, изправено %dx%d', [Img.Width, Img.Height]));
  Codecs := WicListCodecs;
  B := False;
  for I := 0 to High(Codecs) do
    if not Codecs[I].IsEncoder and (Pos('.png', Codecs[I].Extensions) > 0) and
       not IsEqualGUID(Codecs[I].Clsid, GUID_NULL) then B := True;
  Ok(B, 'кодеците носят CLSID');
  B := False;
  for I := 0 to High(Codecs) do
    if IsEqualGUID(Codecs[I].Clsid, CLSID_WICRawImageDecoder) then B := True;
  if B then WriteLn('  INFO Raw Image Decoder е наличен: RAW пикселите идват от него')
  else WriteLn('  INFO Raw Image Decoder го няма на тази машина');

  WriteLn('== Миниатюра и грешки');
  Ok(not WicLoadEmbeddedThumbnail('alpha.png', Img), 'PNG без вградена миниатюра -> False');
  try
    WicSave(Img2, 'x.xyz');
    Ok(False, 'непознат формат хвърля EWicError');
  except
    on E: EWicError do Ok(not FileExists('x.xyz'), 'непознат формат: ' + E.Message);
  end;
  try
    WicLoad('nema_go.jpg');
    Ok(False, 'липсващ файл хвърля');
  except
    on E: EWicError do Ok(True, 'липсващ файл: ' + E.Message);
  end;
  try
    WicLoad('wictest.lpr');
    Ok(False, 'не-изображение хвърля');
  except
    on E: EWicError do Ok(True, 'не-изображение: ' + E.Message);
  end;

  WriteLn;
  if Fails = 0 then
    WriteLn('#### ALL GREEN #### (', Skips, ' SKIP)')
  else
    WriteLn('#### ', Fails, ' FAIL #### (', Skips, ' SKIP)');
  ExitCode := Fails;
end.
