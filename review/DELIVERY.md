# RAGAA — حالة التسليم (نسخة اختبارية جاهزة للمراجعة)

| العنصر | القيمة |
| --- | --- |
| الفرع | `arena/994cab4e-ragaa` |
| آخر Commit قبل بناء الحزمة | `d54d600` (ثم commits آلية للسجلات والملفات فقط) |
| Workflow | RAGAA Flutter CI & Desktop Builds — run **44815516868** (نجح بالكامل) |
| `flutter analyze` | No issues found |
| `flutter test` | **29** اختبارًا، كلها ناجحة |

## الملفات النهائية (Artifacts)

من صفحة التشغيل:
<https://github.com/ahmadtefa/RAGAA/actions/runs/44815516868>

| الملف | الحجم | Artifact ID |
| --- | --- | --- |
| `RAGAA-Setup.exe` (مثبّت Inno Setup) | 14.2 MB | 14670460470 |
| `RAGAA-Windows-x64-Portable.zip` | 18.1 MB | 14669691640 |
| `RAGAA-release.apk` (+ `sha256`) | 35.7 MB | 14667928988 |
| `RAGAA-Linux-x64-Preview.tar.gz` | 15.8 MB | 14669108051 |
| `RAGAA-review-samples.zip` | 306 KB | 14668868349 |
| `test-coverage-lcov` | 11 KB | 14669512008 |

روابط التنزيل المباشرة (تتطلب تسجيل الدخول إلى GitHub):

- `https://github.com/ahmadtefa/RAGAA/actions/runs/44815516868/artifacts/14670460470`
- `https://github.com/ahmadtefa/RAGAA/actions/runs/44815516868/artifacts/14667928988`

## ما تم التحقق منه فعليًا في هذه الحزمة

- **Windows:** تثبيت صامت (`/VERYSILENT /DIR=...`) ثم التأكد من وجود `ragaa.exe`،
  `flutter_windows.dll`، `sqlite3.dll`، خط Amiri، وإنشاء اختصارَي Start
  (تشغيل + إلغاء تثبيت) ثم إزالة تثبيت صامتة والتأكد من اختفاء البرنامج
  (السجل الكامل: `review/ci/windows-install.log`).
- **Android:** الـAPK يحتوي `libapp.so` لكل من `arm64-v8a` و`armeabi-v7a` و`x86_64`،
  و`libsqlite3.so`، وخطوط Amiri/Tajawal، وتم التحقق من التوقيع بـ`apksigner`
  (V2، شهادة debug) — السجل: `review/ci/apk-verify.log`.
- **التقارير:** ملفات PDF/Excel مولَّدة من بيانات حقيقية داخل CI ومحفوظة في
  `review/`، وتم فحصها بصريًا (رسم صفحات PDF) وبرمجيًا (openpyxl).

## عوائق حقيقية متبقية

1. **اعتماد التصميم النهائي من العميل** — التصميم الحالي مطابق لفرع Work
   (`review/paper/preview.png`) وينتظر التأكيد النهائي.
2. **`RAGAA-Setup.exe` غير موقَّع بشهادة Code Signing** (لا توجد شهادة)، لذلك قد
   يعرض Windows SmartScreen تحذير «ناشر غير معروف».
3. **الـAPK موقَّع بمفتاح debug** لأن المفتاح الخاص لا يُرفع للمستودع؛ يكفي للتثبيت
   والاختبار، ويصبح توقيعًا رسميًا بإضافة أسرار `ANDROID_KEYSTORE_BASE64`
   و`ANDROID_KEY_ALIAS` و`ANDROID_KEY_PASSWORD` و`ANDROID_STORE_PASSWORD`.
4. لم يُختبر التطبيق على جهاز Android/Windows حقيقي من هذه البيئة (لا تتوفر أجهزة)؛
   التحقق جرى عبر اختبارات الواجهة (widget tests) وبناء الحزم وتثبيتها صامتًا.
