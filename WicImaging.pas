{ ============================================================================
  WicImaging.pas - Windows Imaging Component (WIC) за Free Pascal / Lazarus

  Безплатните кодеци на Windows: JPEG, PNG, TIFF, BMP, GIF, ICO, JPEG-XR,
  а с разширенията от Store и HEIC/HEIF, WebP, AVIF, RAW от фотоапарати.
  Никакви външни DLL-и: всичко е в windowscodecs.dll, налично от Vista насам.

  Самостоятелен unit: не ползва ActiveX/ComObj/LCL, само Windows + SysUtils.
  За TBitmap виж WicLCL.pas.

  Пиксели в паметта: 32 bpp BGRA, права (непремултиплицирана) алфа,
  отгоре надолу, stride = Width * 4. Същото като TRawImage BGRA в LCL.

  COM: всяка публична функция сама вика CoInitializeEx/CoUninitialize
  балансирано и работи в STA и MTA нишки, както и когато LCL вече е
  инициализирал OLE.
  ============================================================================ }
unit WicImaging;

{$mode objfpc}{$H+}
{$PACKRECORDS C}

interface

uses
  Windows, SysUtils, Classes;

type
  EWicError = class(Exception)
  public
    HR: HRESULT;
    constructor CreateHR(const Step: string; AHR: HRESULT);
  end;

  { Декодирано изображение в паметта }
  TWicImage = record
    Width, Height: Integer;
    Pixels: array of Byte;   // BGRA, Width*Height*4 байта
  end;

  TWicCodecInfo = record
    FriendlyName: string;
    Extensions: string;      // напр. '.jpeg,.jpe,.jpg,.jfif,.exif'
    MimeTypes: string;
    ContainerFormat: TGUID;
    Clsid: TGUID;            // CLSID на самия кодек
    IsEncoder: Boolean;      // False = декодер (четене), True = енкодер (запис)
  end;
  TWicCodecInfoArray = array of TWicCodecInfo;

  { Най-ползваните EXIF данни от снимка. 0/'' = липсва. }
  TWicPhotoInfo = record
    Make, Model, Software: string;
    Lens: string;            // модел на обектива (EXIF LensModel)
    DateTaken: string;       // EXIF формат 'YYYY:MM:DD HH:MM:SS'
    Orientation: Integer;    // 1..8
    ExposureTime: Double;    // секунди, напр. 0.004 = 1/250
    FNumber: Double;         // напр. 2.8
    FocalLength: Double;     // мм
    ISO: Integer;
    HasGPS: Boolean;
    Latitude, Longitude: Double;  // десетични градуси, юг/запад = отрицателни
  end;

  TWicInterpolation = (wiNearest, wiLinear, wiCubic, wiFant, wiHighQualityCubic);

  TWicMetadataMode = (wmNone, wmBasic, wmAll);

{ --- Четене ------------------------------------------------------------------ }

{ Зарежда първия кадър. MaxSide > 0 смалява пропорционално, така че по-дългата
  страна да е <= MaxSide (никога не уголемява). AutoRotate прилага EXIF
  ориентацията, т.е. снимките от телефон излизат изправени. }
function WicLoad(const FileName: string; MaxSide: Integer = 0;
  AutoRotate: Boolean = True): TWicImage;

{ Същите, с UnicodeString път: за код с $modeswitch unicodestrings, където
  string е UnicodeString и превръщане към AnsiString би загубило символи. }
function WicLoadW(const FileName: UnicodeString; MaxSide: Integer = 0;
  AutoRotate: Boolean = True): TWicImage;
function WicGetPhotoInfoW(const FileName: UnicodeString): TWicPhotoInfo;

{ Размери без декодиране на пикселите: чете само хедъра, много бързо. }
function WicGetImageSize(const FileName: string; out W, H: Integer;
  AutoRotate: Boolean = True): Boolean;

{ Брой кадри (многостраничен TIFF, анимиран GIF). }
function WicGetFrameCount(const FileName: string): Integer;

{ Зарежда конкретен кадър (0-базиран). }
function WicLoadFrame(const FileName: string; FrameIndex: Integer;
  MaxSide: Integer = 0; AutoRotate: Boolean = True): TWicImage;

{ Превю: за RAW е вграденият JPEG в пълен размер (Decoder.GetPreview), без
  демозаикинг - многократно по-бързо от пълното декодиране. Форматите без превю
  (JPEG, PNG, HEIC...) се декодират нормално. MaxSide и AutoRotate като при WicLoad.
  Ориентацията на превюто: прилага се само ако превюто е със същите пропорции като
  суровия кадър (иначе декодерът вече го е завъртял); 180° не се различава така. }
function WicLoadPreviewW(const FileName: UnicodeString; MaxSide: Integer = 0;
  AutoRotate: Boolean = True): TWicImage;

{ Най-доброто изображение до MaxSide (0 = пълен размер): вграденото превю, ако е
  достатъчно голямо (поне 90% от нужното), иначе истинският кадър, смален. За RAW с малко
  превю (DNG от Adobe: 1024 px) това е пълното декодиране на сензора - секунди, не ms.
  За JPEG/PNG/HEIC е същото като WicLoadW. }
function WicLoadBestW(const FileName: UnicodeString; MaxSide: Integer = 0;
  ToSrgb: Boolean = False; WasConverted: PBoolean = nil): TWicImage;

{ Само за проверка: описание на цветовия профил на кадъра - 'sRGB / без профил',
  'ICC профил (N байта)' или 'EXIF Adobe RGB'. }
function WicColorInfoW(const FileName: UnicodeString): string;

{ Бърза миниатюра за решетка: вградената EXIF миниатюра, ако дългата ѝ страна е
  поне MinThumbSide; иначе превюто (RAW) или самото изображение, смалени до MaxSide. }
function WicLoadThumbW(const FileName: UnicodeString; MaxSide: Integer;
  MinThumbSide: Integer = 120): TWicImage;

{ Стойност от метаданните като текст ('' ако я няма), напр.
  WicReadMetadataW(FN, '/xmp/xmp:Rating') или WicReadMetadataW(FN, 'System.Rating'). }
function WicReadMetadataW(const FileName: UnicodeString; const Path: string): string;

{ Вградената EXIF миниатюра (обикновено около 160x120), ако има такава.
  Зарежда се мигновено, без да се декодира цялата снимка. }
function WicLoadEmbeddedThumbnail(const FileName: string;
  out Img: TWicImage): Boolean;

{ --- Запис ------------------------------------------------------------------- }

{ Форматът се избира по разширението (.jpg .png .tif .bmp .jxr .heic .webp...).
  Quality 0..1 важи за JPEG, JPEG-XR и HEIF. }
procedure WicSave(const Img: TWicImage; const FileName: string;
  Quality: Single = 0.9);

{ Конвертиране с едно извикване: зарежда, изправя, смалява и записва.
  Metadata:
    wmNone  - чист файл без EXIF/GPS (за публикуване, без да издаваш локация)
    wmBasic - камера, дата, експонация, GPS, автор, заглавие, ключови думи;
              работи и между формати (JPEG -> HEIC/TIFF/JXL)
    wmAll   - всички блокове 1:1 (вкл. MakerNote, XMP, IPTC), когато
              форматът е същият; при различен формат пада до wmBasic
  Ориентацията винаги става 1, защото пикселите вече са изправени. }
procedure WicConvert(const SrcFile, DstFile: string; MaxSide: Integer = 0;
  Quality: Single = 0.9; Metadata: TWicMetadataMode = wmBasic);

{ --- Експорт ------------------------------------------------------------------- }

type
  TWicExportOptions = record
    MaxSide: Integer;            // 0 = пълен размер
    Quality: Single;             // 0..1 за JPEG/HEIF
    Metadata: TWicMetadataMode;
    StripGps: Boolean;           // всички метаданни без местоположението
    ToSrgb: Boolean;             // Adobe RGB / Display P3 -> sRGB (за мрежата и телефоните)
  end;

  TWicExportResult = record
    Width, Height: Integer;
    ColorConverted: Boolean;
  end;

function WicDefaultExportOptions: TWicExportOptions;

{ Един файл за експорт: най-доброто изображение (за RAW - пълното декодиране, ако превюто е
  малко), изправено, смалено, в sRGB, записано във формата по разширението на DstFile, с
  метаданните на източника. Хвърля EWicError; при грешка не оставя полузаписан файл. }
function WicExportFileW(const SrcFile, DstFile: UnicodeString;
  const Opt: TWicExportOptions): TWicExportResult;

{ Записва вече обработено изображение с метаданните на друг файл:
  Img := WicLoad(Src); ...редакция...; WicSaveWithMetadataFrom(Img, Dst, Src).
  PixelsUpright=False, ако си зареждал с AutoRotate=False и пикселите
  още са в суровата ориентация (тогава тя се копира). }
procedure WicSaveWithMetadataFrom(const Img: TWicImage; const DstFile,
  MetadataSrcFile: string; Quality: Single = 0.9;
  Metadata: TWicMetadataMode = wmBasic; PixelsUpright: Boolean = True);

{ --- Обработка в паметта ----------------------------------------------------- }

function WicResize(const Img: TWicImage; NewWidth, NewHeight: Integer;
  Mode: TWicInterpolation = wiHighQualityCubic): TWicImage;

{ Прилага EXIF ориентация 1..8 върху пикселите (WicLoad го прави сам). }
procedure WicApplyOrientation(var Img: TWicImage; Orientation: Integer);

{ 32-битов DIB section за чист WinAPI. Premultiply=True за AlphaBlend. }
function WicToHBITMAP(const Img: TWicImage; Premultiply: Boolean = False): HBITMAP;

{ --- Метаданни и кодеци ------------------------------------------------------ }

function WicGetPhotoInfo(const FileName: string): TWicPhotoInfo;

(* Всички метаданни като редове 'път = стойност', напр.
   '/app1/ifd/{ushort=271} = Canon'. Пътищата важат за GetMetadataByName. *)
procedure WicDumpMetadata(const FileName: string; Lines: TStrings);

{ Всички кодеци, регистрирани на тази машина, вкл. от Store (HEIF, WebP, RAW). }
function WicListCodecs: TWicCodecInfoArray;

{ Може ли тази машина да чете / пише дадено разширение ('.heic', 'webp'...). }
function WicCanDecode(const Ext: string): Boolean;
function WicCanEncode(const Ext: string): Boolean;

{ Container GUID по разширение, напр. '.jpg' -> GUID_ContainerFormatJpeg }
function WicContainerForExt(const Ext: string): TGUID;

const
  { „Microsoft Raw Image Decoder“ (Raw Image Extension от Store). За някои формати Windows
    по подразбиране избира друг декодер: за .dng старият „DNG Decoder“, който дава само
    вграденото превю (1024 px) вместо пълния RAW. Пикселите затова се взимат от този,
    когато поддържа разширението. CLSID-ът е от регистъра на реална машина (wicprobe). }
  CLSID_WICRawImageDecoder: TGUID = '{41945702-8302-44A6-9445-AC98E8AFA086}';

  GUID_ContainerFormatBmp:  TGUID = '{0AF1D87E-FCFE-4188-BDEB-A7906471CBE3}';
  GUID_ContainerFormatPng:  TGUID = '{1B7CFAF4-713F-473C-BBCD-6137425FAEAF}';
  GUID_ContainerFormatIco:  TGUID = '{A3A860C4-338F-4C17-919A-FBA4B5628F21}';
  GUID_ContainerFormatJpeg: TGUID = '{19E4A5AA-5662-4FC5-A0C0-1758028E1057}';
  GUID_ContainerFormatTiff: TGUID = '{163BCC30-E2E9-4F0B-961D-A3E9FDB788A3}';
  GUID_ContainerFormatGif:  TGUID = '{1F8A5601-7D4D-4CBD-9C82-1BC8D4EEB9A5}';
  GUID_ContainerFormatWmp:  TGUID = '{57A37CAA-367A-4540-916B-F183C5093A4B}';
  GUID_ContainerFormatHeif: TGUID = '{E1E62521-6787-405B-A339-500715B5763F}';
  GUID_ContainerFormatWebp: TGUID = '{E094B0E2-67F2-45B3-B0EA-115337CA7CF3}';
  GUID_ContainerFormatDds:  TGUID = '{9967CB95-2E85-4AC8-8CA2-83D7CCD425C9}';

  GUID_WICPixelFormat24bppBGR:   TGUID = '{6FDDC324-4E03-4BFE-B185-3D77768DC90C}';
  GUID_WICPixelFormat32bppBGR:   TGUID = '{6FDDC324-4E03-4BFE-B185-3D77768DC90E}';
  GUID_WICPixelFormat32bppBGRA:  TGUID = '{6FDDC324-4E03-4BFE-B185-3D77768DC90F}';
  GUID_WICPixelFormat32bppPBGRA: TGUID = '{6FDDC324-4E03-4BFE-B185-3D77768DC910}';

{ ============================================================================
  Сурови COM декларации. Публични са, за да можеш да стигнеш и до неща,
  които обвивките отгоре не покриват. Редът на методите повтаря wincodec.h
  и не бива да се пипа.
  ============================================================================ }
