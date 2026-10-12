# WIC за Lazarus

Windows Imaging Component от Free Pascal / Lazarus. Ползва кодеците, които Windows вече има: JPEG, PNG, TIFF, BMP, GIF, ICO, JPEG-XR, а с безплатните разширения от Store и HEIC/HEIF, WebP, AVIF и RAW от фотоапарати. Не са нужни външни DLL-и.

## Файлове

| Файл | Какво е |
|---|---|
| `WicImaging.pas` | Ядрото. Зависи само от `Windows`, `SysUtils`, `Classes`, не ползва ActiveX/ComObj/LCL. Става и за конзолни програми и услуги. |
| `WicLCL.pas` | Мост към `TBitmap` / `TPicture` и филтър за `TOpenDialog`. |
| `demo/` | Демо приложение: отваряш снимка, гледаш EXIF, записваш в друг формат. Отвори `wicdemo.lpi`. |
| `test/` | над 100 автоматични проверки. Пусни `run_test.bat`. |
| `probe/` | Диагностика: кои декодери има машината за даден файл, какъв размер дават и за колко време. `wicprobe.bat файл.dng` (при първо пускане се компилира). |

## Бърз старт

```pascal
uses WicImaging, WicLCL;

// Зареждане с изправяне по EXIF и смаляване до 1600 px по дългата страна
WicLoadBitmap('C:\Снимки\IMG_1234.HEIC', Image1.Picture.Bitmap, 1600);

// Запис; форматът се взима от разширението
WicSaveBitmap(Image1.Picture.Bitmap, 'C:\out\snimka.jpg', 0.85);

// Конвертиране с едно извикване, без LCL; EXIF и GPS се запазват
WicConvert('vhod.heic', 'izhod.jpg', 2048, 0.9);

// Редакция в паметта и запис с метаданните на оригинала
Img := WicLoad('IMG_1234.jpg');
...
WicSaveWithMetadataFrom(Img, 'IMG_1234_edit.jpg', 'IMG_1234.jpg');

// За публикуване: без EXIF и без GPS
WicConvert('IMG_1234.jpg', 'za_web.jpg', 1600, 0.85, wmNone);

// EXIF
Info := WicGetPhotoInfo('IMG_1234.jpg');
Caption := Format('%s %s, ISO %d, %.6f %.6f',
  [Info.Make, Info.Model, Info.ISO, Info.Latitude, Info.Longitude]);

// Какво може тази машина
if WicCanDecode('.heic') then ...
OpenDialog1.Filter := WicOpenDialogFilter;
```

## API

| Функция | |
|---|---|
| `WicLoad(FN, MaxSide, AutoRotate)` | → `TWicImage` (BGRA, права алфа, отгоре надолу) |
| `WicLoadFrame(FN, Index, ...)` / `WicGetFrameCount` | многостраничен TIFF, GIF |
| `WicGetImageSize(FN, W, H)` | размер без декодиране, чете само хедъра |
| `WicLoadEmbeddedThumbnail` | вградената EXIF миниатюра, мигновено |
| `WicSave(Img, FN, Quality)` | запис по разширение; Quality за JPEG/JXR/HEIF |
| `WicConvert(Src, Dst, MaxSide, Quality, Metadata)` | зареждане, изправяне, смаляване и запис с едно извикване |
| `WicSaveWithMetadataFrom(Img, Dst, Src, ...)` | запис на обработено изображение с метаданните на оригинала |
| `WicResize(Img, W, H, Mode)` | HighQualityCubic (Win10+), с автоматичен преход към Fant |
| `WicApplyOrientation(Img, 1..8)` | EXIF ориентация върху пикселите |
| `WicToHBITMAP(Img, Premultiply)` | DIB section за чист WinAPI / AlphaBlend |
| `WicGetPhotoInfo` | камера, дата, експонация, бленда, ISO, фокус, GPS |
| `WicDumpMetadata(FN, Lines)` | всички метаданни като `път = стойност` |
| `WicListCodecs`, `WicCanDecode/Encode` | кодеците на машината, вкл. от Store; `WicCanEncode` проверява, че енкодерът реално се създава |
| `WicLoadPreviewW`, `WicLoadThumbW` | вграденото превю (RAW) / миниатюра; черните миниатюри от телефони се отхвърлят |
| `WicLoadBestW(FN, MaxSide, ToSrgb)` | най-доброто до размера: превюто, ако е достатъчно голямо, иначе пълното декодиране; по избор към sRGB |
| `WicExportFileW(Src, Dst, Opt)` | един файл за експорт: най-добро изображение, sRGB, смаляване, метаданни с/без GPS |
| `WicColorInfoW` | какъв е цветовият профил (за проверка) |

