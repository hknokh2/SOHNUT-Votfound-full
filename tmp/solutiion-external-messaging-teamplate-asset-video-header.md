# Решение по проблеме WhatsApp External Template + video header из Salesforce Files

## Краткий вывод
- В текущем варианте OOTB сценарий «подставить видео из Salesforce Files/Asset Library как media header в WhatsApp External Template и отправить из Messaging Session» выглядит неподдерживаемым.
- Рабочий OOTB путь есть, но с компромиссом: header = изображение из `ContentAsset`, видео = ссылка в body/button.
- Полное соответствие критерию (именно video header из SF Files) вероятнее всего требует кастомной интеграции с Meta API.

## Что установлено по org (`SOHNUT-votfound`)
- `Test_video` сейчас фактически только с `Text` форматом, без `ExternalTemplate`.
- В рабочих external template-компонентах используется `HeaderTemplateSection` + `ImageReferenceValue` + `ContentAsset` (изображение).
- Реальные отправки фиксируют ошибки `ApprovedExternalTemplateRequired` и `EndUserIsNotOptedIn`; это не “зависание”, а завершенная отправка с ошибкой.
- Ошибка `ApprovedExternalTemplateRequired` обычно возникает, когда отправляют definition без валидного approved external template.
- В org есть MP4 как `ContentAsset`, но подтверждения OOTB-подстановки такого MP4 в header external template не найдено.

## Предложенные варианты

### Вариант 1 (рекомендуемый OOTB, без кода)
- Использовать `ExternalTemplate` с image header из `ContentAsset`.
- Видео передавать ссылкой (URL-кнопка или ссылка в body).
- Проверить, что компонент активирован, и отправка идет именно через этот message definition.

### Вариант 2 (OOTB-проверка гипотезы)
- Сделать отдельный тестовый external template-компонент и попробовать передать header-параметр как `RecordId`/`ContentAsset` для видео.
- Вероятность низкая, но это единственный no-code путь проверить до конца.

### Вариант 3 (если нужен именно video header из Salesforce файла)
- Кастомный путь: загрузка файла в Meta media endpoint и отправка template через WhatsApp Cloud API с video header параметром.
- Запускать из Salesforce (Flow/Apex action), но без деплоя в production до согласования.

## Почему у Rael “застревает” отправка
- На уровне данных это обычно `ConvMessageSendRequest` со статусом `Completed`, но с `FailedMessageErrorReasons`, а не зависшая операция.
- В этом org уже встречаются:
  - `ApprovedExternalTemplateRequired`
  - `EndUserIsNotOptedIn`

## Чек-лист для настройки без разработки
1. Убедиться, что message definition имеет `ExternalTemplate` формат и связан с approved шаблоном в Meta.
2. Активировать messaging component.
3. Проверить, что для конкретного получателя выполнен opt-in.
4. Проверить отправку из Messaging Session и сразу смотреть ошибки в `ConvMessageSendRequest`.
5. Если нужен именно video header из SF Files — эскалация в вариант 3 (кастом).

## Полезные ссылки
- Salesforce: Send Conversation Messages (Action API)  
  https://developer.salesforce.com/docs/atlas.en-us.api_action.meta/api_action/actions_obj_messaging_send_conversation_messages.htm
- Salesforce metadata typings (`ConversationMessageValueType`, `ConversationMessageConstantValueType`)  
  https://unpkg.com/@salesforce/types/lib/metadata.d.ts
- Meta WhatsApp template sending  
  https://developers.facebook.com/docs/whatsapp/cloud-api/guides/send-message-templates