type
  PWICRect = ^TWICRect;
  TWICRect = record X, Y, Width, Height: Integer; end;

  PWicPropVariant = ^TWicPropVariant;
  TWicPropVariant = record
    vt: Word;
    wReserved1, wReserved2, wReserved3: Word;
    case Integer of
      0:  (bVal: Byte);
      1:  (iVal: SmallInt);
      2:  (uiVal: Word);
      3:  (lVal: LongInt);
      4:  (ulVal: LongWord);
      5:  (hVal: Int64);
      6:  (uhVal: QWord);
      7:  (fltVal: Single);
      8:  (dblVal: Double);
      9:  (pszVal: PAnsiChar);
      10: (pwszVal: PWideChar);
      11: (punkVal: Pointer);
      12: (cElems: LongWord; pElems: Pointer);   // вектори и BLOB
      13: (filetime: TFileTime);
      14: (boolVal: SmallInt);
  end;

  PWicPropBag2 = ^TWicPropBag2;
  TWicPropBag2 = record
    dwType: DWORD;
    vt: Word;
    cfType: Word;
    dwHint: DWORD;
    pstrName: PWideChar;
    clsid: TGUID;
  end;

  IWicEnumString = interface(IUnknown)
    ['{00000101-0000-0000-C000-000000000046}']
    function Next(celt: ULONG; out rgelt: PWideChar; pceltFetched: PULONG): HRESULT; stdcall;
    function Skip(celt: ULONG): HRESULT; stdcall;
    function Reset: HRESULT; stdcall;
    function Clone(out ppenum: IWicEnumString): HRESULT; stdcall;
  end;

  IWicEnumUnknown = interface(IUnknown)
    ['{00000100-0000-0000-C000-000000000046}']
    function Next(celt: ULONG; out rgelt: IUnknown; pceltFetched: PULONG): HRESULT; stdcall;
    function Skip(celt: ULONG): HRESULT; stdcall;
    function Reset: HRESULT; stdcall;
    function Clone(out ppenum: IWicEnumUnknown): HRESULT; stdcall;
  end;

  IWicPropertyBag2 = interface(IUnknown)
    ['{22F55882-280B-11D0-A8A9-00A0C90C2004}']
    function Read(cProperties: ULONG; pPropBag: PWicPropBag2; pErrLog: IUnknown;
      pvarValue: Pointer; phrError: Pointer): HRESULT; stdcall;
    function Write(cProperties: ULONG; pPropBag: PWicPropBag2;
      pvarValue: Pointer): HRESULT; stdcall;
    function CountProperties(out pcProperties: ULONG): HRESULT; stdcall;
    function GetPropertyInfo(iProperty, cProperties: ULONG; pPropBag: PWicPropBag2;
      out pcProperties: ULONG): HRESULT; stdcall;
    function LoadObject(pstrName: PWideChar; dwHint: DWORD; pUnkObject: IUnknown;
      pErrLog: IUnknown): HRESULT; stdcall;
  end;

  IWICMetadataQueryReader = interface(IUnknown)
    ['{30989668-E1C9-4597-B395-458EEDB808DF}']
    function GetContainerFormat(out pguidContainerFormat: TGUID): HRESULT; stdcall;
    function GetLocation(cchMaxLength: UINT; wzNamespace: PWideChar;
      out pcchActualLength: UINT): HRESULT; stdcall;
    function GetMetadataByName(wzName: PWideChar; pvarValue: PWicPropVariant): HRESULT; stdcall;
    function GetEnumerator(out ppIEnumString: IWicEnumString): HRESULT; stdcall;
  end;

  IWICMetadataQueryWriter = interface(IWICMetadataQueryReader)
    ['{A721791A-0DEF-4D06-BD91-2118BF1DB10B}']
    function SetMetadataByName(wzName: PWideChar; pvarValue: PWicPropVariant): HRESULT; stdcall;
    function RemoveMetadataByName(wzName: PWideChar): HRESULT; stdcall;
  end;

  IWICMetadataBlockReader = interface(IUnknown)
    ['{FEAA2A8D-B3F3-43E4-B25C-D1DE990A1AE1}']
    function GetContainerFormat(out pguidContainerFormat: TGUID): HRESULT; stdcall;
    function GetCount(out pcCount: UINT): HRESULT; stdcall;
    function GetReaderByIndex(nIndex: UINT; out ppIMetadataReader: IUnknown): HRESULT; stdcall;
    function GetEnumerator(out ppIEnumMetadata: IUnknown): HRESULT; stdcall;
  end;

  IWICMetadataBlockWriter = interface(IWICMetadataBlockReader)
    ['{08FB9676-B444-41E8-8DBE-6A53A542BFF1}']
    function InitializeFromBlockReader(pIMDBlockReader: IWICMetadataBlockReader): HRESULT; stdcall;
    function GetWriterByIndex(nIndex: UINT; out ppIMetadataWriter: IUnknown): HRESULT; stdcall;
    function AddWriter(pIMetadataWriter: IUnknown): HRESULT; stdcall;
    function SetWriterByIndex(nIndex: UINT; pIMetadataWriter: IUnknown): HRESULT; stdcall;
    function RemoveWriterByIndex(nIndex: UINT): HRESULT; stdcall;
  end;

  IWICBitmapSource = interface(IUnknown)
    ['{00000120-A8F2-4877-BA0A-FD2B6645FB94}']
    function GetSize(out puiWidth, puiHeight: UINT): HRESULT; stdcall;
    function GetPixelFormat(out pPixelFormat: TGUID): HRESULT; stdcall;
    function GetResolution(out pDpiX, pDpiY: Double): HRESULT; stdcall;
    function CopyPalette(pIPalette: IUnknown): HRESULT; stdcall;
    function CopyPixels(prc: PWICRect; cbStride, cbBufferSize: UINT;
      pbBuffer: PByte): HRESULT; stdcall;
  end;

  IWICBitmap = interface(IWICBitmapSource)
    ['{00000121-A8F2-4877-BA0A-FD2B6645FB94}']
    function Lock(prcLock: PWICRect; flags: DWORD; out ppILock: IUnknown): HRESULT; stdcall;
    function SetPalette(pIPalette: IUnknown): HRESULT; stdcall;
    function SetResolution(dpiX, dpiY: Double): HRESULT; stdcall;
  end;

  IWICFormatConverter = interface(IWICBitmapSource)
    ['{00000301-A8F2-4877-BA0A-FD2B6645FB94}']
    function Initialize(pISource: IWICBitmapSource; const dstFormat: TGUID;
      dither: DWORD; pIPalette: IUnknown; alphaThresholdPercent: Double;
      paletteTranslate: DWORD): HRESULT; stdcall;
    function CanConvert(const srcPixelFormat, dstPixelFormat: TGUID;
      out pfCanConvert: BOOL): HRESULT; stdcall;
  end;

  IWICBitmapScaler = interface(IWICBitmapSource)
    ['{00000302-A8F2-4877-BA0A-FD2B6645FB94}']
    function Initialize(pISource: IWICBitmapSource; uiWidth, uiHeight: UINT;
      mode: DWORD): HRESULT; stdcall;
  end;

  IWICBitmapFrameDecode = interface(IWICBitmapSource)
    ['{3B16811B-6A43-4EC9-A813-3D930C13B940}']
    function GetMetadataQueryReader(out ppIMetadataQueryReader: IWICMetadataQueryReader): HRESULT; stdcall;
    function GetColorContexts(cCount: UINT; ppIColorContexts: Pointer;
      out pcActualCount: UINT): HRESULT; stdcall;
    function GetThumbnail(out ppIThumbnail: IWICBitmapSource): HRESULT; stdcall;
  end;

  IWICBitmapDecoder = interface(IUnknown)
    ['{9EDDE9E7-8DEE-47EA-99DF-E6FAF2ED44BF}']
    function QueryCapability(pIStream: IUnknown; out pdwCapability: DWORD): HRESULT; stdcall;
    function Initialize(pIStream: IUnknown; cacheOptions: DWORD): HRESULT; stdcall;
    function GetContainerFormat(out pguidContainerFormat: TGUID): HRESULT; stdcall;
    function GetDecoderInfo(out ppIDecoderInfo: IUnknown): HRESULT; stdcall;
    function CopyPalette(pIPalette: IUnknown): HRESULT; stdcall;
    function GetMetadataQueryReader(out ppIMetadataQueryReader: IWICMetadataQueryReader): HRESULT; stdcall;
    function GetPreview(out ppIBitmapSource: IWICBitmapSource): HRESULT; stdcall;
    function GetColorContexts(cCount: UINT; ppIColorContexts: Pointer;
      out pcActualCount: UINT): HRESULT; stdcall;
    function GetThumbnail(out ppIThumbnail: IWICBitmapSource): HRESULT; stdcall;
    function GetFrameCount(out pCount: UINT): HRESULT; stdcall;
    function GetFrame(index: UINT; out ppIBitmapFrame: IWICBitmapFrameDecode): HRESULT; stdcall;
  end;

  IWICBitmapFrameEncode = interface(IUnknown)
    ['{00000105-A8F2-4877-BA0A-FD2B6645FB94}']
    function Initialize(pIEncoderOptions: IWicPropertyBag2): HRESULT; stdcall;
    function SetSize(uiWidth, uiHeight: UINT): HRESULT; stdcall;
    function SetResolution(dpiX, dpiY: Double): HRESULT; stdcall;
    function SetPixelFormat(var pPixelFormat: TGUID): HRESULT; stdcall;
    function SetColorContexts(cCount: UINT; ppIColorContext: Pointer): HRESULT; stdcall;
    function SetPalette(pIPalette: IUnknown): HRESULT; stdcall;
    function SetThumbnail(pIThumbnail: IWICBitmapSource): HRESULT; stdcall;
    function WritePixels(lineCount, cbStride, cbBufferSize: UINT; pbPixels: PByte): HRESULT; stdcall;
    function WriteSource(pIBitmapSource: IWICBitmapSource; prc: PWICRect): HRESULT; stdcall;
    function Commit: HRESULT; stdcall;
    function GetMetadataQueryWriter(out ppIMetadataQueryWriter: IWICMetadataQueryWriter): HRESULT; stdcall;
  end;

  IWICBitmapEncoder = interface(IUnknown)
    ['{00000103-A8F2-4877-BA0A-FD2B6645FB94}']
    function Initialize(pIStream: IUnknown; cacheOption: DWORD): HRESULT; stdcall;
    function GetContainerFormat(out pguidContainerFormat: TGUID): HRESULT; stdcall;
    function GetEncoderInfo(out ppIEncoderInfo: IUnknown): HRESULT; stdcall;
    function SetColorContexts(cCount: UINT; ppIColorContext: Pointer): HRESULT; stdcall;
    function SetPalette(pIPalette: IUnknown): HRESULT; stdcall;
    function SetThumbnail(pIThumbnail: IWICBitmapSource): HRESULT; stdcall;
    function SetPreview(pIPreview: IWICBitmapSource): HRESULT; stdcall;
    function CreateNewFrame(out ppIFrameEncode: IWICBitmapFrameEncode;
      out ppIEncoderOptions: IWicPropertyBag2): HRESULT; stdcall;
    function Commit: HRESULT; stdcall;
    function GetMetadataQueryWriter(out ppIMetadataQueryWriter: IUnknown): HRESULT; stdcall;
  end;

  { IWICStream наследява IStream; тук са изброени слотовете на ISequentialStream
    и IStream, за да не зависим от ActiveX. Ползваме само InitializeFromFilename. }
  IWICStream = interface(IUnknown)
    ['{135FF860-22B7-4DDF-B0F6-218F4F299A43}']
    function Read(pv: Pointer; cb: ULONG; pcbRead: PULONG): HRESULT; stdcall;
    function Write(pv: Pointer; cb: ULONG; pcbWritten: PULONG): HRESULT; stdcall;
    function Seek(dlibMove: Int64; dwOrigin: DWORD; plibNewPosition: PQWord): HRESULT; stdcall;
    function SetSize(libNewSize: QWord): HRESULT; stdcall;
    function CopyTo(stm: IUnknown; cb: QWord; pcbRead, pcbWritten: PQWord): HRESULT; stdcall;
    function Commit(grfCommitFlags: DWORD): HRESULT; stdcall;
    function Revert: HRESULT; stdcall;
    function LockRegion(libOffset, cb: QWord; dwLockType: DWORD): HRESULT; stdcall;
    function UnlockRegion(libOffset, cb: QWord; dwLockType: DWORD): HRESULT; stdcall;
    function Stat(pstatstg: Pointer; grfStatFlag: DWORD): HRESULT; stdcall;
    function Clone(out stm: IUnknown): HRESULT; stdcall;
    function InitializeFromIStream(pIStream: IUnknown): HRESULT; stdcall;
    function InitializeFromFilename(wzFileName: PWideChar; dwDesiredAccess: DWORD): HRESULT; stdcall;
    function InitializeFromMemory(pbBuffer: PByte; cbBufferSize: DWORD): HRESULT; stdcall;
    function InitializeFromIStreamRegion(pIStream: IUnknown; ulOffset, ulMaxSize: QWord): HRESULT; stdcall;
  end;

  IWICComponentInfo = interface(IUnknown)
    ['{23BC3F0A-698B-4357-886B-F24D50671334}']
    function GetComponentType(out pType: DWORD): HRESULT; stdcall;
    function GetCLSID(out pclsid: TGUID): HRESULT; stdcall;
    function GetSigningStatus(out pStatus: DWORD): HRESULT; stdcall;
    function GetAuthor(cchAuthor: UINT; wzAuthor: PWideChar; out pcchActual: UINT): HRESULT; stdcall;
    function GetVendorGUID(out pguidVendor: TGUID): HRESULT; stdcall;
    function GetVersion(cchVersion: UINT; wzVersion: PWideChar; out pcchActual: UINT): HRESULT; stdcall;
    function GetSpecVersion(cchSpecVersion: UINT; wzSpecVersion: PWideChar; out pcchActual: UINT): HRESULT; stdcall;
    function GetFriendlyName(cchFriendlyName: UINT; wzFriendlyName: PWideChar; out pcchActual: UINT): HRESULT; stdcall;
  end;

  IWICBitmapCodecInfo = interface(IWICComponentInfo)
    ['{E87A44C4-B76E-4C47-8B09-298EB12A2714}']
    function GetContainerFormat(out pguidContainerFormat: TGUID): HRESULT; stdcall;
    function GetPixelFormats(cFormats: UINT; pguidPixelFormats: PGUID; out pcActual: UINT): HRESULT; stdcall;
    function GetColorManagementVersion(cch: UINT; wz: PWideChar; out pcchActual: UINT): HRESULT; stdcall;
    function GetDeviceManufacturer(cch: UINT; wz: PWideChar; out pcchActual: UINT): HRESULT; stdcall;
    function GetDeviceModels(cch: UINT; wz: PWideChar; out pcchActual: UINT): HRESULT; stdcall;
    function GetMimeTypes(cch: UINT; wz: PWideChar; out pcchActual: UINT): HRESULT; stdcall;
    function GetFileExtensions(cch: UINT; wz: PWideChar; out pcchActual: UINT): HRESULT; stdcall;
    // Слотовете по-долу трябва да ги има, иначе всеки наследник (IWICBitmapDecoderInfo,
    // IWICBitmapEncoderInfo) получава методите си в чужди слотове.
    function DoesSupportAnimation(out pfSupportAnimation: BOOL): HRESULT; stdcall;
    function DoesSupportChromakey(out pfSupportChromakey: BOOL): HRESULT; stdcall;
    function DoesSupportLossless(out pfSupportLossless: BOOL): HRESULT; stdcall;
    function DoesSupportMultiframe(out pfSupportMultiframe: BOOL): HRESULT; stdcall;
    function MatchesMimeType(wzMimeType: PWideChar; out pfMatches: BOOL): HRESULT; stdcall;
  end;

  IWICBitmapDecoderInfo = interface(IWICBitmapCodecInfo)
    ['{D8CD007F-D08F-4191-9BFC-236EA7F0E4B5}']
    function GetPatterns(cbSizePatterns: UINT; pPatterns: Pointer; pcPatterns, pcbPatternsActual: PUINT): HRESULT; stdcall;
    function MatchesPattern(pIStream: IUnknown; out pfMatches: BOOL): HRESULT; stdcall;
    function CreateInstance(out ppIBitmapDecoder: IWICBitmapDecoder): HRESULT; stdcall;
  end;

  IWICColorContext = interface(IUnknown)
    ['{3C613A02-34B2-44EA-9A7C-45AEA9C6FD6D}']
    function InitializeFromFilename(wzFilename: PWideChar): HRESULT; stdcall;
    function InitializeFromMemory(pbBuffer: PByte; cbBufferSize: UINT): HRESULT; stdcall;
    function InitializeFromExifColorSpace(value: UINT): HRESULT; stdcall;
    function GetType(out pType: DWORD): HRESULT; stdcall;
    function GetProfileBytes(cbBuffer: UINT; pbBuffer: PByte; out pcbActual: UINT): HRESULT; stdcall;
    function GetExifColorSpace(out pValue: UINT): HRESULT; stdcall;
  end;

  IWICColorTransform = interface(IWICBitmapSource)
    ['{B66F034F-D0E2-40AB-B436-6DE39E321A94}']
    function Initialize(pIBitmapSource: IWICBitmapSource; pIContextSource, pIContextDest: IWICColorContext;
      const pixelFmtDest: TGUID): HRESULT; stdcall;
  end;

  IWICImagingFactory = interface(IUnknown)
    ['{EC5EC8A9-C395-4314-9C77-54D7A935FF70}']
    function CreateDecoderFromFilename(wzFilename: PWideChar; pguidVendor: PGUID;
      dwDesiredAccess: DWORD; metadataOptions: DWORD;
      out ppIDecoder: IWICBitmapDecoder): HRESULT; stdcall;
    function CreateDecoderFromStream(pIStream: IUnknown; pguidVendor: PGUID;
      metadataOptions: DWORD; out ppIDecoder: IWICBitmapDecoder): HRESULT; stdcall;
    function CreateDecoderFromFileHandle(hFile: PtrUInt; pguidVendor: PGUID;
      metadataOptions: DWORD; out ppIDecoder: IWICBitmapDecoder): HRESULT; stdcall;
    function CreateComponentInfo(const clsidComponent: TGUID;
      out ppIInfo: IWICComponentInfo): HRESULT; stdcall;
    function CreateDecoder(const guidContainerFormat: TGUID; pguidVendor: PGUID;
      out ppIDecoder: IWICBitmapDecoder): HRESULT; stdcall;
    function CreateEncoder(const guidContainerFormat: TGUID; pguidVendor: PGUID;
      out ppIEncoder: IWICBitmapEncoder): HRESULT; stdcall;
    function CreatePalette(out ppIPalette: IUnknown): HRESULT; stdcall;
    function CreateFormatConverter(out ppIFormatConverter: IWICFormatConverter): HRESULT; stdcall;
    function CreateBitmapScaler(out ppIBitmapScaler: IWICBitmapScaler): HRESULT; stdcall;
    function CreateBitmapClipper(out ppIBitmapClipper: IUnknown): HRESULT; stdcall;
    function CreateBitmapFlipRotator(out ppIBitmapFlipRotator: IUnknown): HRESULT; stdcall;
    function CreateStream(out ppIWICStream: IWICStream): HRESULT; stdcall;
    function CreateColorContext(out ppIWICColorContext: IWICColorContext): HRESULT; stdcall;
    function CreateColorTransformer(out ppIWICColorTransform: IWICColorTransform): HRESULT; stdcall;
    function CreateBitmap(uiWidth, uiHeight: UINT; const pixelFormat: TGUID;
      option: DWORD; out ppIBitmap: IWICBitmap): HRESULT; stdcall;
    function CreateBitmapFromSource(pIBitmapSource: IWICBitmapSource;
      option: DWORD; out ppIBitmap: IWICBitmap): HRESULT; stdcall;
    function CreateBitmapFromSourceRect(pIBitmapSource: IWICBitmapSource;
      x, y, width, height: UINT; out ppIBitmap: IWICBitmap): HRESULT; stdcall;
    function CreateBitmapFromMemory(uiWidth, uiHeight: UINT; const pixelFormat: TGUID;
      cbStride, cbBufferSize: UINT; pbBuffer: PByte;
      out ppIBitmap: IWICBitmap): HRESULT; stdcall;
    function CreateBitmapFromHBITMAP(hBmp: HBITMAP; hPal: HPALETTE; options: DWORD;
      out ppIBitmap: IWICBitmap): HRESULT; stdcall;
    function CreateBitmapFromHICON(hIco: HICON; out ppIBitmap: IWICBitmap): HRESULT; stdcall;
    function CreateComponentEnumerator(componentTypes, options: DWORD;
      out ppIEnumUnknown: IWicEnumUnknown): HRESULT; stdcall;
  end;

