program wicprobe;
{ Диагностика: отваря файл с ВСЕКИ регистриран WIC декодер поотделно и показва какво дава всеки.
    wicprobe.exe снимка.dng [друга.ARW ...]
  Изход: кой декодер избира Windows сам, кадри и размери, превю, миниатюра, време за декодиране. }
{$mode objfpc}{$H+}{$codepage utf8}
uses Windows, SysUtils, WicImaging;


const
  GUID_VendorMicrosoft: TGUID        = '{F0E749CA-EDEF-4589-A73A-EE0E626A2A2B}';
  GUID_VendorMicrosoftBuiltIn: TGUID = '{257A30FD-06B6-462B-AEA4-63F70B86E533}';
  WICDecoder = 1;

function CoInitializeEx(p: Pointer; c: DWORD): HRESULT; stdcall; external 'ole32.dll';
function CommandLineToArgvW(lpCmdLine: PWideChar; out pNumArgs: Integer): PPWideChar; stdcall; external 'shell32.dll';

function Str(const Info: IWICComponentInfo; Which: Integer): string;
var
  n: UINT;
  b: UnicodeString;
  ci: IWICBitmapCodecInfo;
begin
  Result := '';
  n := 0;
  if Which = 0 then Info.GetFriendlyName(0, nil, n)
  else if Supports(Info, IWICBitmapCodecInfo, ci) then ci.GetFileExtensions(0, nil, n);
  if n = 0 then Exit;
  SetLength(b, n);
  if Which = 0 then Info.GetFriendlyName(n, PWideChar(b), n)
  else ci.GetFileExtensions(n, PWideChar(b), n);
  Result := UTF8Encode(UnicodeString(PWideChar(b)));
end;

function VendorName(const G: TGUID): string;
begin
  if IsEqualGUID(G, GUID_VendorMicrosoft) or IsEqualGUID(G, GUID_VendorMicrosoftBuiltIn) then Result := 'Microsoft'
  else Result := 'доставчик ' + GUIDToString(G);
end;

function CoCreateInstance(const clsid: TGUID; unkOuter: Pointer; dwClsContext: DWORD;
  const iid: TGUID; out pv): HRESULT; stdcall; external 'ole32.dll';

function Sz(const S: IWICBitmapSource): string;
var w, h: UINT;
begin
  if (S <> nil) and Succeeded(S.GetSize(w, h)) then Result := Format('%d x %d (%.1f MP)', [w, h, w * h / 1e6])
  else Result := '-';
end;

function TimedDecode(const S: IWICBitmapSource): string;
var
  F: IWICImagingFactory;
  C: IWICFormatConverter;
  w, h: UINT;
  buf: array of Byte;
  t: QWord;
  hr: HRESULT;
begin
  Result := '-';
  if (S = nil) or Failed(S.GetSize(w, h)) then Exit;
  F := WicCreateFactory;
  F.CreateFormatConverter(C);
  if Failed(C.Initialize(S, GUID_WICPixelFormat32bppBGRA, 0, nil, 0, 0)) then Exit('конвертирането отказа');
  SetLength(buf, QWord(w) * h * 4);
  t := GetTickCount64;
  hr := C.CopyPixels(nil, w * 4, Length(buf), @buf[0]);
  if Failed(hr) then Result := 'грешка $' + IntToHex(hr, 8)
  else Result := Format('%d ms', [GetTickCount64 - t]);
end;

procedure Describe(const D: IWICBitmapDecoder; Full: Boolean);
var
  n, i: UINT;
  Fr: IWICBitmapFrameDecode;
  P, T: IWICBitmapSource;
  hr: HRESULT;
begin
  n := 0;
  D.GetFrameCount(n);
  WriteLn('      кадри: ', n);
  for i := 0 to n - 1 do
  begin
    if i > 5 then begin WriteLn('      ...'); Break; end;
    Fr := nil;
    if Failed(D.GetFrame(i, Fr)) then begin WriteLn('      кадър ', i, ': GetFrame отказа'); Continue; end;
    Write('      кадър ', i, ': ', Sz(Fr));
    if Full then Write('   пълно декодиране: ', TimedDecode(Fr));
    WriteLn;
    T := nil;
    if Succeeded(Fr.GetThumbnail(T)) and (T <> nil) then WriteLn('        миниатюра на кадъра: ', Sz(T));
  end;
  P := nil;
  hr := D.GetPreview(P);
  if Succeeded(hr) and (P <> nil) then
  begin
    Write('      превю (GetPreview): ', Sz(P));
    if Full then Write('   декодиране: ', TimedDecode(P));
    WriteLn;
  end
  else WriteLn('      превю: няма ($', IntToHex(hr, 8), ')');
  T := nil;
  if Succeeded(D.GetThumbnail(T)) and (T <> nil) then WriteLn('      миниатюра на файла: ', Sz(T));
