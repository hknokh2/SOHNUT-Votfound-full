# Решение по задаче: WhatsApp External Template + video header из Salesforce Files

## Ключевой вывод
На текущий момент в Salesforce Messaging Components (формат **External Template** для WhatsApp) нет подтвержденного OOTB-механизма, который позволяет в UI компонента выбрать видео напрямую из **Salesforce Files / Asset Library** и подставить его как **media header** шаблона WhatsApp при отправке.

Иными словами, требование "video header именно из Salesforce Files без кода" с высокой вероятностью **не реализуется OOTB**.

## Рабочие варианты

### Вариант 1 (рекомендуемый OOTB-компромисс, без кода)
1. В Meta оставить approved template `video_test` (или аналог), где медиа согласовано в Meta-процессе.
2. В Salesforce отправлять этот External Template как есть.
3. Если нужен контент из Salesforce, использовать:
   - image header (если поддерживается в текущей связке),
   - текст/кнопку с публичной ссылкой на видео (из CDN/хранилища, не private Salesforce File URL).
4. Проверить opt-in и 24h/marketing policy, чтобы отправка не блокировалась.

Плюсы: быстро, без разработки.  
Минусы: видео не выбирается как header из Files в интерфейсе Salesforce.

### Вариант 2 (полное выполнение требования, но с разработкой)
Реализовать кастомную интеграцию через WhatsApp/Meta API:
1. Загружать видео (source из Salesforce Files/Asset) во внешний media endpoint.
2. Получать `media_id`.
3. Отправлять template message с header media через API, подставляя `media_id`.
4. Логировать message status и ошибки обратно в Salesforce.

Плюсы: соответствует целевому сценарию с video header.  
Минусы: не OOTB, нужна разработка, безопасность, хранение токенов, поддержка.

## Почему у Rael "застревает" отправка
По данным из org, есть типовые причины, когда отправка выглядит "зависшей", но фактически завершается ошибкой:
- `ApprovedExternalTemplateRequired`
- `EndUserIsNotOptedIn`

Что проверить:
1. Template действительно approved и синхронизирован в Salesforce.
2. У получателя корректный opt-in для канала WhatsApp.
3. Отправка идет в допустимом окне и с корректной категорией шаблона.
4. Канал/номер/маршрутизация активны и связаны с нужным deployment.
5. Состояние смотреть в Enhanced Messaging Log и в записях send request/status, а не только в UI composer.

## Практический план проверки (без деплоя в org)
1. Проверить настройки Messaging Channel, WhatsApp Sender, consent/opt-in политику.
2. Проверить, что компонент `Test video` активирован и доступен агенту в нужном routing context.
3. В тестовой сессии отправить template на номер с подтвержденным opt-in.
4. Сверить статусы/коды ошибок в логах.
5. Зафиксировать, что выбор video из Salesforce Files в External Template UI отсутствует (как product limitation).

## Итог
- Если нужен строго OOTB путь: использовать approved template и альтернативу со ссылкой/изображением.
- Если нужен именно **video header из Salesforce Files**: требуется кастомная интеграция (не OOTB).