const
  CLSID_WICImagingFactory:  TGUID = '{CACAF262-9370-4615-A13B-9F5539DA4C0A}';
  CLSID_WICImagingFactory2: TGUID = '{317D06E8-5F24-433D-BDF7-79CE68D8ABC2}';

  VT_EMPTY = 0; VT_I2 = 2; VT_I4 = 3; VT_R4 = 4; VT_R8 = 5; VT_BSTR = 8;
  VT_BOOL = 11; VT_UNKNOWN = 13; VT_I1 = 16; VT_UI1 = 17; VT_UI2 = 18;
  VT_UI4 = 19; VT_I8 = 20; VT_UI8 = 21; VT_LPSTR = 30; VT_LPWSTR = 31;
  VT_FILETIME = 64; VT_BLOB = 65; VT_CLSID = 72; VT_VECTOR = $1000;

{ Нов WIC factory. Викащият носи отговорност за COM инициализацията. }
function WicCreateFactory: IWICImagingFactory;

implementation

uses
  Math;

const
  COINIT_APARTMENTTHREADED = $2;
  CLSCTX_INPROC_SERVER = 1;
  RPC_E_CHANGED_MODE = HRESULT($80010106);

  WICDecodeMetadataCacheOnDemand = 0;
  WICBitmapEncoderNoCache = 2;
  WICBitmapCacheOnLoad = 2;
  WICBitmapDitherTypeNone = 0;
  WICBitmapPaletteTypeCustom = 0;
  WICDecoder = 1;
  WICEncoder = 2;
  WICComponentEnumerateDefault = 0;

function wicCoInitializeEx(pvReserved: Pointer; dwCoInit: DWORD): HRESULT; stdcall;
  external 'ole32.dll' name 'CoInitializeEx';
procedure wicCoUninitialize; stdcall; external 'ole32.dll' name 'CoUninitialize';
function wicCoCreateInstance(const clsid: TGUID; unkOuter: Pointer; dwClsContext: DWORD;
  const iid: TGUID; out pv): HRESULT; stdcall; external 'ole32.dll' name 'CoCreateInstance';
procedure wicCoTaskMemFree(pv: Pointer); stdcall; external 'ole32.dll' name 'CoTaskMemFree';
function wicPropVariantClear(pvar: PWicPropVariant): HRESULT; stdcall;
  external 'ole32.dll' name 'PropVariantClear';

{ ---------------------------------------------------------------------------- }

constructor EWicError.CreateHR(const Step: string; AHR: HRESULT);
begin
  inherited CreateFmt('WIC: %s неуспешно (HRESULT $%.8x)', [Step, LongWord(AHR)]);
  HR := AHR;
end;

procedure Check(HR: HRESULT; const Step: string); inline;
begin
  if Failed(HR) then
    raise EWicError.CreateHR(Step, HR);
end;

{ COM за времето на едно публично извикване. Ако нишката вече е в друг
  apartment (RPC_E_CHANGED_MODE), работим в него и не деинициализираме. }
function ComEnter: Boolean;
var
  hr: HRESULT;
begin
  hr := wicCoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  Result := (hr = S_OK) or (hr = S_FALSE);
  if Failed(hr) and (hr <> RPC_E_CHANGED_MODE) then
    raise EWicError.CreateHR('CoInitializeEx', hr);
end;

procedure ComLeave(Entered: Boolean);
begin
  if Entered then
    wicCoUninitialize;
end;

function WicCreateFactory: IWICImagingFactory;
var
  hr: HRESULT;
begin
  Result := nil;
  hr := wicCoCreateInstance(CLSID_WICImagingFactory2, nil, CLSCTX_INPROC_SERVER,
    IWICImagingFactory, Result);
  if Failed(hr) then
    hr := wicCoCreateInstance(CLSID_WICImagingFactory, nil, CLSCTX_INPROC_SERVER,
      IWICImagingFactory, Result);
  Check(hr, 'CoCreateInstance(WICImagingFactory)');
end;

{ Превръщането зачита кодовата страница на низа: в Lazarus (UTF-8) и в
  конзолни програми с ANSI низове дава един и същ правилен резултат. }
function WideName(const FileName: string): UnicodeString;
begin
  Result := UnicodeString(FileName);
end;

function NormExt(const Ext: string): string;
begin
  Result := LowerCase(Trim(Ext));
  if (Result <> '') and (Result[1] <> '.') then
    Result := '.' + Result;
end;

{ ---------------------------------------------------------------------------- }
{ Метаданни: помощни                                                           }
{ ---------------------------------------------------------------------------- }

function RationalToFloat(V: QWord): Double;
var
  Num, Den: LongWord;
begin
  Num := LongWord(V and $FFFFFFFF);
  Den := LongWord(V shr 32);
  if Den = 0 then Result := 0 else Result := Num / Den;
end;

function SRationalToFloat(V: Int64): Double;
var
  Num, Den: LongInt;
begin
  Num := LongInt(V and $FFFFFFFF);
  Den := LongInt(QWord(V) shr 32);
  if Den = 0 then Result := 0 else Result := Num / Den;
end;

function PropToFloat(const PV: TWicPropVariant; out Value: Double): Boolean;
begin
  Result := True;
  case PV.vt of
    VT_UI1: Value := PV.bVal;
    VT_I2:  Value := PV.iVal;
    VT_UI2: Value := PV.uiVal;
    VT_I4:  Value := PV.lVal;
    VT_UI4: Value := PV.ulVal;
    VT_R4:  Value := PV.fltVal;
    VT_R8:  Value := PV.dblVal;
    VT_UI8: Value := RationalToFloat(PV.uhVal);   // EXIF RATIONAL
    VT_I8:  Value := SRationalToFloat(PV.hVal);   // EXIF SRATIONAL
  else
    Result := False;
  end;