end;

procedure Probe(const FN: UnicodeString);
var
  F: IWICImagingFactory;
  D: IWICBitmapDecoder;
  En: IWicEnumUnknown;
  Unk: IUnknown;
  Info: IWICBitmapDecoderInfo;
  CInfo: IWICComponentInfo;
  S: IWICStream;
  got: ULONG;
  clsid, vendor, chosen: TGUID;
  hr: HRESULT;
  ext: string;
  matches: BOOL;
begin
  WriteLn('=================================================================');
  WriteLn(UTF8Encode(FN));
  if not FileExists(FN) then
  begin
    WriteLn('   ФАЙЛЪТ НЕ Е НАМЕРЕН (текуща папка: ', UTF8Encode(UnicodeString(GetCurrentDir)), ')');
    Exit;
  end;
  F := WicCreateFactory;
  ext := LowerCase(UTF8Encode(UnicodeString(ExtractFileExt(FN))));

  WriteLn('-- какво избира Windows сам (CreateDecoderFromFilename):');
  FillChar(chosen, SizeOf(chosen), 0);
  hr := F.CreateDecoderFromFilename(PWideChar(FN), nil, GENERIC_READ, 0, D);
  if Failed(hr) then WriteLn('   отказ $', IntToHex(hr, 8))
  else
  begin
    if Succeeded(D.GetDecoderInfo(Unk)) and Supports(Unk, IWICComponentInfo, CInfo) then
    begin
      CInfo.GetCLSID(chosen);
      CInfo.GetVendorGUID(vendor);
      WriteLn('   ', Str(CInfo, 0), '  [', VendorName(vendor), ', ', GUIDToString(chosen), ']');
    end;
    Describe(D, True);
  end;

  WriteLn('-- всеки декодер поотделно:');
  if Failed(F.CreateComponentEnumerator(WICDecoder, 0, En)) then Exit;
  while (En.Next(1, Unk, @got) = S_OK) and (got = 1) do
  begin
    if not Supports(Unk, IWICBitmapDecoderInfo, Info) then Continue;
    Info.GetCLSID(clsid);
    Info.GetVendorGUID(vendor);
    // само тези, които разпознават съдържанието на файла
    S := nil;
    F.CreateStream(S);
    if Failed(S.InitializeFromFilename(PWideChar(FN), GENERIC_READ)) then Continue;
    matches := False;
    Info.MatchesPattern(S, matches);
    if not matches and (Pos(ext, LowerCase(Str(Info, 1))) = 0) then Continue;
    Write('   ', Str(Info, 0), '  [', VendorName(vendor), ', ', GUIDToString(clsid), ']');
    if IsEqualGUID(clsid, chosen) then Write('  <- избран от Windows');
    if not matches then Write('  (разширението съвпада, съдържанието - не)');
    WriteLn;
    D := nil;
    hr := Info.CreateInstance(D);
    if Failed(hr) then
      hr := CoCreateInstance(clsid, nil, 1, IWICBitmapDecoder, D);
    if Failed(hr) then begin WriteLn('      не се създава: $', IntToHex(hr, 8)); Continue; end;
    S := nil;
    F.CreateStream(S);
    S.InitializeFromFilename(PWideChar(FN), GENERIC_READ);
    hr := D.Initialize(S, 0);
    if Failed(hr) then begin WriteLn('      Initialize отказа $', IntToHex(hr, 8)); Continue; end;
    Describe(D, not IsEqualGUID(clsid, chosen));
  end;
end;

var
  argv: PPWideChar;
  n, i: Integer;
begin
  SetConsoleOutputCP(CP_UTF8);
  CoInitializeEx(nil, 2);
  argv := CommandLineToArgvW(GetCommandLineW, n);
  if n < 2 then begin WriteLn('употреба: wicprobe <файл> [<файл> ...]'); Halt(2); end;
  for i := 1 to n - 1 do
    try
      Probe(UnicodeString(argv[i]));
    except
      on E: Exception do WriteLn('   ГРЕШКА: ', E.Message);
    end;
end.