**RAW:** за пикселите се ползва изрично Microsoft Raw Image Decoder, когато поддържа разширението, защото за `.dng` Windows сам избира стария DNG Decoder, който дава само вграденото превю. Метаданните се четат от декодера по подразбиране.

**sRGB:** профилът на кадъра се взима с `GetColorContexts`. Ако е sRGB (по описанието в ICC) или липсва, пикселите не се пипат, иначе минават през `IWICColorTransform`. В теста се сверява с littlecms (Pillow) за Adobe RGB, с допуск ±3.

Грешките се хвърлят като `EWicError` с поле `HR` (HRESULT). Пътищата могат да са на кирилица. COM се инициализира и деинициализира балансирано във всяко извикване, така че е безопасно и в нишки.

## Метаданни при запис

| Режим | Какво става |
|---|---|
| `wmNone` | Чист файл без EXIF и GPS. За публикуване, без да издаваш къде е снимано. |
| `wmBasic` (по подразбиране) | Камера, обектив, дата, експонация, бленда, ISO, фокус, светкавица, GPS, автор, copyright, заглавие, ключови думи и рейтинг. Минава през photo policy имената на Windows, затова работи **и между формати** (JPEG → HEIC/TIFF/JXL). |
| `wmAll` | Всички блокове 1:1, вкл. MakerNote, XMP и IPTC, когато форматът е същият. При различен формат пада до `wmBasic`. |

Ориентацията става 1, защото пикселите вече са изправени. При `wmAll` се обновяват и EXIF размерите, а остарялата вградена миниатюра се маха. С `PixelsUpright=False` се запазва оригиналната ориентация.

Метаданните са „най-доброто възможно“: ако целевият формат не поддържа някое поле, то просто се пропуска и записът не се проваля. Източникът не може да е самият целеви файл, защото така би се унищожил оригиналът; в този случай функцията отказва с грешка.

## Какво е тествано и как

Тествано е на Linux с FPC 3.2.2 крос-компилиран за win64, под Wine 9:

- **Минава:** четене и запис на PNG, TIFF, BMP и JPEG; правата алфа без загуби; смаляване; всички 8 EXIF ориентации, сверени **пиксел по пиксел** с Pillow (`exif_transpose`); кирилица в пътищата; HBITMAP с премултиплициране; списък с кодеци; грешки при липсващ файл, непознат формат и файл, който не е изображение.
- **LCL** (Lazarus 3.0 изходници, win32 widgetset): `TBitmap`, `Canvas.Pixels`, 24-битов bitmap, алфа round-trip, `TPicture`, филтър за диалога. Всичко е зелено. Демото се компилира и формата се показва.
- **Не може да се провери под Wine** (в теста са `SKIP`, а на истински Windows са задължителни): EXIF от JPEG (`/app1/ifd/...`), под-директориите EXIF и GPS, изброяването на метаданни, `System.Photo.*`, JPEG `ImageQuality` и **целият запис на метаданни**. Wine просто не ги имплементира, проверих HRESULT-ите.
- **Потвърдено на Windows 11** (FPC 3.2.4): целият тест без нито един SKIP, вкл. EXIF от JPEG, GPS, качеството на JPEG, записа на метаданни, махането на GPS, sRGB конверсията и експорта.

**Пусни `test\run_test.bat` на твоята машина.** Там SKIP-овете стават истински проверки, а ако нещо се счупи, прати ми изхода.

## Известни ограничения

- Записът в GIF не е поддържан (изисква палитра). Ползвай PNG.
- Записът на HEIC изисква „HEVC Video Extensions“ от Store. Четенето изисква „HEIF Image Extensions“.
- RAW се декодира с настройките на Windows (без собствена обработка: баланс на бялото, експозиция, шум).
