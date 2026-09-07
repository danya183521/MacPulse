# MacPulse

Нативный локальный системный монитор для macOS 14+, с приоритетом Apple Silicon. SwiftUI, AppKit, Charts, WidgetKit и системные API Apple; внешних библиотек и web runtime нет.

**Статус:** приложение собирается и запускается на MacBook Air M1. Реальные CPU/GPU/ANE, температуры, память, батарея, сеть и диск проверяются диагностическими программами из этого же проекта. Dashboard, настройки и компактная панель проверены через работающий интерфейс. Полная цель пока **не объявлена выполненной**: WidgetKit с общими данными требует Apple Development signing / App Group; на проверяемом Mac нет доступной signing identity. Детальная граница подтверждения — [CompletionAudit](Docs/CompletionAudit.md).

## Открыть и запустить

Открыть `MacPulse.xcodeproj`, выбрать схему **MacPulse**, конфигурацию **Debug**, назначение **My Mac**, нажать Run. Debug подписывается локально, без developer account. Приложение остаётся доступным в Menu Bar после закрытия Dashboard.

Из Terminal в корне проекта:

```sh
./Scripts/build.sh
open build/Build/Products/Debug/MacPulse.app
./Scripts/build.sh test
```

В этом окружении Xcode находится в `/Applications/work/Xcode.app`. Скрипт задаёт `DEVELOPER_DIR` только для своего процесса; глобальный `xcode-select` не меняется. Для другого расположения:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/build.sh
```

Минимум — macOS 14, Xcode с SDK macOS 14 или новее. Проверено с Xcode 26.6 / SDK 26.5 на macOS 26.5.1 arm64. Intel-компиляция предусмотрена Release, но аппаратные метрики Intel не проверены. Все отсутствующие значения отображаются как `—` / Unavailable.

## Интерфейсы

- **Menu Bar:** выбранные метрики в сохранённом порядке, моноширинные цифры, размер текста ограничен измеренной шириной; остальное обозначено `+N`. Выключение всех метрик оставляет значок.
- **Quick Panel:** клик по Menu Bar или Window → Show Quick Panel (`⇧⌘M` внутри приложения). Выбранные показатели и основные системные данные, переход в Dashboard и Settings.
- **Dashboard:** Overview, CPU, GPU, Memory, Thermals, Battery, Power, Network, Storage, System. Графики показывают историю текущего запуска.
- **Settings:** состав и порядок Menu Bar, интервал 1/2/5/10 секунд, System/Light/Dark, Launch at Login, предупреждения. Настройки сохраняются в UserDefaults.
- **Alerts:** выключены по умолчанию. При включении запрашивается разрешение macOS. Условие должно сохраняться 30 секунд; пауза между сообщениями одного типа — час, с сохранением между запусками. Условия: высокая температура CPU, критический memory pressure, низкий заряд без внешнего питания, мало свободного диска.

Launch at Login использует `SMAppService.mainApp`. Он не включается автоматически и может потребовать подтверждения в системных Login Items. Этот сценарий не проверялся фактическим входом в macOS: системные настройки без разрешения не менялись.

## Архитектура

```text
MPNativeSensors / MPNetworkCounters
            ↓  единая utility-очередь
       SensorWorker → Snapshot
            ↓  MainActor
       SamplingEngine
       ├── HistoryStore → Charts
       ├── StatusBarController → NSPopover / SwiftUI
       ├── Dashboard / Settings
       ├── AlertPolicy → UserNotifications
       └── отдельная очередь записи → WidgetSnapshot → App Group → WidgetKit