end;

function PropToStr(const PV: TWicPropVariant): string;
var
  D: Double;
begin
  case PV.vt of
    VT_LPSTR:  Result := Trim(string(PV.pszVal));
    VT_LPWSTR: Result := Trim(UTF8Encode(UnicodeString(PV.pwszVal)));
  else
    if PropToFloat(PV, D) then Result := FloatToStr(D) else Result := '';
  end;
end;

{ Чете стойност по път. False, ако я няма. Стойността трябва да се освободи. }
function QueryValue(const Reader: IWICMetadataQueryReader; const Path: string;
  out PV: TWicPropVariant): Boolean;
var
  W: UnicodeString;
begin
  FillChar(PV, SizeOf(PV), 0);
  Result := False;
  if Reader = nil then Exit;
  W := UnicodeString(Path);
  Result := Succeeded(Reader.GetMetadataByName(PWideChar(W), @PV));
  if not Result then
    FillChar(PV, SizeOf(PV), 0);
end;

function QueryStr(const Reader: IWICMetadataQueryReader; const Path: string): string;
var
  PV: TWicPropVariant;
begin
  Result := '';
  if QueryValue(Reader, Path, PV) then
  try
    Result := PropToStr(PV);
  finally
    wicPropVariantClear(@PV);
  end;
end;

function QueryFloat(const Reader: IWICMetadataQueryReader; const Path: string;
  out Value: Double): Boolean;
var
  PV: TWicPropVariant;
begin
  Value := 0;
  Result := False;
  if QueryValue(Reader, Path, PV) then
  try
    Result := PropToFloat(PV, Value);
  finally
    wicPropVariantClear(@PV);
  end;
end;

function PathExists(const Reader: IWICMetadataQueryReader; const Path: string): Boolean;
var
  W: UnicodeString;
begin
  W := UnicodeString(Path);
  Result := (Reader <> nil) and Succeeded(Reader.GetMetadataByName(PWideChar(W), nil));
end;

{ Корен на EXIF IFD: '/app1/ifd' за JPEG, '/ifd' за TIFF/HEIF/RAW. }
function FindIfdRoot(const Reader: IWICMetadataQueryReader): string;
begin
  if PathExists(Reader, '/app1/ifd') then Result := '/app1/ifd'
  else if PathExists(Reader, '/ifd') then Result := '/ifd'
  else Result := '';
end;

function ReadOrientationEx(const Frame: IWICBitmapFrameDecode; out Found: Boolean): Integer;
var
  Reader: IWICMetadataQueryReader;
  D: Double;
  Root: string;
begin
  Result := 1;
  Found := False;
  if Failed(Frame.GetMetadataQueryReader(Reader)) or (Reader = nil) then Exit;
  // Photo policy работи за всички формати на истински Windows
  if QueryFloat(Reader, 'System.Photo.Orientation', D) and (D >= 1) and (D <= 8) then
  begin
    Found := True;
    Exit(Round(D));
  end;
  Root := FindIfdRoot(Reader);
  if (Root <> '') and QueryFloat(Reader, Root + '/{ushort=274}', D)
    and (D >= 1) and (D <= 8) then
  begin
    Found := True;
    Result := Round(D);
  end;
end;

function ReadOrientation(const Frame: IWICBitmapFrameDecode): Integer;
var
  Found: Boolean;
begin
  Result := ReadOrientationEx(Frame, Found);
end;

{ ---------------------------------------------------------------------------- }
{ Ориентация                                                                   }
{ ---------------------------------------------------------------------------- }

procedure WicApplyOrientation(var Img: TWicImage; Orientation: Integer);
var
  W, H, NW, NH, X, Y, SX, SY: Integer;
  Src: array of Byte;
  S, D: PLongWord;
begin
  if (Orientation < 2) or (Orientation > 8) or (Img.Width = 0) then Exit;
  W := Img.Width;
  H := Img.Height;
  Src := Copy(Img.Pixels);
  if Orientation >= 5 then
  begin
    NW := H; NH := W;
  end
  else
  begin
    NW := W; NH := H;
  end;
  S := PLongWord(@Src[0]);
  D := PLongWord(@Img.Pixels[0]);
  for Y := 0 to NH - 1 do
    for X := 0 to NW - 1 do
    begin
      case Orientation of
        2: begin SX := W - 1 - X; SY := Y;         end; // огледално хоризонтално
        3: begin SX := W - 1 - X; SY := H - 1 - Y; end; // 180°
        4: begin SX := X;         SY := H - 1 - Y; end; // огледално вертикално
        5: begin SX := Y;         SY := X;         end; // транспониране
        6: begin SX := Y;         SY := H - 1 - X; end; // 90° по часовника
        7: begin SX := W - 1 - Y; SY := H - 1 - X; end; // транcверсия
        8: begin SX := W - 1 - Y; SY := X;         end; // 90° обратно
      else
        SX := X; SY := Y;
      end;
      D[Y * NW + X] := S[SY * W + SX];
    end;
  Img.Width := NW;
  Img.Height := NH;
end;

{ ---------------------------------------------------------------------------- }
{ Четене                                                                       }
{ ---------------------------------------------------------------------------- }

function ScaleMode(Mode: TWicInterpolation): DWORD;
begin
  case Mode of
    wiNearest: Result := 0;
    wiLinear:  Result := 1;
    wiCubic:   Result := 2;
    wiFant:    Result := 3;
  else
    Result := 4;   // HighQualityCubic, Windows 10+
  end;
end;

{ Смалява Src до NW x NH. HighQualityCubic липсва преди Windows 10, затова
  при отказ слизаме към Fant, който е добър за смаляване. }
function MakeScaler(const Factory: IWICImagingFactory; const Src: IWICBitmapSource;
  NW, NH: Integer; Mode: TWicInterpolation): IWICBitmapSource;
var
  Scaler: IWICBitmapScaler;
  hr: HRESULT;
begin
  Check(Factory.CreateBitmapScaler(Scaler), 'CreateBitmapScaler');
  hr := Scaler.Initialize(Src, NW, NH, ScaleMode(Mode));
  if Failed(hr) and (Mode = wiHighQualityCubic) then
    hr := Scaler.Initialize(Src, NW, NH, ScaleMode(wiFant));
  Check(hr, 'BitmapScaler.Initialize');
  Result := Scaler;
end;

procedure FitInto(W, H, MaxSide: Integer; out NW, NH: Integer);
begin
  if W >= H then
  begin
    NW := MaxSide;
    NH := Round(H * MaxSide / W);
  end
  else
  begin
    NH := MaxSide;
    NW := Round(W * MaxSide / H);
  end;
  if NW < 1 then NW := 1;
  if NH < 1 then NH := 1;
end;

{ Копира произволен WIC source в TWicImage като BGRA. }
function SourceToImage(const Factory: IWICImagingFactory;
  const Src: IWICBitmapSource): TWicImage;
var
  Conv: IWICFormatConverter;
  W, H: UINT;
begin
  Check(Src.GetSize(W, H), 'GetSize');
  Check(Factory.CreateFormatConverter(Conv), 'CreateFormatConverter');
  Check(Conv.Initialize(Src, GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone,
    nil, 0, WICBitmapPaletteTypeCustom), 'FormatConverter.Initialize');
  Result.Width := W;
  Result.Height := H;
  SetLength(Result.Pixels, W * H * 4);
  if Length(Result.Pixels) > 0 then
    Check(Conv.CopyPixels(nil, W * 4, Length(Result.Pixels), @Result.Pixels[0]),
      'CopyPixels');
end;

function OpenDecoder(const Factory: IWICImagingFactory;
  const W: UnicodeString): IWICBitmapDecoder;
begin
  if not FileExists(W) then
    raise EWicError.CreateFmt('WIC: файлът не съществува: %s', [UTF8Encode(W)]);
  Check(Factory.CreateDecoderFromFilename(PWideChar(W), nil, GENERIC_READ,
    WICDecodeMetadataCacheOnDemand, Result), 'CreateDecoderFromFilename');
end;

var
  GRawExts: string = '';          // ',.cr3,.dng,...,' - разширенията на Raw Image Decoder
  GRawExtsLoaded: Boolean = False;

function RawDecoderExts: string;
var
  L: TWicCodecInfoArray;
  i: Integer;
  s: string;
begin
  if GRawExtsLoaded then Exit(GRawExts);
  s := ',';
  try
    L := WicListCodecs;
    for i := 0 to High(L) do
      if (not L[i].IsEncoder) and IsEqualGUID(L[i].Clsid, CLSID_WICRawImageDecoder) then
        s := s + StringReplace(StringReplace(LowerCase(L[i].Extensions), ';', ',', [rfReplaceAll]),
          ' ', '', [rfReplaceAll]) + ',';
  except
    s := ',';
  end;
  // публикуваме чак накрая: при едновременно първо извикване от две нишки и двете смятат еднакво
  GRawExts := s;
  GRawExtsLoaded := True;
  Result := s;
end;

{ Декодер за ПИКСЕЛИТЕ. Ако Raw Image Decoder поддържа разширението и успее да отвори файла,
  се ползва той; иначе изборът на Windows. IsPreferred казва кой е отворен. Метаданните
  (EXIF, GPS) винаги се четат през OpenDecoder - там поведението е доказано. }
function OpenPixelDecoder(const Factory: IWICImagingFactory; const W: UnicodeString;
  out IsPreferred: Boolean): IWICBitmapDecoder;
var
  ext: string;
  D: IWICBitmapDecoder;
  S: IWICStream;
begin
  IsPreferred := False;
  if not FileExists(W) then
    raise EWicError.CreateFmt('WIC: файлът не съществува: %s', [UTF8Encode(W)]);
  ext := LowerCase(UTF8Encode(ExtractFileExt(W)));
  if (ext <> '') and (Pos(',' + ext + ',', RawDecoderExts) > 0) then
  begin
    D := nil;
    S := nil;
    if Succeeded(wicCoCreateInstance(CLSID_WICRawImageDecoder, nil, CLSCTX_INPROC_SERVER,
         IWICBitmapDecoder, D)) and (D <> nil) and
       Succeeded(Factory.CreateStream(S)) and
       Succeeded(S.InitializeFromFilename(PWideChar(W), GENERIC_READ)) and
       Succeeded(D.Initialize(S, WICDecodeMetadataCacheOnDemand)) then
    begin
      IsPreferred := True;
      Exit(D);
    end;
  end;
  Result := OpenDecoder(Factory, W);
end;

{ Ориентация за пикселите от Frame. Ако предпочетеният декодер не я знае (няма метаданни),
  я взимаме от декодера по подразбиране - пикселите на един RAW са в една и съща сурова
  ориентация, независимо кой декодер ги дава. }
function PixelOrientation(const Factory: IWICImagingFactory; const W: UnicodeString;
  const Frame: IWICBitmapFrameDecode; IsPreferred: Boolean): Integer;
var
  Found: Boolean;
  D: IWICBitmapDecoder;
  F: IWICBitmapFrameDecode;
begin
  Result := ReadOrientationEx(Frame, Found);
  if Found or not IsPreferred then Exit;
  try
    D := OpenDecoder(Factory, W);
    if Succeeded(D.GetFrame(0, F)) then
      Result := ReadOrientation(F);
  except
    Result := 1;
  end;
end;

function DoLoad(const FileName: UnicodeString; FrameIndex, MaxSide: Integer;
  AutoRotate: Boolean): TWicImage;
var
  Factory: IWICImagingFactory;
  Decoder: IWICBitmapDecoder;
  Frame: IWICBitmapFrameDecode;
  Src: IWICBitmapSource;
  W, H: UINT;
  NW, NH, Orientation: Integer;
  Pref: Boolean;
begin
  Factory := WicCreateFactory;
  Decoder := OpenPixelDecoder(Factory, FileName, Pref);
  Check(Decoder.GetFrame(FrameIndex, Frame), 'GetFrame');
  Orientation := 1;
  if AutoRotate then
    Orientation := PixelOrientation(Factory, FileName, Frame, Pref);
  Check(Frame.GetSize(W, H), 'GetSize');
  Src := Frame;
  // Ориентацията само разменя страните, затова MaxSide важи и преди нея
  if (MaxSide > 0) and ((Integer(W) > MaxSide) or (Integer(H) > MaxSide)) then
  begin
    FitInto(W, H, MaxSide, NW, NH);
    Src := MakeScaler(Factory, Src, NW, NH, wiHighQualityCubic);
  end;
  Result := SourceToImage(Factory, Src);
  WicApplyOrientation(Result, Orientation);
end;

function WicLoad(const FileName: string; MaxSide: Integer; AutoRotate: Boolean): TWicImage;
begin
  Result := WicLoadFrame(FileName, 0, MaxSide, AutoRotate);
end;

function WicLoadW(const FileName: UnicodeString; MaxSide: Integer;
  AutoRotate: Boolean): TWicImage;
var
  C: Boolean;
