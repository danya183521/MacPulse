# Completion audit

Полная цель: [Goal.md](Goal.md). **Цель пока не выполнена полностью.** Наличие build, исходного кода и unit tests не подменяет отсутствующую runtime-проверку WidgetKit.

Состояние на 7 сентября 2026 после финальных build/test и запуска Debug. Краткое подтверждение сборки: `Evidence/build-verification.json`.

| № | Критерий | Доказательство / состояние |
|---:|---|---|
| 1 | Настоящий Xcode project | MacPulse.xcodeproj; targets MacPulse, MacPulseWidget, MacPulseTests. Подтверждено сборкой. |
| 2 | Debug build | `Evidence/debug-build.log`, BUILD SUCCEEDED. Финальный `clean build` успешен; 9 tests / 0 failures. |
| 3 | Реальный запуск | Процесс MacPulse из build/Build/Products/Debug/MacPulse.app; работающий Dashboard наблюдался через CUA. |
| 4 | Menu Bar существует и обновляется | Нативный NSStatusItem; `testNativeStatusItemReceivesLiveSamples` проверил visibility, window width, реальные CPU readings и реакцию title на смену выбора. Панель была открыта через штатную команду ⇧⌘M. Прямой физический клик по самому пункту отдельно не зафиксирован. |
| 5 | Выбор и сохранение | Через Settings включена температура, изменён порядок; после quit/relaunch выбор и порядок сохранились. Unit test подтверждает также пустой выбор, интервал и тему. Overflow +N наблюдался в preview. |
| 6 | Menu Bar panel | Реальный NSPopover показал CPU/RAM/network/temperature/battery/power/GPU/storage; переход в Settings проверен. Последняя правка высоты и освобождения hosting controller требует повторной UI-проверки. |
| 7 | Dashboard | Overview, реальные значения и растущие графики проверены в Light/Dark; на финальной сборке AX повторно показал новые значения и увеличение истории с 3 до 11 samples. Все подробные страницы созданы; повторный последовательный UI-аудит прерван ошибкой CUA native pipe. Не считать все страницы отдельно проверенными. |
| 8 | Settings | Menu Bar controls, порядок, theme, General, persistence проверены. Launch at Login и доставка notifications не активировались без разрешения. |
| 9 | WidgetKit | Extension компилируется; payload round-trip на реальных данных прошёл. Personal Team назначена обоим targets, но `security find-identity -v -p codesigning` показывает 0 identities; оба сертификата в Xcode имеют Missing Private Key, а третий Xcode не создаёт. App Group и реальное отображение в WidgetKit не подтверждены. |
| 10 | Реальная CPU нагрузка | Native collector, XCTest, CPU workload 24.7% → 70.5%, изменение графика в Dashboard. |
| 11 | Реальная память | Mach collector; physical bytes совпадают с sysctl; used сверяется с vm_stat formula. |
| 12 | Реальная батарея | IOKit + pmset; percentage/state совпадают; charge и discharge наблюдались. Остальные values из реального registry. |
| 13 | Сетевой трафик | Реальные download/upload служебных данных, curl exit 0, counters выросли; Evidence/network-check.json. Итоговые 64-битные IFMIB counters также попали между независимыми чтениями netstat: Evidence/network-counter-comparison.json. |
| 14 | Storage | Foundation total/free сверены с df; физические read/write counters доступны. |
| 15 | System | sysctl model/chip/memory/core count совпали; OS и uptime читаются системно. |
| 16 | Temperature/GPU/Power | IOHID, IOAccelerator, IOReport Energy Model + PMP ANE, read-only AppleSMC. CPU/Metal/CoreML нагрузки проверены. PHPC mapping оставлен experimental; wall power не заявлен. |
| 17 | Нет fake production values | Missing = nil/—; тесты используют отдельные сценарии. Ни GPU 30°C floor, ни ANE 0 W не подставлены: получены от источника и меняются под нагрузкой. |
| 18 | История и Charts | Растущие реальные CPU/memory графики в UI, bounded history test. Остальные графики реализованы; все подробные страницы ещё не проверены через UI. |
| 19 | Unavailable / network state | Nil formatting, collector reset и synthetic interface transitions проверены runtime tests. Физическое отключение сети / sleep не проводилось. Нулевой ответ sensor не подменяется fake data. |
| 20 | Собственная нагрузка | Финальная Debug: 5.80% одного ядра (около 0.72% восьми ядер), RSS 123.52 → 136.83 MiB за 30 s. Physical footprint отдельной выборки 56.8 MiB. Background-only и длительный battery benchmark ещё не подтверждены. |
| 21 | Основные runtime-сценарии | Live sampling, реальные нагрузки, persistence, Overview, panel/settings и native status item проверены. Widget и полный проход детальных страниц остаются открытыми. |
| 22 | Документация | README: архитектура, все типы источников, private ABI, история, privacy, widgets, ограничения и команды. |
| 23 | Локальный git commit, clean, no remote | Локальный repository на main; рабочая версия закоммичена, финальный git status clean, remote отсутствует. Push не выполнялся. |
| 24 | Русская локализация | `Sources/Core/Localizable.xcstrings` подключён к app и WidgetKit extension; 226 ключей имеют русский перевод. Финальный clean build создал `en`/`ru` ресурсы в обоих bundles. Русский Overview, Menu Bar panel, Settings и Alerts с реальными данными подтверждены через AX; все detail-разделы покрыты каталогом и исходным UI-аудитом, но их последовательный runtime-переход не подтверждён из-за сбоя CUA native pipe. |

## Объективные внешние ограничения

