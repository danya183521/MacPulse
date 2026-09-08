# Mac Health Engine

Mac Health Engine — локальный детерминированный аналитический слой MacPulse. Он получает уже собранный `Snapshot` и текущий список процессов из существующего `SamplingEngine` и не создаёт отдельный hardware sampler, сеть, telemetry или AI/API.

## Архитектура

Поток данных:

```text
existing sensors → Snapshot + ProcessRecord[]
                 → MacHealthEngine
                 → category analyzers
                 → correlations / root causes / recommendations
                 → score + MacHealthSnapshot
                 → Overview, Health Detail, Menu Bar, alerts, history
```

Основные типы находятся в `Sources/Core/MacHealthEngine.swift`: `MacHealthSnapshot`, `HealthCategorySnapshot`, `HealthIssue`, `HealthEvidence`, `HealthRootCause`, `HealthRecommendation`, `HealthBaselineState` и `HealthTrend`. SwiftUI не содержит порогов и не принимает решений о severity.

## Категории и сигналы

- **Compute**: rolling CPU/GPU/ANE, duration, peak, process contribution и Energy Score.
- **Memory**: system Memory Pressure, swap, рост swap, compressed memory и крупнейшие memory consumers. RAM Used — только evidence и не является главным сигналом.
- **Thermals**: CPU/GPU/SoC/battery temperatures и системный `ProcessInfo.ThermalState`. Системное состояние macOS имеет приоритет над догадкой только по температуре.
- **Battery / Energy**: battery capacity health отдельно от текущего состояния, signed Battery Power, temperature, discharge baseline и energy processes.
- **Storage**: free bytes, free percent, disk activity и sustained I/O.

Каждая доступная категория имеет score 0–100, severity, status, evidence, trend и issues. При отсутствии датчика показывается `Unavailable`, а значение не заменяется нулём.

## Score и severity

Score не является средним значением категорий. Issues сортируются по severity, после чего penalties применяются с весами `1.0, 0.65, 0.4, 0.25, 0.15`; связанные вторичные сигналы поэтому уменьшают score, но не считаются полностью повторно. Категории без issues остаются 100.

Диапазоны overall: 90–100 `Excellent`, 75–89 `Normal`, 55–74 `Elevated Load`, 30–54 `High Load`, 0–29 `Critical`. Score и category scores сглаживаются, причём ухудшение применяется быстрее восстановления. Критические overrides ограничивают overall: critical memory ≤29, critical thermals ≤24, critical storage ≤34, critical compute ≤39, critical battery ≤44.

Mac Health Score описывает **текущее рабочее состояние системы**, а не физический износ или оставшийся срок службы Mac. Battery Health остаётся отдельной hardware-related метрикой.

## Duration, hysteresis и recovery

Потенциальные conditions хранятся по identity. CPU требует rolling average и 20 секунд; высокий CPU получает high severity после 60 секунд, critical — после 180 секунд. GPU требует 45 секунд, ANE и высокий discharge — 60 секунд, thermals — 45 секунд (serious/critical system state может сработать быстрее), disk I/O — 30 секунд, memory pressure — 15 секунд. Low storage — safety condition без warm-up delay.

Короткие spikes не создают issue. Recovery требует отдельного recovery threshold и 30 секунд подтверждённого нормального состояния. Пока issue восстанавливается, его duration и последний наблюдаемый root cause остаются стабильными; после debounce condition удаляется. Alerts используют ту же identity, cooldown 1 час и отдельное уведомление о recovery только для существенных issues.

## Adaptive baseline и warm-up

Baseline хранится компактно в `UserDefaults` (`macHealthBaseline.v1`) как mean, variance, sample count и даты. После ранних samples используется медленная EMA `α=0.02`; небезопасные samples и категории с активными issues не обучают baseline. Baseline готов только после минимум 30 samples и 120 секунд для четырёх метрик. До этого UI явно показывает `Learning / Изучение системы`, но абсолютные safety rules продолжают работать.

## Root cause, confidence и correlations

Process records группируются по отображаемому имени, поэтому несколько одноимённых helper workers не теряются. Выбирается крупнейший вклад для CPU, memory, energy или disk; process cause сохраняется на протяжении recovery. Формулировка зависит от confidence: `Primary cause`, `Largest memory consumer` или `Likely contributor`. Малый или недостаточный вклад не объявляется причиной.

Корреляции включают sustained compute + thermal state/temperature и compute + battery drain. В issue evidence остаются среднее, duration, peak, baseline deviation, process share и системный источник.

## Recommendations

Рекомендации только наблюдательные и обратимые: снизить вычислительную нагрузку, закрыть ненужные memory consumers, дать Mac остыть, освободить место, уменьшить disk activity или обратить внимание на energy process. Engine не завершает процессы, не меняет priority, не очищает RAM, не удаляет файлы и не меняет системные настройки.

## UI и localization

Overview содержит компактную кликабельную карточку Mac Health. Health Detail показывает hero score, issues, root cause/confidence, evidence, recommendations, независимые категории, explainability deductions и bounded Swift Charts history. Menu Bar имеет отдельный компактный блок и selectable metric `Health`; он не включается принудительно. Все новые строки добавлены в String Catalog для English и Russian, включая длинные русские рекомендации и disclaimer.

## Ограничения

- ANE utilization percentage и wall-power из розетки не объявляются доступными, если датчик этого не сообщает; показывается реальный ANE Power и источник.
- Root cause — вероятный вклад наблюдаемого процесса, а не доказательство единственной причины.
- Baseline и history текущей сессии ограничены; history — максимум 900 точек / 30 минут.
- WidgetKit signing и App Store не входят в эту задачу.