begin
  C := ComEnter;
  try
    Result := DoLoad(FileName, 0, MaxSide, AutoRotate);
  finally
    ComLeave(C);
  end;
end;

function WicLoadFrame(const FileName: string; FrameIndex: Integer;
  MaxSide: Integer; AutoRotate: Boolean): TWicImage;
var
  C: Boolean;
begin
  C := ComEnter;
  try
    Result := DoLoad(WideName(FileName), FrameIndex, MaxSide, AutoRotate);
  finally
    ComLeave(C);
  end;
end;

function DoGetSize(const FileName: string; out W, H: Integer; AutoRotate: Boolean): Boolean;
var
  Factory: IWICImagingFactory;
  Decoder: IWICBitmapDecoder;
  Frame: IWICBitmapFrameDecode;
  UW, UH: UINT;
  T: Integer;
  Pref: Boolean;
begin
  Factory := WicCreateFactory;
  Decoder := OpenPixelDecoder(Factory, WideName(FileName), Pref);
  Check(Decoder.GetFrame(0, Frame), 'GetFrame');
  Check(Frame.GetSize(UW, UH), 'GetSize');
  W := UW;
  H := UH;
  if AutoRotate and (PixelOrientation(Factory, WideName(FileName), Frame, Pref) >= 5) then
  begin
    T := W; W := H; H := T;
  end;
  Result := True;
end;

function WicGetImageSize(const FileName: string; out W, H: Integer;
  AutoRotate: Boolean): Boolean;
var
  C: Boolean;
begin
  W := 0;
  H := 0;
  C := ComEnter;
  try
    try
      Result := DoGetSize(FileName, W, H, AutoRotate);
    except
      on EWicError do Result := False;
    end;
  finally
    ComLeave(C);
  end;
end;

function DoFrameCount(const FileName: string): Integer;
var
  Factory: IWICImagingFactory;
  Decoder: IWICBitmapDecoder;
  N: UINT;
begin
  Factory := WicCreateFactory;
  Decoder := OpenDecoder(Factory, WideName(FileName));
  Check(Decoder.GetFrameCount(N), 'GetFrameCount');
  Result := N;
end;

function WicGetFrameCount(const FileName: string): Integer;
var
  C: Boolean;
begin
  C := ComEnter;
  try
    Result := DoFrameCount(FileName);
  finally
    ComLeave(C);
  end;
end;

function DoThumb(const FileName: string; out Img: TWicImage): Boolean;
var
  Factory: IWICImagingFactory;
  Decoder: IWICBitmapDecoder;
  Frame: IWICBitmapFrameDecode;
  Thumb: IWICBitmapSource;
begin
  Result := False;
  Factory := WicCreateFactory;
  Decoder := OpenDecoder(Factory, WideName(FileName));
  Check(Decoder.GetFrame(0, Frame), 'GetFrame');
  if Failed(Frame.GetThumbnail(Thumb)) or (Thumb = nil) then
    if Failed(Decoder.GetThumbnail(Thumb)) or (Thumb = nil) then
      Exit;
  Img := SourceToImage(Factory, Thumb);
  WicApplyOrientation(Img, ReadOrientation(Frame));
  Result := True;
end;

function SrcSize(const S: IWICBitmapSource; out W, H: Integer): Boolean;
var
  UW, UH: UINT;
begin
  Result := (S <> nil) and Succeeded(S.GetSize(UW, UH)) and (UW > 0) and (UH > 0);
  W := UW;
  H := UH;
end;

{ ---------------------------------------------------------------------------- }
{ Цвят                                                                         }
{ ---------------------------------------------------------------------------- }

const
  WICColorContextProfile = 1;
  WICColorContextExifColorSpace = 2;

{ Цветовият контекст на кадъра, ако е различен от sRGB; nil = sRGB или няма профил (тогава по
  конвенция пикселите са sRGB). Разпознаването на sRGB е по описанието в ICC профила - всички
  разпространени sRGB профили (Microsoft, HP, littlecms, Apple) носят „sRGB“ в него. Ако не го
  разпознаем, преобразуването sRGB -> sRGB е безвредно, просто ненужно. }
function NonSrgbContext(const Factory: IWICImagingFactory; const Frame: IWICBitmapFrameDecode): IWICColorContext;
var
  N, i, Got, Sz, ExifCS, Kind: UINT;
  Ctx: array of IWICColorContext;
  Bytes: array of Byte;
  s: string;
  k: Integer;
begin
  Result := nil;
  N := 0;
  if Failed(Frame.GetColorContexts(0, nil, N)) or (N = 0) then Exit;
  SetLength(Ctx, N);
  for i := 0 to N - 1 do
    if Failed(Factory.CreateColorContext(Ctx[i])) then Exit;
  Got := 0;
  if Failed(Frame.GetColorContexts(N, @Ctx[0], Got)) or (Got = 0) then Exit;
  for i := 0 to Got - 1 do
  begin
    Kind := 0;
    Ctx[i].GetType(Kind);
    if Kind = WICColorContextExifColorSpace then
    begin
      // 1 = sRGB, 2 = Adobe RGB (EXIF InteroperabilityIndex R03), 65535 = некалибрирано
      if Succeeded(Ctx[i].GetExifColorSpace(ExifCS)) and (ExifCS = 2) then Exit(Ctx[i]);
      Continue;
    end;
    if Kind <> WICColorContextProfile then Continue;
    Sz := 0;
    Ctx[i].GetProfileBytes(0, nil, Sz);
    if Sz = 0 then Continue;
    SetLength(Bytes, Sz);
    if Failed(Ctx[i].GetProfileBytes(Sz, @Bytes[0], Sz)) then Continue;
    // Описанието е ASCII ('desc') или UTF-16BE ('mluc'): сваляме нулите и търсим „sRGB“
    SetLength(s, 0);
    for k := 0 to Min(Integer(Sz), 4096) - 1 do
      if Bytes[k] <> 0 then s := s + Chr(Bytes[k]);
    if Pos('sRGB', s) > 0 then Exit(nil);
    Exit(Ctx[i]);
  end;
end;

{ Src (пикселите на Frame) -> 32bppBGRA в sRGB. Converted = имало е преобразуване. }
function ToSrgb(const Factory: IWICImagingFactory; const Frame: IWICBitmapFrameDecode;
  const Src: IWICBitmapSource; out Converted: Boolean): IWICBitmapSource;
var
  SrcCtx, Dst: IWICColorContext;
  Conv: IWICFormatConverter;
  T: IWICColorTransform;
begin
  Result := Src;
  Converted := False;
  SrcCtx := NonSrgbContext(Factory, Frame);
  if SrcCtx = nil then Exit;
  if Failed(Factory.CreateColorContext(Dst)) or Failed(Dst.InitializeFromExifColorSpace(1)) then Exit;
  if Failed(Factory.CreateFormatConverter(Conv)) or
     Failed(Conv.Initialize(Src, GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone, nil, 0,
       WICBitmapPaletteTypeCustom)) then Exit;
  if Failed(Factory.CreateColorTransformer(T)) or
     Failed(T.Initialize(Conv, SrcCtx, Dst, GUID_WICPixelFormat32bppBGRA)) then Exit;
  Result := T;
  Converted := True;
end;

{ Вградена миниатюра, която е почти еднаква по цялата площ, е повредена: телефоните при HDR
  често записват черна миниатюра, преди обработката да е готова (видяно на motorola edge 70).
  Проверяваме я по извадка от пикселите - тя е малка, затова е евтино. Снимка на наистина
  еднаква сцена (бяла стена) също ще се отхвърли, но тогава просто се декодира самата снимка. }
function FlatSource(const Factory: IWICImagingFactory; const S: IWICBitmapSource): Boolean;
var
  Img: TWicImage;
  i, n, step, lum, lo, hi: Integer;
  p: PByte;
begin
  Result := False;
  try
    Img := SourceToImage(Factory, S);
  except
    Exit(True);   // нечетима миниатюра = неизползваема
  end;
  n := Img.Width * Img.Height;
  if n = 0 then Exit(True);
  step := Max(1, n div 4096);
  lo := 255;
  hi := 0;
  i := 0;
  while i < n do
  begin
    p := @Img.Pixels[i * 4];
    lum := (p[2] * 77 + p[1] * 150 + p[0] * 29) shr 8;
    if lum < lo then lo := lum;
    if lum > hi then hi := lum;
    Inc(i, step);
  end;
  Result := hi - lo < 12;
end;

{ MinPreview: превюто се ползва само ако дългата му страна е поне толкова; -1 = за най-добро
  качество (поне 90% от нужното: MaxSide или пълния размер на кадъра). }
{ Srgb <> nil: пикселите на кадъра се преобразуват към sRGB, ако профилът му е друг (Adobe RGB,
  Display P3...); Srgb^ казва дали е имало преобразуване. Вградените превюта и миниатюри не се
  пипат - фотоапаратите и телефоните ги правят в sRGB. }
function DoPreview(const FileName: UnicodeString; MaxSide: Integer; AutoRotate,
  UseThumb: Boolean; MinThumb: Integer; MinPreview: Integer = 0; Srgb: PBoolean = nil): TWicImage;
var
  Factory: IWICImagingFactory;
  Decoder: IWICBitmapDecoder;
  Frame: IWICBitmapFrameDecode;
  Src, T: IWICBitmapSource;
  FW, FH, SW, SH, NW, NH, Orient, Need: Integer;
  IsDerived, Pref: Boolean;
begin
  Factory := WicCreateFactory;
  Decoder := OpenPixelDecoder(Factory, FileName, Pref);
  Check(Decoder.GetFrame(0, Frame), 'GetFrame');
  Orient := 1;
  if AutoRotate then
    Orient := PixelOrientation(Factory, FileName, Frame, Pref);
  SrcSize(Frame, FW, FH);
  if MinPreview < 0 then
  begin
    Need := Max(FW, FH);
    if (MaxSide > 0) and (MaxSide < Need) then Need := MaxSide;
    MinPreview := Round(Need * 0.9);
  end;
  Src := nil;
  IsDerived := False;
  if UseThumb then
  begin
    T := nil;
    if Failed(Frame.GetThumbnail(T)) or (T = nil) then
      if Failed(Decoder.GetThumbnail(T)) then T := nil;
    if SrcSize(T, SW, SH) and (Max(SW, SH) >= MinThumb) and not FlatSource(Factory, T) then
    begin
      Src := T;
      IsDerived := True;
    end;
  end;
  if Src = nil then
  begin
    T := nil;
    if Succeeded(Decoder.GetPreview(T)) and SrcSize(T, SW, SH) and (Max(SW, SH) >= MinPreview) then
    begin
      Src := T;
      IsDerived := True;
    end;
  end;
  if Srgb <> nil then Srgb^ := False;
  if Src = nil then
  begin
    Src := Frame;
    if Srgb <> nil then
      Src := ToSrgb(Factory, Frame, Src, Srgb^);
  end;
  // Производно изображение (миниатюра/превю), което е с разменени пропорции спрямо
  // кадъра, значи вече е завъртяно от декодера: не го въртим втори път.
  if IsDerived and (Orient >= 5) and SrcSize(Src, SW, SH) and (FW > 0) and
     ((SW > SH) <> (FW > FH)) then
    Orient := 1;
  if (MaxSide > 0) and SrcSize(Src, SW, SH) and ((SW > MaxSide) or (SH > MaxSide)) then
  begin
    FitInto(SW, SH, MaxSide, NW, NH);
    Src := MakeScaler(Factory, Src, NW, NH, wiHighQualityCubic);
  end;
  Result := SourceToImage(Factory, Src);
  WicApplyOrientation(Result, Orient);
end;

function WicLoadPreviewW(const FileName: UnicodeString; MaxSide: Integer;
  AutoRotate: Boolean): TWicImage;
var
  C: Boolean;
begin
  C := ComEnter;
  try
    Result := DoPreview(FileName, MaxSide, AutoRotate, False, 0);
  finally
    ComLeave(C);
  end;
end;

function WicLoadBestW(const FileName: UnicodeString; MaxSide: Integer;
  ToSrgb: Boolean; WasConverted: PBoolean): TWicImage;
var
  C, Conv: Boolean;
begin
  C := ComEnter;
  try
    if ToSrgb then
    begin
      Result := DoPreview(FileName, MaxSide, True, False, 0, -1, @Conv);
      if WasConverted <> nil then WasConverted^ := Conv;
    end
    else
    begin
      Result := DoPreview(FileName, MaxSide, True, False, 0, -1, nil);
      if WasConverted <> nil then WasConverted^ := False;
    end;
  finally
    ComLeave(C);
  end;
end;

function WicColorInfoW(const FileName: UnicodeString): string;
var
  C: Boolean;
  Factory: IWICImagingFactory;
  D: IWICBitmapDecoder;
  F: IWICBitmapFrameDecode;
  Ctx: IWICColorContext;
  Kind, Sz: UINT;
begin
  C := ComEnter;
  try
    Factory := WicCreateFactory;
    D := OpenDecoder(Factory, FileName);
    Check(D.GetFrame(0, F), 'GetFrame');
    Ctx := NonSrgbContext(Factory, F);
    if Ctx = nil then Exit('sRGB / без профил');
    Kind := 0;
    Ctx.GetType(Kind);
    if Kind = WICColorContextExifColorSpace then Exit('EXIF Adobe RGB');
    Sz := 0;
    Ctx.GetProfileBytes(0, nil, Sz);
    Result := Format('ICC профил (%d байта)', [Sz]);
  finally
    ComLeave(C);
  end;
