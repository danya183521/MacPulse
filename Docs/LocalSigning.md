# Локальная подпись без платной программы

Проверено 7 сентября 2026. Цель — личный запуск на этом Mac. App Store, notarization и distribution не настраиваются.

## Факты

- Apple Account уже добавлен в Xcode; Personal Team доступна и выбрана для MacPulse и MacPulseWidget в Signed Debug.
- Оба targets используют одну DEVELOPMENT_TEAM, Automatic signing и Apple Development.
- Bundle identifiers сохранены: `local.macpulse.MacPulse`, `local.macpulse.MacPulse.Widget`.
- Debug и Release сохраняют ad-hoc signing и Local.entitlements. Работающий Debug executable не заменялся.
- Signed Debug использует `group.local.macpulse.shared` в обоих entitlements; у widget включён sandbox. Debug не включает общий контейнер.
- `security find-identity -v -p codesigning`: **0 valid identities**.
- Manage Certificates в Xcode показывает два сертификата **Missing Private Key**. Они не удалялись и не отзывались.
- `security find-certificate` подтверждает оба сертификата в `login.keychain-db`; `security find-key -t private` находит только один посторонний ключ. Его application label не совпадает с public-key identifiers обоих Apple Development certificates. В `System.keychain` пар также нет. Keychain Access открыть удалось, но чтение окна прервалось системной ошибкой захвата; вывод CLI достаточен и не раскрывает ключевой материал.
- Read-only SecKeychainGetStatus: default keychain доступна для чтения/записи и разблокирована.
- Автоматическая Signed Debug сборка с `-allowProvisioningUpdates` завершилась exit 65. Оба targets сообщают `The user name or passphrase you entered is not correct.` и отсутствие Mac App Development profiles. Локальный лог: `Evidence/personal-team-initial.log`.

Это доказывает отсутствие пригодной локальной signing identity и ошибку автоматической подготовки signing. Это **не доказывает**, что нужна платная программа, что пароль Apple ID неверен или что бесплатный WidgetKit невозможен.

## Почему нужен ручной отзыв

Xcode не создаёт третий Apple Development certificate: `You already have a current Development certificate or a pending certificate request.` Оба доступных сертификата уже заняли лимит Personal Team, а их приватные ключи отсутствуют локально. По документации Apple сертификат без приватного ключа нельзя использовать для подписи или восстановить скачиванием профиля; нужен приватный ключ с Mac, где он был создан, либо новый сертификат после освобождения слота.

Я не могу безопасно определить, используется ли сертификат `MacBook Air Max` на другом Mac. Поэтому для минимального действия рекомендую отозвать **`Untitled`** — он выглядит как оставшийся placeholder и также подтверждён как `Missing Private Key`. Если `Untitled` нужен на другом Mac, оставьте его и отзовите `MacBook Air Max` вместо него.

## Ручной шаг

На [Apple Developer Certificates](https://developer.apple.com/account/resources/certificates/list) войти в Personal Team, открыть сертификат `Untitled` и нажать **Revoke**. Это действие выполняет пользователь вручную. После отзыва вернуться в Xcode → Settings → Apple Accounts → Personal Team → Manage Certificates… → + → Apple Development. Если macOS запросит пароль, вводить его только в системном окне. Не присылать пароли или private keys в чат.

Если выбранный сертификат используется на другом Mac, отзыв лишит тот Mac возможности подписывать им; тогда сначала перенесите identity через защищённый `.p12`/developer profile или выберите второй сертификат.

## Продолжение

После появления identity проверить macOS App Group `<Team ID>.local.macpulse.shared`, синхронно задав её в entitlements и общем коде. Такой формат документирован Apple как не требующий provisioning profile. Bundle identifiers менять не требуется. Этот путь ещё не подтверждён runtime на данном Mac.

Затем собрать app и extension, добавить настоящий widget, проверить общий snapshot и реальные значения, выполнить tests и обновить CompletionAudit.

Источники Apple: [Personal Team](https://help.apple.com/xcode/mac/current/en.lproj/dev23aab79b4.html), [App Group без provisioning profile](https://developer.apple.com/documentation/xcode/accessing-app-group-containers). Бесплатная Personal Team и документированный формат группы ещё не означают успешную проверку WidgetKit.
