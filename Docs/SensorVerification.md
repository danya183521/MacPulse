# Проверка датчиков — 7 сентября 2026

Машина: MacBookAir10,1, Apple M1, 8 логических ядер, 16 GiB RAM, macOS 26.5.1. Источники сравнения и результаты сохранены локально; это наблюдения на одной машине, а не обещание для всех Apple Silicon.

## Реальные нагрузки

Результат `Evidence/load-check.json` — средние по коротким временным окнам, параллельно работали другие приложения:

| Состояние | CPU | GPU | CPU °C | GPU °C | CPU W | GPU W | SMC PSTR W |
|---|---:|---:|---:|---:|---:|---:|---:|
| До нагрузки | 24.66% | 36.0% | 51.41 | 30.00 | 0.785 | 0.210 | 7.47 |
| Четыре CPU workers | 70.49% | 27.8% | 67.73 | 30.00 | 10.802 | 0.223 | 17.87 |
| После CPU | 31.86% | 25.5% | 62.16 | 30.00 | 1.536 | 0.190 | 7.45 |
| Metal compute | 22.96% | 90.2% | 55.19 | 56.66 | 0.561 | 5.209 | 10.53 |

Это подтверждает реакцию counters и temperature readings на соответствующую нагрузку. Абсолютную аппаратную калибровку этих private readings без внешнего измерительного прибора не заявляем. `powermetrics` отказал с `must be invoked as the superuser`; sudo не использовался.

Расширенный IOReport audit обнаружил `PMP / ANE / mJ`, пропущенный при первоначальной проверке только Energy Model. Collector обновлён и подписывается также на этот канал. Core ML с `.cpuAndNeuralEngine`, локальной MobileNetV2FP16 и пустым изображением выполнил 8996 predictions за короткую нагрузку. ANE вырос от 0 до **2.468 W**, затем вернулся к 0. Результат: `Evidence/ane-load-check.json`. На этом Mac ANE **доступен**; старое предположение о его отсутствии отменено.

## Системные сравнения

`Evidence/system-comparison.json` сопоставляет отдельно снятые показания:

- Model, chip, physical memory и число логических ядер совпали с `sysctl`.
- Battery percentage совпал с `pmset`; на машине реально наблюдались и discharge, и charging после подключения питания пользователем.
- Memory used после применения той же опубликованной VM page formula отличается от последовательного `vm_stat` примерно на 13.5 MB в исходной проверке, что объяснимо изменением памяти между вызовами. Это не сравнение с «PhysMem used» из `top`: у него иная семантика, включающая cache.
- Volume total совпал с `df` побайтно: 245107195904. Available менялся на несколько MB между последовательными вызовами. `df Used` отдельного APFS volume нельзя напрямую считать total-minus-free всего shared container.
- Capacity health — арифметическое raw max / design, не rounded health из System Settings. В начальном снимке: около 78%, 619 циклов.

## Сеть

`Evidence/network-check.json`: оба curl завершились с кодом 0 на итоговом IFMIB collector. Общий download интерфейса в этой сессии был уже 3.35 MB/s из-за других приложений, во время тестовой загрузки — 3.68 MB/s. Upload вырос с 27.5 KB/s до 782 KB/s. Это общий трафик интерфейса: нельзя приписать весь прирост одному curl.

`Evidence/network-counter-comparison.json`: приложение прочитало **13 576 361 930 received bytes**; значение находится между двумя независимыми чтениями `netstat`. Upload также попал между чтениями. Важно, что received уже превышает uint32: полнота 64-битного источника проверена фактически.

Используется публичный `sysctl IFMIB_IFDATA / IFDATA_GENERAL`. Первоначальный `NET_RT_IFLIST2` заменён: [Apple XNU rtsock.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/net/rtsock.c) явно выравнивает до 1024 и приводит bytes к uint32 для non-platform binaries. [IFMIB implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/net/if_mib.c) возвращает `if_data64`; на этом Mac он доступен без sudo и специальных entitlements. При отказе API значение будет unavailable.

`MPNetworkCounters` отдельно проверен runtime unit-тестом на смену interface, отсутствие interface, сброс, длинный перерыв и 64-битные значения за границей uint32. Физическое выключение Wi-Fi, изменение VPN и сон macOS не выполнялись без разрешения; такой тест не объявляется проведённым.

## Температуры и SMC

Самостоятельный IOHID probe вернул реальные именованные eACC/pACC/GPU/SoC/PMU/NAND readings. Отрицательные и вне диапазона значения исключаются. Отдельные одноимённые battery events объединяются по имени; UI не приписывает им неподтверждённые расположения.

SMC audit (`Evidence/smc-audit.txt`) подтвердил размер request struct 80 байт, успешный read-only open и реальные float значения `PSTR` / `PHPC`. Старые temperature keys Tp09/Tp0T/Tg05 вернули result 132, key not found. Поэтому температура берётся из IOHID, а не из нулевого fallback.

PSTR и PHPC отреагировали на нагрузку, однако границы rail/package не документированы Apple. В UI это experimental SMC power, а PHPC оставлен с raw key. Нельзя интерпретировать их как проверенное потребление из розетки.

## Собственные ресурсы

Финальная 30-секундная выборка Debug с открытым Dashboard, интервалом 2 секунды и растущей историей: **1.74 CPU seconds / 30.03 seconds = 5.80% одного ядра**, RSS 123.52 → 136.83 MiB. Это около 0.72% суммарной ёмкости восьми ядер. Результат в `Evidence/process-usage.json`; это короткий интервал, не длительный battery benchmark. Рост RSS за этот интервал сам по себе не доказывает ни утечку, ни её отсутствие; история ограничена 900 snapshots.

Отдельный `sample` показал physical footprint 56.8 MiB (peak 62.3 MiB); этот показатель отличается от RSS. Главный поток большую часть выборки ожидал события в штатном run loop. Background-only CPU/RSS остаётся неподтверждённым: канал CUA оборвался при переходе к детальной странице, поэтому закрытие окон и этот режим не подменялись предположением.