end;

function WicLoadThumbW(const FileName: UnicodeString; MaxSide: Integer;
  MinThumbSide: Integer): TWicImage;
var
  C: Boolean;
begin
  C := ComEnter;
  try
    Result := DoPreview(FileName, MaxSide, True, True, MinThumbSide);
  finally
    ComLeave(C);
  end;
end;

function FormatProp(const PV: TWicPropVariant): string; forward;

function DoReadMeta(const FileName: UnicodeString; const Path: string): string;
var
  Factory: IWICImagingFactory;
  Decoder: IWICBitmapDecoder;
  Frame: IWICBitmapFrameDecode;
  R: IWICMetadataQueryReader;
  PV: TWicPropVariant;
begin
  Result := '';
  Factory := WicCreateFactory;
  Decoder := OpenDecoder(Factory, FileName);
  Check(Decoder.GetFrame(0, Frame), 'GetFrame');
  if Failed(Frame.GetMetadataQueryReader(R)) or (R = nil) then Exit;
  if QueryValue(R, Path, PV) then
  try
    if (PV.vt = VT_LPSTR) or (PV.vt = VT_LPWSTR) then
      Result := PropToStr(PV)
    else
      Result := FormatProp(PV);
  finally
    wicPropVariantClear(@PV);
  end;
end;

function WicReadMetadataW(const FileName: UnicodeString; const Path: string): string;
var
  C: Boolean;
begin
  Result := '';
  C := ComEnter;
  try
    try
      Result := DoReadMeta(FileName, Path);
    except
      on EWicError do Result := '';
    end;
  finally
    ComLeave(C);
  end;
end;

function WicLoadEmbeddedThumbnail(const FileName: string; out Img: TWicImage): Boolean;
var
  C: Boolean;
begin
  Img := Default(TWicImage);
  C := ComEnter;
  try
    try
      Result := DoThumb(FileName, Img);
    except
      on EWicError do Result := False;
    end;
  finally
    ComLeave(C);
  end;
end;

{ ---------------------------------------------------------------------------- }
{ Кодеци                                                                       }
{ ---------------------------------------------------------------------------- }

type
  TCodecStrKind = (cskName, cskExt, cskMime);

function CodecStr(const Info: IWICBitmapCodecInfo; Kind: TCodecStrKind): string;
var
  N: UINT;
  Buf: UnicodeString;
  hr: HRESULT;
begin
  Result := '';
  N := 0;
  case Kind of
    cskName: Info.GetFriendlyName(0, nil, N);
    cskExt:  Info.GetFileExtensions(0, nil, N);
    cskMime: Info.GetMimeTypes(0, nil, N);
  end;
  if N = 0 then Exit;
  SetLength(Buf, N);
  case Kind of
    cskName: hr := Info.GetFriendlyName(N, PWideChar(Buf), N);
    cskExt:  hr := Info.GetFileExtensions(N, PWideChar(Buf), N);
    cskMime: hr := Info.GetMimeTypes(N, PWideChar(Buf), N);
  else
    hr := E_FAIL;
  end;
  if Failed(hr) then Exit;
  Result := UTF8Encode(UnicodeString(PWideChar(Buf)));
end;

procedure EnumKind(const Factory: IWICImagingFactory; Kind: DWORD;
  var List: TWicCodecInfoArray);
var
  Enum: IWicEnumUnknown;
  Unk: IUnknown;
  Info: IWICBitmapCodecInfo;
  Fetched: ULONG;
  Item: TWicCodecInfo;
begin
  if Failed(Factory.CreateComponentEnumerator(Kind, WICComponentEnumerateDefault, Enum))
    or (Enum = nil) then
    Exit;
  while True do
  begin
    Unk := nil;
    Fetched := 0;
    if (Enum.Next(1, Unk, @Fetched) <> S_OK) or (Fetched = 0) then
      Break;
    if Supports(Unk, IWICBitmapCodecInfo, Info) then
    begin
      Item := Default(TWicCodecInfo);
      Item.FriendlyName := CodecStr(Info, cskName);
      Item.Extensions := LowerCase(CodecStr(Info, cskExt));
      Item.MimeTypes := CodecStr(Info, cskMime);
      Info.GetContainerFormat(Item.ContainerFormat);
      Info.GetCLSID(Item.Clsid);
      Item.IsEncoder := Kind = WICEncoder;
      SetLength(List, Length(List) + 1);
      List[High(List)] := Item;
    end;
    Info := nil;
  end;
end;

function DoListCodecs: TWicCodecInfoArray;
var
  Factory: IWICImagingFactory;
begin
  Result := nil;
  Factory := WicCreateFactory;
  EnumKind(Factory, WICDecoder, Result);
  EnumKind(Factory, WICEncoder, Result);
end;

function WicListCodecs: TWicCodecInfoArray;
var
  C: Boolean;
begin
  C := ComEnter;
  try
    Result := DoListCodecs;
  finally
    ComLeave(C);
  end;
end;

{ Windows разделя разширенията със запетая, Wine с точка и запетая. }
function ExtInList(const Ext, List: string): Boolean;
var
  L: string;
begin
  L := StringReplace(LowerCase(List), ' ', '', [rfReplaceAll]);
  L := StringReplace(L, ';', ',', [rfReplaceAll]);
  Result := Pos(',' + NormExt(Ext) + ',', ',' + L + ',') > 0;
end;

function FindCodec(const Ext: string; Encoder: Boolean; out Info: TWicCodecInfo): Boolean;
var
  L: TWicCodecInfoArray;
  I: Integer;
begin
  L := WicListCodecs;
  for I := 0 to High(L) do
    if (L[I].IsEncoder = Encoder) and ExtInList(Ext, L[I].Extensions) then
    begin
      Info := L[I];
      Exit(True);
    end;
  Result := False;
end;

function WicCanDecode(const Ext: string): Boolean;
var
  I: TWicCodecInfo;
begin
  Result := FindCodec(Ext, False, I);
end;

function TryCreateEncoder(const Container: TGUID): Boolean;
var
  Factory: IWICImagingFactory;
  Enc: IWICBitmapEncoder;
begin
  Factory := WicCreateFactory;
  Result := Succeeded(Factory.CreateEncoder(Container, nil, Enc)) and (Enc <> nil);
end;

{ Регистриран енкодер не значи работещ: някои от Store (напр. JPEG XL на
  определени машини) се регистрират, но отказват да се създадат. }
function WicCanEncode(const Ext: string): Boolean;
var
  I: TWicCodecInfo;
  C: Boolean;
begin
  Result := FindCodec(Ext, True, I);
  if not Result then Exit;
  C := ComEnter;
  try
    Result := TryCreateEncoder(I.ContainerFormat);
  finally
    ComLeave(C);
  end;
end;

function WicContainerForExt(const Ext: string): TGUID;
var
  E: string;
  Info: TWicCodecInfo;
begin
  E := NormExt(Ext);
  if (E = '.jpg') or (E = '.jpeg') or (E = '.jpe') or (E = '.jfif') then Exit(GUID_ContainerFormatJpeg);
  if E = '.png' then Exit(GUID_ContainerFormatPng);
  if (E = '.tif') or (E = '.tiff') then Exit(GUID_ContainerFormatTiff);
  if (E = '.bmp') or (E = '.dib') then Exit(GUID_ContainerFormatBmp);
  if E = '.gif' then Exit(GUID_ContainerFormatGif);
  if (E = '.jxr') or (E = '.wdp') or (E = '.hdp') then Exit(GUID_ContainerFormatWmp);
  if (E = '.heic') or (E = '.heif') or (E = '.hif') or (E = '.avif') then Exit(GUID_ContainerFormatHeif);
  if E = '.webp' then Exit(GUID_ContainerFormatWebp);
  if E = '.dds' then Exit(GUID_ContainerFormatDds);
  if E = '.ico' then Exit(GUID_ContainerFormatIco);
  // Непознато разширение: питаме регистрираните енкодери (вкл. от Store)
  if FindCodec(E, True, Info) then Exit(Info.ContainerFormat);
  raise EWicError.CreateFmt('WIC: няма енкодер за разширение "%s"', [Ext]);
end;

{ ---------------------------------------------------------------------------- }
{ Запис                                                                        }
{ ---------------------------------------------------------------------------- }

function NeedsQuality(const G: TGUID): Boolean;
begin
  Result := IsEqualGUID(G, GUID_ContainerFormatJpeg) or
            IsEqualGUID(G, GUID_ContainerFormatWmp) or
            IsEqualGUID(G, GUID_ContainerFormatHeif) or
            IsEqualGUID(G, GUID_ContainerFormatWebp);
end;

{ ---------------------------------------------------------------------------- }
{ Копиране на метаданни                                                        }
{ ---------------------------------------------------------------------------- }

const
  { Photo policy имената: WIC сам ги превежда към правилното място за всеки
    формат (EXIF в JPEG/TIFF, IFD в HEIF, XMP...). Затова работят между формати. }
  BasicPolicies: array[0..34] of string = (
    'System.Photo.DateTaken',
    'System.Photo.CameraManufacturer',
    'System.Photo.CameraModel',
    'System.ApplicationName',
    'System.Photo.ExposureTime',
    'System.Photo.FNumber',
    'System.Photo.ISOSpeed',
    'System.Photo.FocalLength',
    'System.Photo.FocalLengthInFilm',
    'System.Photo.ExposureBias',
    'System.Photo.ExposureProgram',
    'System.Photo.MeteringMode',
    'System.Photo.Flash',
    'System.Photo.WhiteBalance',
    'System.Photo.MaxAperture',
    'System.Photo.SubjectDistance',
    'System.Photo.LensManufacturer',
    'System.Photo.LensModel',
    'System.Author',
    'System.Copyright',
    'System.Title',
    'System.Subject',
    'System.Comment',
    'System.Keywords',
    'System.Rating',
    'System.GPS.VersionID',
    'System.GPS.Latitude',
    'System.GPS.LatitudeRef',
    'System.GPS.Longitude',
    'System.GPS.LongitudeRef',
    'System.GPS.Altitude',
    'System.GPS.AltitudeRef',
    'System.GPS.ImgDirection',
    'System.GPS.ImgDirectionRef',
    'System.GPS.Date');

  { Резервен път: сурови EXIF тагове (подпът спрямо корена на IFD).
    Ползват се само ако policy копирането не е сложило стойността. }
  RawTags: array[0..15] of string = (
    '/{ushort=271}', '/{ushort=272}', '/{ushort=305}', '/{ushort=306}',
    '/exif/{ushort=36867}', '/exif/{ushort=36868}', '/exif/{ushort=33434}',
    '/exif/{ushort=33437}', '/exif/{ushort=34855}', '/exif/{ushort=37386}',
    '/gps/{ushort=0}', '/gps/{ushort=1}', '/gps/{ushort=2}', '/gps/{ushort=3}',
    '/gps/{ushort=4}', '/gps/{ushort=6}');

function IfdRootFor(const Container: TGUID): string;
begin
  if IsEqualGUID(Container, GUID_ContainerFormatJpeg) then Result := '/app1/ifd'
  else if IsEqualGUID(Container, GUID_ContainerFormatTiff) or
          IsEqualGUID(Container, GUID_ContainerFormatHeif) then Result := '/ifd'
  else Result := '';
end;

function SetValue(const W: IWICMetadataQueryWriter; const Path: string;
  var PV: TWicPropVariant): Boolean;
var
  U: UnicodeString;
begin
  U := UnicodeString(Path);
  Result := Succeeded(W.SetMetadataByName(PWideChar(U), @PV));
end;

function SetUI2(const W: IWICMetadataQueryWriter; const Path: string; Value: Word): Boolean;
var
  PV: TWicPropVariant;
begin
  PV := Default(TWicPropVariant);
  PV.vt := VT_UI2;
  PV.uiVal := Value;
  Result := SetValue(W, Path, PV);
end;

procedure RemovePath(const W: IWICMetadataQueryWriter; const Path: string);
var
  U: UnicodeString;
begin
  U := UnicodeString(Path);
  W.RemoveMetadataByName(PWideChar(U));
end;

{ Копира стойност от R в W по същия път, ако я има в R. }
function CopyPath(const R: IWICMetadataQueryReader; const W: IWICMetadataQueryWriter;
  const SrcPath, DstPath: string): Boolean;
var
  PV: TWicPropVariant;
begin
  Result := False;
  if not QueryValue(R, SrcPath, PV) then Exit;
  try
    if PV.vt <> VT_EMPTY then
      Result := SetValue(W, DstPath, PV);
  finally
    wicPropVariantClear(@PV);
  end;
end;

{ Обновява EXIF PixelXDimension/PixelYDimension, ако ги има, със същия тип. }
procedure FixDimension(const W: IWICMetadataQueryWriter; const Path: string; Value: Integer);
var
  PV: TWicPropVariant;