1. **Developer signing:** Personal Team уже назначена обоим Signed Debug targets. `security find-identity -v -p codesigning` → 0 valid identities; `security find-certificate` и сравнение публичных отпечатков подтверждают оба Apple Development certificates без соответствующего private key. Xcode отклоняет создание третьего сертификата (`You already have a current Development certificate or a pending certificate request.`). Для выпуска новой пары нужно вручную отозвать один из двух сертификатов в Apple Developer Certificates; я не выполнял отзыв. Пароли/сертификаты не запрашиваются в чате. Бесплатный локальный WidgetKit остаётся технически возможным, но пока не проверен.
2. **CUA transport:** после успешных проверок Overview / panel / settings инструмент начал возвращать `Sky Computer Use native pipe closed before response`. После перезапуска финального приложения чтение Overview восстановилось, но на действии выбора CPU снова оборвался pipe. js_reset не помог. MacPulse продолжает работать; sample показывает обычный run loop, а не блокировку главного потока. Это ограничение проверки UI, а не доказательство неисправности приложения. Оно не обходится сторонней UI-автоматизацией.

## Следующие проверки после снятия ограничений

- Открыть каждый detail-раздел, 5/15/30-minute history, panel → Dashboard и panel → Settings, пустой и переполненный Menu Bar, финальные Light/Dark screenshots.
- Проверить два размера реального WidgetKit widget, timestamp, устаревание и обновление из App Group.
- Проверить background-only CPU/RSS на финальном executable.
- При разрешении пользователя — настоящий login registration, notification delivery, sleep/wake и физический network-state change; зафиксировать отдельно от unit tests.
- После исправлений повторить соответствующие build/test/runtime проверки и обновить этот аудит. Не отмечать goal complete при оставшихся неподтверждённых критериях.

## Local signing follow-up, 2026-09-07

The earlier missing-team diagnosis is superseded: Personal Team is now selected for both Signed Debug targets. Xcode shows two certificates with Missing Private Key, zero valid local identities, and an automatic signing error: `The user name or passphrase you entered is not correct.` Paid membership has NOT been established as necessary. Widget runtime remains unverified. See [LocalSigning.md](LocalSigning.md) for evidence and the manual certificate step.

## Localization follow-up, 2026-09-07

`Localizable.xcstrings` содержит английский исходный язык и русский перевод всех извлечённых пользовательских строк: Dashboard, detail pages, Menu Bar, Quick Panel, Settings, alerts, statuses, accessibility и WidgetKit. Форматирование чисел и дат использует `Locale.current`; технические обозначения и единицы сохраняются компактными. Смена языка выполняется через per-app language в системных настройках macOS, после чего приложение нужно перезапустить. Build и 9 XCTest прошли после подключения каталога.

## Processes follow-up, 2026-09-07

Добавлен отдельный раздел **Processes** с одним централизованным utility-sampler, который работает только пока открыт экран процессов и обновляется по умолчанию раз в 2 секунды. Список строится через `proc_listallpids`, `proc_pidinfo` (`PROC_PIDTBSDINFO` и `PROC_PIDTASKINFO`) и `proc_pid_rusage(RUSAGE_INFO_V4)`; `ps`/`top` не используются в production-коде.

- CPU считается по дельте user/system nanoseconds между снимками: 100% означает одно занятое логическое ядро, значения выше 100% допустимы.
- Память — `ri_phys_footprint`, с fallback на resident size из `proc_taskinfo`.
- Disk read/write — реальные дельты `ri_diskio_bytesread`/`ri_diskio_byteswritten` в байтах в секунду.
- Per-process network accounting явно помечен unavailable: публичного API для этих счётчиков нет, синтетические значения не показываются.
- Energy Score — прозрачный относительный MacPulse score из CPU, wakeups и disk activity; он не называется официальным Apple Energy Impact.
- UI поддерживает All/User Processes, поиск по имени и PID, сортировку по CPU/Memory/Energy/Network/Disk/Process, ограничение Top processes и detail panel с bundle/executable/parent PID/threads и историей CPU/Memory.
- Settings сохраняет интервал 1/2/5/10 секунд, Top processes 20/50/All и default scope системных процессов. Данные доступны только для чтения: kill/suspend/renice отсутствуют.
- Runtime на этом Mac показал 20 живых процессов с PID, реальным footprint и disk rates; контролируемая нагрузка `macpulse-process-load` (PID 72969) отображалась как 258 MB, Energy Score 10–11 и до 1.78 GB/s disk write. Английская и русская версии, поиск (4 совпадения для `MacPulse`), фильтр User/All и меню сортировки проверены через AX. Detail panel был открыт на `WidgetsExtension` и показал CPU, footprint, Energy Score, disk, PID, executable, parent PID, threads и CPU/Memory history. Опрос занимал 12.9–34.4 ms.
- Независимая сверка с `top` для самого приложения: PID 72705, RSS 80 MB, 1.7% one-core CPU в момент снимка; UI sampler продолжал обновляться. Отдельное измерение процесса MacPulse за 30 секунд показало 2.896% one-core CPU и 116.73 MiB RSS при закрытом Processes против 6.992% и 140.94 MiB при открытом Processes; данные сохранены в [Evidence/process-screen-usage.json](../Evidence/process-screen-usage.json). Полный XCTest: 11 tests, 0 failures.

Ограничение: при одновременном live-перестроении списка отдельные AX element ID могут устареть между снимками; координатный клик позволил завершить проверку detail panel. WidgetKit/signing к этому follow-up не относятся и намеренно не менялись.