```

- `Sources/PrivateSensors`: Objective-C мост к Mach, IOKit и изолированным private ABI. Только чтение; освобождение CF/IOKit объектов; проверки размера, типа, диапазона и наличия символов.
- `Sources/Core`: каталог метрик, единицы и источники, снимки, ограниченная история, общий payload виджета.
- `Sources/MacPulse`: центральный sampling engine, отдельная политика предупреждений, настройки и SwiftUI/AppKit интерфейсы.
- `Sources/Widget`: отдельный sandboxed WidgetKit extension, размеры small/medium.
- `Tests`: XCTest для реального сборщика, сетевых переходов, форматирования unavailable, истории, настроек, предупреждений и нативного status item.
- `Scripts`: генератор Xcode-проекта без сторонних dependencies и воспроизводимые локальные проверки. Генератор не требуется для обычной сборки.

UI не читает датчики. Один `DispatchSourceTimer` работает на utility-очереди; статические данные, volumes и CoreWLAN обновляются раз в 15 samples. Sleep отменяет timer и сбрасывает дельты, wake запускает сбор заново. Закрытая компактная панель освобождает hosting controller. Файловая запись виджета вынесена с MainActor.

История держится только в памяти: максимум 900 снимков и 30 минут, что наступит раньше. При интервале 1 секунда это 15 минут; при 2 секундах — 30 минут. Графики ограничивают число отрисовываемых точек, сохраняя разрывы отсутствующих измерений. Старые точки удаляются; после quit история исчезает.

## Реальные источники данных

| Метрики | Источник и смысл |
|---|---|
| CPU общий / по логическим ядрам | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`: дельты user + system + nice относительно суммы с idle. Первый sample не показывает процент. |
| Типы кластеров | `hw.nperflevels` и `hw.perflevelN.name/physicalcpu`. Индексам Mach не приписываются неподтверждённые P/E метки. |
| Memory | `host_statistics64(HOST_VM_INFO64)`, `physicalMemory`. Used = active + inactive + speculative + wired + compressed − purgeable − file-backed, в байтах. Available = physical − used. Cached = purgeable + file-backed. |
| Swap, memory pressure | `sysctl vm.swapusage` и `kern.memorystatus_vm_pressure_level`. Pressure не выводится из процента занятой RAM. |
| CPU / GPU temperature, прочие sensors | Private IOHID temperature events: CPU — среднее именованных eACC/pACC sensors, GPU — среднее GPU MTR sensors. Дополнительно доступны SoC, PMU, NAND и другие именованные события. Проверяются диапазон 0…150°C и finite. |
| SMC temperature fallback | Read-only AppleSMC ABI, фиксированное соответствие ключей только для Apple M1. На этом Mac `Tp09` / `Tp0T` / `Tg05` возвращают SMC result 132 (key not found), поэтому используются реальные IOHID readings. |
| GPU utilization / memory | IOKit `IOAccelerator/PerformanceStatistics`: `Device Utilization %` и `In use system memory`. Это undocumented registry schema. |
| CPU / GPU / ANE power | Private `libIOReport`, energy deltas из **Energy Model** и **PMP**. mJ/uJ/nJ переводятся в джоули и делятся на реальное монотонное elapsed time. На этом M1 ANE находится в PMP. |
| CPU + GPU + ANE | Сумма только при наличии всех трёх каналов. Это не полная мощность Mac. |
| System / PHPC power | AppleSMC float keys `PSTR` и `PHPC`. PSTR имеет общепринятое соответствие system power, но не измеряет розетку. PHPC показывается под raw key, поскольку граница этого rail / package не документирована Apple. Обе метрики помечены experimental. |
| Battery charge / state | Предпочтительно публичный IOKit Power Sources API; AppleSmartBattery — fallback. |
| Battery details | AppleSmartBattery: cycles, AppleRawCurrentCapacity, AppleRawMaxCapacity, DesignCapacity; health = max/design; Temperature / 100, Voltage / 1000, InstantAmperage (fallback Amperage) / 1000. Power = V × A; отрицательное значение — разряд. Возраст battery-controller snapshot отображается отдельно. |
| Network | `sysctl IFMIB_IFDATA / IFDATA_GENERAL` / `if_data64` byte counters только основного интерфейса, выбранного через SystemConfiguration. Нет суммирования физического интерфейса с VPN. Смена маршрута, потеря интерфейса, сброс счётчиков и wake требуют новой базы. |
| Wi-Fi / IP | CoreWLAN signal/noise/transmit link; локальный IPv4 из `getifaddrs`. SSID может быть скрыт политикой macOS. Location permission не запрашивается. |
| Storage | Foundation volume total/available capacity для home/data volume. Used = total − available; purgeable space в free не добавляется. APFS shared volumes не суммируются. |
| Disk activity | IOKit IOBlockStorageDriver Statistics, дельты Bytes (Read)/(Write) всех физических дисков. Изменение набора устройств сбрасывает базу. |
| System | `sysctl`, `ProcessInfo`, локальный `gethostname` без DNS lookup; thermal state — `ProcessInfo.thermalState`. |

IOReport сообщает **модель энергопотребления**, а не лабораторно откалиброванные измерения. IOHID для неактивного GPU на этом M1 сообщает ровно 30°C; под реальной Metal-нагрузкой чтение поднялось примерно до 57°C. Такие hardware floors не заменяются и не «исправляются» выдуманными значениями.