begin
  if not QueryValue(W, Path, PV) then Exit;
  try
    case PV.vt of
      VT_UI2: PV.uiVal := Value;
      VT_UI4: PV.ulVal := Value;
    else
      Exit;
    end;
    SetValue(W, Path, PV);
  finally
    wicPropVariantClear(@PV);
  end;
end;

procedure CopyBasic(const R: IWICMetadataQueryReader; const W: IWICMetadataQueryWriter;
  const SrcContainer, DstContainer: TGUID; CopyOrientation, StripGps: Boolean);
var
  I: Integer;
  SrcRoot, DstRoot: string;
begin
  for I := Low(BasicPolicies) to High(BasicPolicies) do
    if not (StripGps and (Pos('System.GPS.', BasicPolicies[I]) = 1)) then
      CopyPath(R, W, BasicPolicies[I], BasicPolicies[I]);
  if CopyOrientation then
    CopyPath(R, W, 'System.Photo.Orientation', 'System.Photo.Orientation');

  // Резервен път за JPEG/TIFF -> JPEG/TIFF: сурови тагове, които липсват
  SrcRoot := FindIfdRoot(R);
  DstRoot := IfdRootFor(DstContainer);
  if (SrcRoot = '') or (DstRoot = '') then Exit;
  for I := Low(RawTags) to High(RawTags) do
    if not (StripGps and (Pos('/gps/', RawTags[I]) = 1)) and not PathExists(W, DstRoot + RawTags[I]) then
      CopyPath(R, W, SrcRoot + RawTags[I], DstRoot + RawTags[I]);
  if CopyOrientation and not PathExists(W, DstRoot + '/{ushort=274}') then
    CopyPath(R, W, SrcRoot + '/{ushort=274}', DstRoot + '/{ushort=274}');
end;

{ Прехвърля метаданните на SrcFrame в DstFrame според режима. Метаданните са
  „най-доброто възможно“: ако нещо не се поддържа от целевия формат, просто
  го пропускаме, вместо да проваляме целия запис. }
const
  // Местоположението, извън EXIF GPS директорията: XMP и photo policy имената
  GpsXmp: array[0..11] of string = ('exif:GPSLatitude', 'exif:GPSLongitude', 'exif:GPSAltitude',
    'exif:GPSAltitudeRef', 'exif:GPSTimeStamp', 'exif:GPSVersionID', 'exif:GPSMapDatum',
    'exif:GPSImgDirection', 'exif:GPSImgDirectionRef', 'exif:GPSSpeed', 'exif:GPSSpeedRef',
    'exif:GPSProcessingMethod');

{ Маха местоположението от вече копирани метаданни. Всичко, което не съществува, просто се
  пропуска - важно е след това WicGetPhotoInfo да не намира GPS (проверено в тестовете). }
procedure RemoveGps(const W: IWICMetadataQueryWriter; const DstContainer: TGUID);
var
  Root: string;
  I: Integer;
begin
  Root := IfdRootFor(DstContainer);
  if Root <> '' then
  begin
    RemovePath(W, Root + '/gps');
    RemovePath(W, Root + '/{ushort=34853}');
  end;
  for I := Low(GpsXmp) to High(GpsXmp) do
  begin
    RemovePath(W, '/xmp/' + GpsXmp[I]);
    if Root = '/app1/ifd' then RemovePath(W, '/app1/xmp/' + GpsXmp[I]);
  end;
  for I := Low(BasicPolicies) to High(BasicPolicies) do
    if Pos('System.GPS.', BasicPolicies[I]) = 1 then
      RemovePath(W, BasicPolicies[I]);
end;

{ ColorConverted: пикселите са преобразувани към sRGB - профилът на източника вече не важи,
  затова 1:1 копирането на блокове се заменя с основното (иначе би се пренесъл и старият ICC
  профил), а EXIF ColorSpace става 1 (sRGB). }
procedure CopyMetadata(const SrcFrame: IWICBitmapFrameDecode;
  const SrcContainer: TGUID; const DstFrame: IWICBitmapFrameEncode;
  const DstContainer: TGUID; Mode: TWicMetadataMode; PixelsUpright: Boolean;
  NewWidth, NewHeight: Integer; StripGps: Boolean = False; ColorConverted: Boolean = False);
var
  R: IWICMetadataQueryReader;
  W: IWICMetadataQueryWriter;
  BR: IWICMetadataBlockReader;
  BW: IWICMetadataBlockWriter;
  Root: string;
  SrcW, SrcH: UINT;
  Orient: Integer;
  Changed: Boolean;
begin
  if Mode = wmNone then Exit;
  if Failed(SrcFrame.GetMetadataQueryReader(R)) or (R = nil) then Exit;

  if (Mode = wmAll) and not ColorConverted and IsEqualGUID(SrcContainer, DstContainer) and
     Supports(SrcFrame, IWICMetadataBlockReader, BR) and
     Supports(DstFrame, IWICMetadataBlockWriter, BW) and
     Succeeded(BW.InitializeFromBlockReader(BR)) then
  begin
    // Всичко е копирано 1:1. Оправяме само това, което вече не е вярно.
    if Failed(DstFrame.GetMetadataQueryWriter(W)) or (W = nil) then Exit;
    Orient := ReadOrientation(SrcFrame);
    SrcFrame.GetSize(SrcW, SrcH);
    // Изправените пиксели при ориентация 5..8 имат разменени страни спрямо
    // суровия кадър; суровите (PixelsUpright=False) не са разменени.
    if PixelsUpright and (Orient >= 5) then
      Changed := (Integer(SrcH) <> NewWidth) or (Integer(SrcW) <> NewHeight)
    else
      Changed := (Integer(SrcW) <> NewWidth) or (Integer(SrcH) <> NewHeight);
    Root := IfdRootFor(DstContainer);
    if PixelsUpright and (Orient <> 1) then
    begin
      if not SetUI2(W, 'System.Photo.Orientation', 1) and (Root <> '') then
        SetUI2(W, Root + '/{ushort=274}', 1);
      Changed := True;
    end;
    if Root <> '' then
    begin
      FixDimension(W, Root + '/exif/{ushort=40962}', NewWidth);
      FixDimension(W, Root + '/exif/{ushort=40963}', NewHeight);
    end;
    // Вградената миниатюра вече не съответства (завъртяна или изрязана)
    if Changed and IsEqualGUID(DstContainer, GUID_ContainerFormatJpeg) then
      RemovePath(W, '/app1/thumb');
    if StripGps then RemoveGps(W, DstContainer);
    Exit;
  end;

  // wmBasic, или wmAll между различни формати / след цветово преобразуване
  if Failed(DstFrame.GetMetadataQueryWriter(W)) or (W = nil) then Exit;
  CopyBasic(R, W, SrcContainer, DstContainer, not PixelsUpright, StripGps);
  if ColorConverted then
  begin
    Root := IfdRootFor(DstContainer);
    if not SetUI2(W, 'System.Image.ColorSpace', 1) and (Root <> '') then
      SetUI2(W, Root + '/exif/{ushort=40961}', 1);
  end;
end;

procedure DoSave(const Img: TWicImage; const FileName: string; Quality: Single;
  const MetaSrc: string; MetaMode: TWicMetadataMode; PixelsUpright: Boolean;
  var Created: Boolean; StripGps: Boolean = False; ColorConverted: Boolean = False);
var
  SrcDecoder: IWICBitmapDecoder;
  SrcFrame: IWICBitmapFrameDecode;
  SrcContainer: TGUID;
  Factory: IWICImagingFactory;
  Stream: IWICStream;
  Encoder: IWICBitmapEncoder;
  Frame: IWICBitmapFrameEncode;
  Bag: IWicPropertyBag2;
  Bmp: IWICBitmap;
  Conv: IWICFormatConverter;
  Src: IWICBitmapSource;
  Container, Fmt: TGUID;
  PB: TWicPropBag2;
  V: TWicPropVariant;   // VARIANT и PROPVARIANT имат един и същ layout за VT_R4
  PropName, W: UnicodeString;
begin
  if (Img.Width <= 0) or (Img.Height <= 0) or
     (Length(Img.Pixels) < Img.Width * Img.Height * 4) then
    raise EWicError.Create('WIC: празно или повредено изображение');

  Container := WicContainerForExt(ExtractFileExt(FileName));
  Factory := WicCreateFactory;

  // WIC чете метаданните мързеливо, докато пишем, затова източникът не може
  // да е самият целеви файл: презаписът би го унищожил по средата.
  if (MetaSrc <> '') and (MetaMode <> wmNone) then
  begin
    SrcDecoder := OpenDecoder(Factory, WideName(MetaSrc));
    Check(SrcDecoder.GetFrame(0, SrcFrame), 'GetFrame (метаданни)');
    Check(SrcDecoder.GetContainerFormat(SrcContainer), 'GetContainerFormat');
  end;

  Check(Factory.CreateStream(Stream), 'CreateStream');
  W := WideName(FileName);
  Check(Stream.InitializeFromFilename(PWideChar(W), GENERIC_WRITE),
    'Stream.InitializeFromFilename');
  Created := True;   // от тук нататък при грешка файлът е наш и е счупен
  Check(Factory.CreateEncoder(Container, nil, Encoder), 'CreateEncoder');
  Check(Encoder.Initialize(Stream, WICBitmapEncoderNoCache), 'Encoder.Initialize');
  Check(Encoder.CreateNewFrame(Frame, Bag), 'CreateNewFrame');

  if (Bag <> nil) and NeedsQuality(Container) then
  begin
    if Quality < 0 then Quality := 0;
    if Quality > 1 then Quality := 1;
    PropName := 'ImageQuality';
    PB := Default(TWicPropBag2);
    PB.pstrName := PWideChar(PropName);
    V := Default(TWicPropVariant);
    V.vt := VT_R4;
    V.fltVal := Quality;
    Bag.Write(1, @PB, @V);   // ако енкодерът не го поддържа, продължаваме без него
  end;

  Check(Frame.Initialize(Bag), 'Frame.Initialize');
  Check(Frame.SetSize(Img.Width, Img.Height), 'Frame.SetSize');
  Frame.SetResolution(96, 96);
  Fmt := GUID_WICPixelFormat32bppBGRA;
  Check(Frame.SetPixelFormat(Fmt), 'Frame.SetPixelFormat');

  if SrcFrame <> nil then
    CopyMetadata(SrcFrame, SrcContainer, Frame, Container, MetaMode,
      PixelsUpright, Img.Width, Img.Height, StripGps, ColorConverted);

  Check(Factory.CreateBitmapFromMemory(Img.Width, Img.Height,
    GUID_WICPixelFormat32bppBGRA, Img.Width * 4, Img.Width * Img.Height * 4,
    @Img.Pixels[0], Bmp), 'CreateBitmapFromMemory');
  Src := Bmp;

  // Енкодерът може да е договорил друг формат (напр. JPEG -> 24bppBGR)
  if not IsEqualGUID(Fmt, GUID_WICPixelFormat32bppBGRA) then
  begin
    Check(Factory.CreateFormatConverter(Conv), 'CreateFormatConverter');
    Check(Conv.Initialize(Src, Fmt, WICBitmapDitherTypeNone, nil, 0,
      WICBitmapPaletteTypeCustom),
      'FormatConverter.Initialize (форматът изисква палитра? GIF не се поддържа)');
    Src := Conv;
  end;

  Check(Frame.WriteSource(Src, nil), 'Frame.WriteSource');
  Check(Frame.Commit, 'Frame.Commit');
  Check(Encoder.Commit, 'Encoder.Commit');
end;

procedure SaveImpl(const Img: TWicImage; const FileName: string; Quality: Single;
  const MetaSrc: string; MetaMode: TWicMetadataMode; PixelsUpright: Boolean;
  StripGps: Boolean = False; ColorConverted: Boolean = False);
var
  C, Created: Boolean;
begin
  if (MetaSrc <> '') and (MetaMode <> wmNone) and
     SameText(ExpandFileName(MetaSrc), ExpandFileName(FileName)) then
    raise EWicError.Create('WIC: източникът на метаданни не може да е самият целеви файл');
  Created := False;
  C := ComEnter;
  try
    try
      DoSave(Img, FileName, Quality, MetaSrc, MetaMode, PixelsUpright, Created, StripGps, ColorConverted);
    except
      // трием само полузаписан файл, който сме създали ние
      if Created then
        SysUtils.DeleteFile(WideName(FileName));
      raise;
    end;
  finally
    ComLeave(C);
  end;
end;

procedure WicSave(const Img: TWicImage; const FileName: string; Quality: Single);
begin
  SaveImpl(Img, FileName, Quality, '', wmNone, True);
end;

procedure WicSaveWithMetadataFrom(const Img: TWicImage; const DstFile,
  MetadataSrcFile: string; Quality: Single; Metadata: TWicMetadataMode;
  PixelsUpright: Boolean);
begin
  SaveImpl(Img, DstFile, Quality, MetadataSrcFile, Metadata, PixelsUpright);
end;

procedure WicConvert(const SrcFile, DstFile: string; MaxSide: Integer;
  Quality: Single; Metadata: TWicMetadataMode);
begin
  SaveImpl(WicLoad(SrcFile, MaxSide, True), DstFile, Quality, SrcFile, Metadata, True);
end;

function WicDefaultExportOptions: TWicExportOptions;
begin
  Result.MaxSide := 0;
  Result.Quality := 0.9;
  Result.Metadata := wmAll;
  Result.StripGps := True;
  Result.ToSrgb := True;
end;

function WicExportFileW(const SrcFile, DstFile: UnicodeString;
  const Opt: TWicExportOptions): TWicExportResult;
var
  Img: TWicImage;
  Conv: Boolean;
begin
  Result := Default(TWicExportResult);
  Conv := False;
  Img := WicLoadBestW(SrcFile, Opt.MaxSide, Opt.ToSrgb, @Conv);
  SaveImpl(Img, UTF8Encode(DstFile), Opt.Quality, UTF8Encode(SrcFile), Opt.Metadata, True,
    Opt.StripGps and (Opt.Metadata <> wmNone), Conv);
  Result.Width := Img.Width;
  Result.Height := Img.Height;
  Result.ColorConverted := Conv;
end;

{ ---------------------------------------------------------------------------- }
{ Обработка                                                                    }
{ ---------------------------------------------------------------------------- }

function DoResize(const Img: TWicImage; NW, NH: Integer; Mode: TWicInterpolation): TWicImage;
var
  Factory: IWICImagingFactory;
  Bmp: IWICBitmap;
begin
  Factory := WicCreateFactory;
  Check(Factory.CreateBitmapFromMemory(Img.Width, Img.Height,
    GUID_WICPixelFormat32bppBGRA, Img.Width * 4, Img.Width * Img.Height * 4,
    @Img.Pixels[0], Bmp), 'CreateBitmapFromMemory');
  Result := SourceToImage(Factory, MakeScaler(Factory, Bmp, NW, NH, Mode));
end;

function WicResize(const Img: TWicImage; NewWidth, NewHeight: Integer;
  Mode: TWicInterpolation): TWicImage;
var
  C: Boolean;
begin
  if (Img.Width <= 0) or (NewWidth <= 0) or (NewHeight <= 0) then
    raise EWicError.Create('WIC: невалиден размер');
  C := ComEnter;
  try
    Result := DoResize(Img, NewWidth, NewHeight, Mode);
  finally
    ComLeave(C);
  end;
end;

function WicToHBITMAP(const Img: TWicImage; Premultiply: Boolean): HBITMAP;
var
  BI: TBitmapInfo;
  Bits: Pointer;
  P: PByte;
  I: Integer;
  A: Integer;
begin
  BI := Default(TBitmapInfo);
  BI.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
  BI.bmiHeader.biWidth := Img.Width;
  BI.bmiHeader.biHeight := -Img.Height;   // отгоре надолу
  BI.bmiHeader.biPlanes := 1;
  BI.bmiHeader.biBitCount := 32;
  BI.bmiHeader.biCompression := BI_RGB;
  Bits := nil;
  Result := CreateDIBSection(0, BI, DIB_RGB_COLORS, Bits, 0, 0);
  if (Result = 0) or (Bits = nil) then
    raise EWicError.Create('WIC: CreateDIBSection неуспешно');
  Move(Img.Pixels[0], Bits^, Img.Width * Img.Height * 4);
  if Premultiply then
  begin
    P := Bits;
    for I := 0 to Img.Width * Img.Height - 1 do
    begin
      A := P[3];
      if A < 255 then
      begin
        P[0] := (P[0] * A + 127) div 255;
        P[1] := (P[1] * A + 127) div 255;
        P[2] := (P[2] * A + 127) div 255;
      end;
      Inc(P, 4);
    end;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ Метаданни: публични                                                          }
{ ---------------------------------------------------------------------------- }

function GpsCoord(const Reader: IWICMetadataQueryReader; const GpsRoot: string;
  ValTag, RefTag: Integer; out Value: Double): Boolean;
var
  PV: TWicPropVariant;
  Q: PQWord;
  Ref: string;
begin
  Result := False;
  Value := 0;
  if not QueryValue(Reader, Format('%s/{ushort=%d}', [GpsRoot, ValTag]), PV) then Exit;
  try
    if (PV.vt = (VT_VECTOR or VT_UI8)) and (PV.cElems >= 3) and (PV.pElems <> nil) then
    begin
      Q := PV.pElems;
      Value := RationalToFloat(Q[0]) + RationalToFloat(Q[1]) / 60 +
               RationalToFloat(Q[2]) / 3600;
      Result := True;
    end;
  finally
    wicPropVariantClear(@PV);
  end;
  if Result then
  begin
    Ref := UpperCase(QueryStr(Reader, Format('%s/{ushort=%d}', [GpsRoot, RefTag])));
    if (Ref = 'S') or (Ref = 'W') then
      Value := -Value;
  end;
end;

function DoPhotoInfo(const FileName: UnicodeString): TWicPhotoInfo;
var
  Factory: IWICImagingFactory;
  Decoder: IWICBitmapDecoder;
  Frame: IWICBitmapFrameDecode;
  R: IWICMetadataQueryReader;
  Root, Exif, Gps: string;
  D: Double;
begin
  Result := Default(TWicPhotoInfo);
  Factory := WicCreateFactory;
  Decoder := OpenDecoder(Factory, FileName);
  Check(Decoder.GetFrame(0, Frame), 'GetFrame');
  Result.Orientation := ReadOrientation(Frame);
  if Failed(Frame.GetMetadataQueryReader(R)) or (R = nil) then Exit;
  Root := FindIfdRoot(R);
  if Root = '' then Exit;
  Exif := Root + '/exif';
  Gps := Root + '/gps';

  Result.Make     := QueryStr(R, Root + '/{ushort=271}');
  Result.Model    := QueryStr(R, Root + '/{ushort=272}');
  Result.Software := QueryStr(R, Root + '/{ushort=305}');
  Result.Lens     := QueryStr(R, Exif + '/{ushort=42036}');          // LensModel
  Result.DateTaken := QueryStr(R, Exif + '/{ushort=36867}');      // DateTimeOriginal
  if Result.DateTaken = '' then
    Result.DateTaken := QueryStr(R, Root + '/{ushort=306}');      // DateTime
  QueryFloat(R, Exif + '/{ushort=33434}', Result.ExposureTime);
  QueryFloat(R, Exif + '/{ushort=33437}', Result.FNumber);
  QueryFloat(R, Exif + '/{ushort=37386}', Result.FocalLength);
  if QueryFloat(R, Exif + '/{ushort=34855}', D) then
    Result.ISO := Round(D);

  Result.HasGPS := GpsCoord(R, Gps, 2, 1, Result.Latitude) and
                   GpsCoord(R, Gps, 4, 3, Result.Longitude);
  if not Result.HasGPS then
  begin
    Result.Latitude := 0;
    Result.Longitude := 0;
  end;
end;

function WicGetPhotoInfoW(const FileName: UnicodeString): TWicPhotoInfo;
var
  C: Boolean;
begin
  C := ComEnter;
  try
    Result := DoPhotoInfo(FileName);
  finally
    ComLeave(C);
  end;
end;

function WicGetPhotoInfo(const FileName: string): TWicPhotoInfo;
var
  C: Boolean;
begin
  C := ComEnter;
  try
    Result := DoPhotoInfo(WideName(FileName));
  finally
    ComLeave(C);
  end;
end;

function FormatProp(const PV: TWicPropVariant): string;
const
  MaxShow = 16;
var
  I, N: Integer;
  Base: Word;
  P: PByte;
  ST: TSystemTime;
  FT: TFileTime;
begin
  if (PV.vt and VT_VECTOR) <> 0 then
  begin
    Base := PV.vt and not VT_VECTOR;
    N := PV.cElems;
    P := PV.pElems;
    if (P = nil) or (N = 0) then Exit('[]');
    if (Base = VT_UI1) and (N > MaxShow) then
      Exit(Format('<%d байта>', [N]));
    Result := '[';
    for I := 0 to N - 1 do
    begin
      if I >= MaxShow then begin Result := Result + ', ...'; Break; end;
      if I > 0 then Result := Result + ', ';
      case Base of
        VT_UI1: Result := Result + IntToStr(P[I]);
        VT_UI2: Result := Result + IntToStr(PWord(P)[I]);
        VT_UI4: Result := Result + IntToStr(PLongWord(P)[I]);
        VT_I4:  Result := Result + IntToStr(PLongInt(P)[I]);
        VT_UI8: Result := Result + Format('%d/%d',
                  [PQWord(P)[I] and $FFFFFFFF, PQWord(P)[I] shr 32]);
        VT_I8:  Result := Result + Format('%d/%d',
                  [LongInt(PInt64(P)[I] and $FFFFFFFF), LongInt(QWord(PInt64(P)[I]) shr 32)]);
        VT_R8:  Result := Result + FloatToStr(PDouble(P)[I]);
        VT_LPSTR:  Result := Result + '"' + string(PPAnsiChar(P)[I]) + '"';
        VT_LPWSTR: Result := Result + '"' + UTF8Encode(UnicodeString(PPWideChar(P)[I])) + '"';
      else
        Exit(Format('<вектор vt=%d, %d бр.>', [Base, N]));
      end;
    end;
    Result := Result + ']';
    Exit;
  end;

  case PV.vt of
    VT_EMPTY:  Result := '<празно>';
    VT_LPSTR:  Result := '"' + string(PV.pszVal) + '"';
    VT_LPWSTR: Result := '"' + UTF8Encode(UnicodeString(PV.pwszVal)) + '"';
    VT_BOOL:   Result := BoolToStr(PV.boolVal <> 0, True);
    VT_I1, VT_UI1: Result := IntToStr(PV.bVal);
    VT_I2:     Result := IntToStr(PV.iVal);
    VT_UI2:    Result := IntToStr(PV.uiVal);
    VT_I4:     Result := IntToStr(PV.lVal);
    VT_UI4:    Result := IntToStr(PV.ulVal);
    VT_R4:     Result := FloatToStr(PV.fltVal);
    VT_R8:     Result := FloatToStr(PV.dblVal);
    VT_UI8:    if (PV.uhVal shr 32) <> 0 then
                 Result := Format('%d/%d', [PV.uhVal and $FFFFFFFF, PV.uhVal shr 32])
               else
                 Result := IntToStr(PV.uhVal);
    VT_I8:     Result := IntToStr(PV.hVal);
    VT_BLOB:   Result := Format('<blob %d байта>', [PV.cElems]);
    VT_CLSID:  if PV.punkVal <> nil then Result := GUIDToString(PGUID(PV.punkVal)^)
               else Result := '<clsid>';
    VT_FILETIME:
      begin
        FT := PV.filetime;
        if FileTimeToSystemTime(FT, ST) then
          Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', SystemTimeToDateTime(ST))
        else
          Result := '<filetime>';
      end;
  else
    Result := Format('<vt=%d>', [PV.vt]);
  end;
end;

procedure DumpReader(const Reader: IWICMetadataQueryReader; const Prefix: string;
  Lines: TStrings; Depth: Integer);
var
  Enum: IWicEnumString;
  Name: PWideChar;
  Fetched: ULONG;
  Path: string;
  PV: TWicPropVariant;
  Sub: IWICMetadataQueryReader;
begin
  if (Depth > 8) or Failed(Reader.GetEnumerator(Enum)) or (Enum = nil) then Exit;
  while True do
  begin
    Name := nil;
    Fetched := 0;
    if (Enum.Next(1, Name, @Fetched) <> S_OK) or (Fetched = 0) or (Name = nil) then
      Break;
    try
      Path := Prefix + UTF8Encode(UnicodeString(Name));
      FillChar(PV, SizeOf(PV), 0);
      if Succeeded(Reader.GetMetadataByName(Name, @PV)) then
      try
        if (PV.vt = VT_UNKNOWN) and (PV.punkVal <> nil) then
        begin
          Sub := nil;
          if Succeeded(IUnknown(PV.punkVal).QueryInterface(IWICMetadataQueryReader, Sub))
            and (Sub <> nil) then
            DumpReader(Sub, Path, Lines, Depth + 1);
          Sub := nil;
        end
        else
          Lines.Add(Path + ' = ' + FormatProp(PV));
      finally
        wicPropVariantClear(@PV);
      end;
    finally
      wicCoTaskMemFree(Name);
    end;
  end;
end;

procedure DoDump(const FileName: string; Lines: TStrings);
var
  Factory: IWICImagingFactory;
  Decoder: IWICBitmapDecoder;
  Frame: IWICBitmapFrameDecode;
  R: IWICMetadataQueryReader;
begin
  Factory := WicCreateFactory;
  Decoder := OpenDecoder(Factory, WideName(FileName));
  // Метаданни на ниво контейнер (GIF, някои TIFF-ове)
  if Succeeded(Decoder.GetMetadataQueryReader(R)) and (R <> nil) then
    DumpReader(R, '', Lines, 0);
  R := nil;
  Check(Decoder.GetFrame(0, Frame), 'GetFrame');
  if Succeeded(Frame.GetMetadataQueryReader(R)) and (R <> nil) then
    DumpReader(R, '', Lines, 0);
end;

procedure WicDumpMetadata(const FileName: string; Lines: TStrings);
var
  C: Boolean;
begin
  C := ComEnter;
  try
    DoDump(FileName, Lines);
  finally
    ComLeave(C);
  end;
end;

end.