## WidgetKit и signing

Обычный Debug собирает extension, но **не обращается к App Group без developer signing**. Виджет не содержит fake preview numbers: без общего снимка показывает состояние отсутствия данных. Настройки приложения сообщают о необходимости developer signing.

Для полноценной проверки нужна конфигурация **Signed Debug** и одна Apple Developer team для приложения и extension, с доступным сертификатом Apple Development и разрешённой группой `group.local.macpulse.shared`.

1. Добавить команду в Xcode → Settings → Accounts.
2. В обоих targets выбрать эту команду для Signed Debug / Automatic Signing и App Groups.
3. При необходимости выбрать уникальный group identifier одновременно в обоих entitlements и `WidgetSnapshot.group`.
4. Собрать и запустить Signed Debug. После появления двух samples дождаться записи shared snapshot.
5. Добавить MacPulse через системную галерею виджетов; проверить small/medium и реальный timestamp/данные.

Команда сборки после настройки team:

```sh
MACPULSE_CONFIGURATION='Signed Debug' ./Scripts/build.sh
```

Payload содержит только timestamp, CPU, memory, battery, CPU temperature. Приложение записывает его атомарно не чаще раза в минуту; просит WidgetKit обновиться не чаще раза в 15 минут. Extension читает общий файл, а не опрашивает сенсоры и не запускает независимую fake систему. Решение о времени обновления принимает macOS. Виджет показывает время снимка и помечает старые данные; это **не realtime Menu Bar**.

Нельзя обходить отсутствие signing через чужие группы, широкие sandbox exceptions или выдавать неподтверждённый extension за работающий. Подробнее: [Apple — App Group containers](https://developer.apple.com/documentation/xcode/accessing-app-group-containers), [WidgetKit refresh policy](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).

## Проверки и ограничения

- `./Scripts/build.sh test` — XCTest, в том числе actual sensor sampling и реальный NSStatusItem.
- `./Scripts/build-probes.sh` — компилирует локальные диагностические программы на тех же production collectors.
- `python3 Scripts/compare-network.py` — сверяет полные byte counters с двумя чтениями `netstat`.
- `python3 Scripts/compare-system.py` — сверяет memory/model/chip/battery/storage с `vm_stat`, `sysctl`, `pmset`, `df`.
- `python3 Scripts/runtime-load-check.py` — краткая CPU/Metal нагрузка и сопоставление датчиков до/во время/после.
- `python3 Scripts/network-check.py` — служебная загрузка и отправка нулевых байтов в Cloudflare speed test; **это опциональный тестовый скрипт, приложение никогда не делает этих запросов**.
- `Scripts/ane-load.swift` — опциональная Core ML нагрузка на локальной модели MobileNetV2FP16 из [официальной галереи Apple](https://developer.apple.com/machine-learning/models/). Модель, её cache и benchmark не входят в приложение и git.
- `python3 Scripts/measure-process.py` — 30-секундная выборка собственного CPU time/RSS.

Измеренные сравнения и границы достоверности находятся в [SensorVerification](Docs/SensorVerification.md), итог по каждому критерию — в [CompletionAudit](Docs/CompletionAudit.md). Полные локальные build/test логи лежат в `Evidence`; большие и потенциально персональные диагностические snapshots исключены из git.

Private ABI может измениться в обновлении macOS. Незнакомая модель, отсутствующий символ, ошибка подписки, неизвестная единица или отсутствующий sensor оставляют значение unavailable. Достоверность на других Apple Silicon не объявлена проверенной. Частота sampling не заставляет battery controller или WidgetKit обновляться чаще их собственного расписания.

Исходники для исследования ABI и семантики: [Apple XNU](https://github.com/apple-oss-distributions/xnu), [macmon low-level sources](https://github.com/vladkens/macmon/blob/main/src_lib/sources.rs), [macmon metrics](https://github.com/vladkens/macmon/blob/main/src_lib/metrics.rs), [Stats RAM reader](https://github.com/exelban/stats/blob/master/Modules/RAM/readers.swift), [Stats sensor keys](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift), [VirtualSMC sensor documentation](https://github.com/acidanthera/VirtualSMC/blob/master/Docs/SMCSensorKeys.txt). Эти проекты не подключены как dependencies.

Нет backend, accounts, telemetry, analytics, subprocess polling в production или отправки системных метрик наружу. Нет remote repository, push, публикации или изменений других проектов.
