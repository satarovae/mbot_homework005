-- Проверки выполняются после ToDoListDb.sql и ToDoListDb_Insert.sql.
-- Изменения тестовых строк откатываются; исходный набор должен остаться неизменным.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL plpgsql.check_asserts = on;

DO $verify$
DECLARE
    user_one CONSTANT uuid := '10000000-0000-0000-0000-000000000001';
    user_two CONSTANT uuid := '10000000-0000-0000-0000-000000000002';
    list_one CONSTANT uuid := '20000000-0000-0000-0000-000000000001';
    list_other_owner CONSTANT uuid := '20000000-0000-0000-0000-000000000003';
    missing_user CONSTANT uuid := '90000000-0000-0000-0000-000000000999';
    missing_list CONSTANT uuid := '90000000-0000-0000-0000-000000000998';
    temporary_list CONSTANT uuid := '90000000-0000-0000-0000-000000000200';
    users_before jsonb;
    lists_before jsonb;
    items_before jsonb;
    second_user_before jsonb;
    second_lists_before jsonb;
    second_items_before jsonb;
    detached_ids uuid[];
    detached_expected jsonb;
    items_before_list_delete bigint;
    expected record;
    fk record;
    fk_count integer := 0;
    violated_constraint text;
    violated_column text;
BEGIN
    ASSERT current_setting('server_version_num')::integer >= 160000,
        'Требуется PostgreSQL 16 или новее';

    -- Набор и его владельцы проверяются до выполнения изменяющих операций.
    ASSERT (SELECT count(*) FROM "public"."ToDoUser") = 2,
        'Ожидалось 2 пользователя';
    ASSERT (SELECT count(*) FROM "public"."ToDoList") = 3,
        'Ожидалось 3 списка';
    ASSERT (SELECT count(*) FROM "public"."ToDoItem") = 9,
        'Ожидалось 9 задач';
    ASSERT (SELECT array_agg("UserId" ORDER BY "UserId") FROM "public"."ToDoUser")
        = ARRAY[user_one, user_two], 'Идентификаторы пользователей не соответствуют тестовому набору';
    ASSERT (SELECT "TelegramUserId" FROM "public"."ToDoUser" WHERE "UserId" = user_one) = 1000000001
        AND (SELECT "TelegramUserId" FROM "public"."ToDoUser" WHERE "UserId" = user_two) = 1000000002,
        'TelegramUserId не соответствуют тестовому набору';
    ASSERT (SELECT count(*) FROM "public"."ToDoList" WHERE "UserId" = user_one) = 2
        AND (SELECT count(*) FROM "public"."ToDoList" WHERE "UserId" = user_two) = 1,
        'Неверное распределение списков между владельцами';
    ASSERT (SELECT count(*) FROM "public"."ToDoItem" WHERE "UserId" = user_one) = 6
        AND (SELECT count(*) FROM "public"."ToDoItem" WHERE "UserId" = user_two) = 3,
        'Неверное распределение задач между владельцами';
    ASSERT (SELECT "UserId" FROM "public"."ToDoList" WHERE "Id" = list_one) = user_one
        AND (SELECT "UserId" FROM "public"."ToDoList" WHERE "Id" = list_other_owner) = user_two,
        'Списки для проверки связей отсутствуют или имеют другого владельца';

    SELECT jsonb_agg(to_jsonb(u) ORDER BY u."UserId") INTO users_before
        FROM "public"."ToDoUser" AS u;
    SELECT jsonb_agg(to_jsonb(l) ORDER BY l."Id") INTO lists_before
        FROM "public"."ToDoList" AS l;
    SELECT jsonb_agg(to_jsonb(i) ORDER BY i."Id") INTO items_before
        FROM "public"."ToDoItem" AS i;
    SELECT jsonb_agg(to_jsonb(u) ORDER BY u."UserId") INTO second_user_before
        FROM "public"."ToDoUser" AS u WHERE u."UserId" = user_two;
    SELECT jsonb_agg(to_jsonb(l) ORDER BY l."Id") INTO second_lists_before
        FROM "public"."ToDoList" AS l WHERE l."UserId" = user_two;
    SELECT jsonb_agg(to_jsonb(i) ORDER BY i."Id") INTO second_items_before
        FROM "public"."ToDoItem" AS i WHERE i."UserId" = user_two;

    -- Первичные ключи проверяются по столбцам, а не только по именам ограничений.
    FOR expected IN
        SELECT * FROM (VALUES
            ('public."ToDoUser"'::regclass, 'UserId'::text),
            ('public."ToDoList"'::regclass, 'Id'::text),
            ('public."ToDoItem"'::regclass, 'Id'::text)
        ) AS p(relation_id, column_name)
    LOOP
        ASSERT EXISTS (
            SELECT 1 FROM pg_catalog.pg_constraint AS c
            WHERE c.conrelid = expected.relation_id AND c.contype = 'p' AND c.convalidated
              AND c.conkey = ARRAY(
                  SELECT a.attnum FROM pg_catalog.pg_attribute AS a
                  WHERE a.attrelid = expected.relation_id
                    AND a.attname::text = expected.column_name AND NOT a.attisdropped
              )
        ), format('Не найден первичный ключ %s(%s)', expected.relation_id, expected.column_name);
    END LOOP;

    -- Проверяются направления связей, порядок столбцов и действия ON DELETE.
    FOR expected IN
        SELECT * FROM (VALUES
            ('public."ToDoList"'::regclass, 'public."ToDoUser"'::regclass,
                ARRAY['UserId']::text[], ARRAY['UserId']::text[], 'c'::text),
            ('public."ToDoItem"'::regclass, 'public."ToDoUser"'::regclass,
                ARRAY['UserId']::text[], ARRAY['UserId']::text[], 'c'::text),
            ('public."ToDoItem"'::regclass, 'public."ToDoList"'::regclass,
                ARRAY['ListId']::text[], ARRAY['Id']::text[], 'n'::text),
            ('public."ToDoItem"'::regclass, 'public."ToDoList"'::regclass,
                ARRAY['ListId', 'UserId']::text[], ARRAY['Id', 'UserId']::text[], 'n'::text)
        ) AS f(child_relation, parent_relation, child_columns, parent_columns, delete_action)
    LOOP
        ASSERT EXISTS (
            SELECT 1 FROM pg_catalog.pg_constraint AS c
            WHERE c.contype = 'f' AND c.convalidated
              AND c.conrelid = expected.child_relation AND c.confrelid = expected.parent_relation
              AND c.confdeltype::text = expected.delete_action
              AND c.conkey = ARRAY(
                  SELECT a.attnum FROM pg_catalog.pg_attribute AS a
                  WHERE a.attrelid = expected.child_relation
                    AND a.attname::text = ANY(expected.child_columns) AND NOT a.attisdropped
                  ORDER BY array_position(expected.child_columns, a.attname::text)
              )
              AND c.confkey = ARRAY(
                  SELECT a.attnum FROM pg_catalog.pg_attribute AS a
                  WHERE a.attrelid = expected.parent_relation
                    AND a.attname::text = ANY(expected.parent_columns) AND NOT a.attisdropped
                  ORDER BY array_position(expected.parent_columns, a.attname::text)
              )
        ), format('Не найден ожидаемый внешний ключ %s(%s) -> %s(%s)',
            expected.child_relation, expected.child_columns, expected.parent_relation, expected.parent_columns);
    END LOOP;

    ASSERT EXISTS (
        SELECT 1 FROM pg_catalog.pg_index AS ix
        WHERE ix.indrelid = 'public."ToDoUser"'::regclass
          AND ix.indisunique AND ix.indisvalid AND ix.indisready AND ix.indislive
          AND ix.indpred IS NULL AND ix.indnkeyatts = 1
          AND ARRAY(
              SELECT k.attnum FROM unnest(ix.indkey) WITH ORDINALITY AS k(attnum, position)
              WHERE k.position = 1
          ) = ARRAY(
              SELECT a.attnum FROM pg_catalog.pg_attribute AS a
              WHERE a.attrelid = 'public."ToDoUser"'::regclass AND a.attname = 'TelegramUserId'
          )
    ), 'Не найден полный уникальный индекс по TelegramUserId';

    -- Для каждого FK нужен пригодный полный индекс с его столбцами в начале ключа.
    -- INCLUDE-столбцы не считаются ключевыми, выражения и частичные индексы не подходят.
    FOR fk IN
        SELECT c.conrelid, c.conkey, c.conname
        FROM pg_catalog.pg_constraint AS c
        WHERE c.contype = 'f' AND c.conrelid IN (
            'public."ToDoUser"'::regclass,
            'public."ToDoList"'::regclass,
            'public."ToDoItem"'::regclass)
        ORDER BY c.conrelid, c.conname
    LOOP
        fk_count := fk_count + 1;
        ASSERT EXISTS (
            SELECT 1 FROM pg_catalog.pg_index AS ix
            WHERE ix.indrelid = fk.conrelid
              AND ix.indisvalid AND ix.indisready AND ix.indislive AND ix.indpred IS NULL
              AND ix.indnkeyatts >= cardinality(fk.conkey)
              AND ARRAY(
                  SELECT k.attnum FROM unnest(ix.indkey) WITH ORDINALITY AS k(attnum, position)
                  WHERE k.position <= cardinality(fk.conkey) ORDER BY k.position
              ) = fk.conkey
        ), format('Нет индекса с ведущими столбцами внешнего ключа %s', fk.conname);
    END LOOP;
    ASSERT fk_count >= 3, 'Должны присутствовать как минимум три обязательных внешних ключа';

    -- Ожидаемые ошибки перехватываются только по конкретному классу SQLSTATE.
    BEGIN
        INSERT INTO "public"."ToDoUser" ("UserId", "TelegramUserId")
        VALUES (user_one, 900000000001);
        RAISE EXCEPTION 'duplicateUserPK: повторный UserId принят';
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME;
        ASSERT violated_constraint = 'PK_ToDoUser', 'duplicateUserPK: нарушено другое ограничение';
    END;

    BEGIN
        INSERT INTO "public"."ToDoList" ("Id", "UserId", "Name")
        VALUES (list_one, user_two, 'Повторный идентификатор списка');
        RAISE EXCEPTION 'duplicateListPK: повторный Id списка принят';
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME;
        ASSERT violated_constraint = 'PK_ToDoList', 'duplicateListPK: нарушено другое ограничение';
    END;

    BEGIN
        INSERT INTO "public"."ToDoItem" ("Id", "UserId", "Name", "Deadline")
        VALUES ('30000000-0000-0000-0000-000000000001', user_two,
            'Повторный идентификатор задачи', '2026-11-20 18:00:00+00');
        RAISE EXCEPTION 'duplicateItemPK: повторный Id задачи принят';
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME;
        ASSERT violated_constraint = 'PK_ToDoItem', 'duplicateItemPK: нарушено другое ограничение';
    END;

    BEGIN
        INSERT INTO "public"."ToDoList" ("Id", "UserId", "Name")
        VALUES ('90000000-0000-0000-0000-000000000101', missing_user, 'Список без владельца');
        RAISE EXCEPTION 'orphanUserList: список с отсутствующим пользователем принят';
    EXCEPTION WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME;
        ASSERT violated_constraint = 'FK_ToDoList_UserId', 'orphanUserList: нарушено другое ограничение';
    END;

    BEGIN
        INSERT INTO "public"."ToDoItem" ("Id", "UserId", "Name", "Deadline")
        VALUES ('90000000-0000-0000-0000-000000000102', missing_user,
            'Задача без владельца', '2026-11-20 18:00:00+00');
        RAISE EXCEPTION 'orphanUserItem: задача с отсутствующим пользователем принята';
    EXCEPTION WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME;
        ASSERT violated_constraint = 'FK_ToDoItem_UserId', 'orphanUserItem: нарушено другое ограничение';
    END;

    BEGIN
        INSERT INTO "public"."ToDoItem" ("Id", "UserId", "ListId", "Name", "Deadline")
        VALUES ('90000000-0000-0000-0000-000000000103', user_one, missing_list,
            'Задача в отсутствующем списке', '2026-11-20 18:00:00+00');
        RAISE EXCEPTION 'orphanList: задача с отсутствующим списком принята';
    EXCEPTION WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME;
        ASSERT violated_constraint IN ('FK_ToDoItem_ListId', 'FK_ToDoItem_ListId_UserId'),
            'orphanList: нарушено другое ограничение';
    END;

    BEGIN
        INSERT INTO "public"."ToDoItem" ("Id", "UserId", "ListId", "Name", "Deadline")
        VALUES ('90000000-0000-0000-0000-000000000104', user_one, list_other_owner,
            'Задача в чужом списке', '2026-11-20 18:00:00+00');
        RAISE EXCEPTION 'crossOwnerList: задача в списке другого пользователя принята';
    EXCEPTION WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME;
        ASSERT violated_constraint = 'FK_ToDoItem_ListId_UserId',
            'crossOwnerList: нарушено другое ограничение';
    END;

    BEGIN
        INSERT INTO "public"."ToDoUser" ("UserId", "TelegramUserId")
        VALUES ('90000000-0000-0000-0000-000000000105', 1000000001);
        RAISE EXCEPTION 'duplicateTelegram: повторный TelegramUserId принят';
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME;
        ASSERT violated_constraint = 'UX_ToDoUser_TelegramUserId',
            'duplicateTelegram: нарушено другое ограничение';
    END;

    BEGIN
        INSERT INTO "public"."ToDoItem" ("Id", "UserId", "Name", "State", "Deadline")
        VALUES ('90000000-0000-0000-0000-000000000106', user_one,
            'Недопустимое состояние', 2, '2026-11-20 18:00:00+00');
        RAISE EXCEPTION 'invalidState: недопустимый State принят';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME;
        ASSERT violated_constraint = 'CK_ToDoItem_State', 'invalidState: нарушено другое ограничение';
    END;

    BEGIN
        INSERT INTO "public"."ToDoList" ("Id", "UserId", "Name")
        VALUES ('90000000-0000-0000-0000-000000000107', user_one, '   ');
        RAISE EXCEPTION 'emptyListName: пустое название списка принято';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME;
        ASSERT violated_constraint = 'CK_ToDoList_Name', 'emptyListName: нарушено другое ограничение';
    END;

    BEGIN
        INSERT INTO "public"."ToDoItem" ("Id", "UserId", "Name", "Deadline")
        VALUES ('90000000-0000-0000-0000-000000000108', user_one, '', '2026-11-20 18:00:00+00');
        RAISE EXCEPTION 'emptyItemName: пустое название задачи принято';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME;
        ASSERT violated_constraint = 'CK_ToDoItem_Name', 'emptyItemName: нарушено другое ограничение';
    END;

    BEGIN
        INSERT INTO "public"."ToDoItem" ("Id", "UserId", "Name", "Deadline")
        VALUES ('90000000-0000-0000-0000-000000000109', user_one, 'Задача без срока', NULL);
        RAISE EXCEPTION 'nullDeadline: NULL в Deadline принят';
    EXCEPTION WHEN not_null_violation THEN
        GET STACKED DIAGNOSTICS violated_column = COLUMN_NAME;
        ASSERT violated_column = 'Deadline', 'nullDeadline: NULL обнаружен в другом столбце';
    END;

    BEGIN
        INSERT INTO "public"."ToDoItem"
            ("Id", "UserId", "Name", "CreatedAt", "State", "StateChangedAt", "Deadline")
        VALUES ('90000000-0000-0000-0000-000000000110', user_one,
            'Выполненная задача без даты', '2026-11-05 10:00:00+00', 1, NULL, '2026-11-20 18:00:00+00');
        RAISE EXCEPTION 'completedWithoutStateChangedAt: выполнение без даты принято';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME;
        ASSERT violated_constraint = 'CK_ToDoItem_StateChangedAt',
            'completedWithoutStateChangedAt: нарушено другое ограничение';
    END;

    BEGIN
        INSERT INTO "public"."ToDoItem"
            ("Id", "UserId", "Name", "CreatedAt", "State", "StateChangedAt", "Deadline")
        VALUES ('90000000-0000-0000-0000-000000000111', user_one,
            'Смена состояния до создания', '2026-11-05 10:00:00+00', 0,
            '2026-11-04 10:00:00+00', '2026-11-20 18:00:00+00');
        RAISE EXCEPTION 'stateChangedBeforeCreated: дата до CreatedAt принята';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME;
        ASSERT violated_constraint = 'CK_ToDoItem_StateChangedAt',
            'stateChangedBeforeCreated: нарушено другое ограничение';
    END;

    -- Вложенная под-транзакция позволяет проверить удаления и сравнить восстановленный набор.
    BEGIN
        INSERT INTO "public"."ToDoList" ("Id", "UserId", "Name", "CreatedAt")
        VALUES (temporary_list, user_one, 'Список для проверки каскада', '2026-11-05 09:00:00+00');
        INSERT INTO "public"."ToDoItem"
            ("Id", "UserId", "ListId", "Name", "CreatedAt", "State", "StateChangedAt", "Deadline")
        VALUES
            ('90000000-0000-0000-0000-000000000201', user_one, NULL,
                'Активная без списка', '2026-11-05 10:00:00+00', 0, NULL, '2026-11-20 18:00:00+00'),
            ('90000000-0000-0000-0000-000000000202', user_one, NULL,
                'Активная с датой смены состояния', '2026-11-05 10:00:00+00', 0,
                '2026-11-06 10:00:00+00', '2026-11-20 18:00:00+00'),
            ('90000000-0000-0000-0000-000000000203', user_one, temporary_list,
                'Выполненная в списке', '2026-11-05 10:00:00+00', 1,
                '2026-11-06 10:00:00+00', '2026-11-20 18:00:00+00');

        ASSERT EXISTS (SELECT 1 FROM "public"."ToDoItem"
            WHERE "Id" = '90000000-0000-0000-0000-000000000201'
              AND "UserId" = user_one AND "ListId" IS NULL
              AND "State" = 0 AND "StateChangedAt" IS NULL),
            'Допустимая активная задача без списка не сохранена';
        ASSERT EXISTS (SELECT 1 FROM "public"."ToDoItem"
            WHERE "Id" = '90000000-0000-0000-0000-000000000202'
              AND "UserId" = user_one AND "ListId" IS NULL AND "State" = 0
              AND "StateChangedAt" = '2026-11-06 10:00:00+00'::timestamptz),
            'Active с датой смены состояния должен быть допустим';
        ASSERT EXISTS (SELECT 1 FROM "public"."ToDoItem"
            WHERE "Id" = '90000000-0000-0000-0000-000000000203'
              AND "UserId" = user_one AND "ListId" = temporary_list AND "State" = 1
              AND "StateChangedAt" >= "CreatedAt"),
            'Completed с корректной датой должен быть допустим';

        SELECT array_agg(i."Id" ORDER BY i."Id"),
            jsonb_agg(jsonb_set(to_jsonb(i), '{ListId}', 'null'::jsonb) ORDER BY i."Id")
        INTO detached_ids, detached_expected
        FROM "public"."ToDoItem" AS i WHERE i."ListId" = list_one;
        ASSERT cardinality(detached_ids) = 2, 'Для удаления списка ожидалось две связанные задачи';
        SELECT count(*) INTO items_before_list_delete FROM "public"."ToDoItem";

        DELETE FROM "public"."ToDoList" WHERE "Id" = list_one;
        ASSERT NOT EXISTS (SELECT 1 FROM "public"."ToDoList" WHERE "Id" = list_one),
            'Список не удалён';
        ASSERT (SELECT count(*) FROM "public"."ToDoItem") = items_before_list_delete,
            'Удаление списка не должно удалять задачи';
        ASSERT (SELECT jsonb_agg(to_jsonb(i) ORDER BY i."Id")
            FROM "public"."ToDoItem" AS i WHERE i."Id" = ANY(detached_ids)) = detached_expected,
            'После удаления списка должен измениться только ListId; UserId и остальные поля сохраняются';

        DELETE FROM "public"."ToDoUser" WHERE "UserId" = user_one;
        ASSERT NOT EXISTS (SELECT 1 FROM "public"."ToDoUser" WHERE "UserId" = user_one),
            'Тестовый пользователь не удалён';
        ASSERT NOT EXISTS (SELECT 1 FROM "public"."ToDoList" WHERE "UserId" = user_one),
            'Списки удалённого пользователя не удалены каскадно';
        ASSERT NOT EXISTS (SELECT 1 FROM "public"."ToDoItem" WHERE "UserId" = user_one),
            'Задачи удалённого пользователя не удалены каскадно';
        ASSERT (SELECT count(*) FROM "public"."ToDoUser") = 1
            AND (SELECT count(*) FROM "public"."ToDoList") = 1
            AND (SELECT count(*) FROM "public"."ToDoItem") = 3,
            'После каскада должны остаться только данные второго пользователя';
        ASSERT (SELECT jsonb_agg(to_jsonb(u) ORDER BY u."UserId")
            FROM "public"."ToDoUser" AS u) = second_user_before,
            'При каскаде изменены данные второго пользователя';
        ASSERT (SELECT jsonb_agg(to_jsonb(l) ORDER BY l."Id")
            FROM "public"."ToDoList" AS l) = second_lists_before,
            'При каскаде изменены списки второго пользователя';
        ASSERT (SELECT jsonb_agg(to_jsonb(i) ORDER BY i."Id")
            FROM "public"."ToDoItem" AS i) = second_items_before,
            'При каскаде изменены задачи второго пользователя';

        -- Сигнал откатывает только проверочные вставки и удаления во вложенном блоке.
        RAISE SQLSTATE 'ZX001' USING MESSAGE = 'Откат проверочных изменений';
    EXCEPTION WHEN SQLSTATE 'ZX001' THEN
        NULL;
    END;

    -- Сравниваются все поля всех исходных строк, а не только количество объектов.
    ASSERT (SELECT jsonb_agg(to_jsonb(u) ORDER BY u."UserId") FROM "public"."ToDoUser" AS u) = users_before,
        'Исходный набор пользователей изменился';
    ASSERT (SELECT jsonb_agg(to_jsonb(l) ORDER BY l."Id") FROM "public"."ToDoList" AS l) = lists_before,
        'Исходный набор списков изменился';
    ASSERT (SELECT jsonb_agg(to_jsonb(i) ORDER BY i."Id") FROM "public"."ToDoItem" AS i) = items_before,
        'Исходный набор задач изменился';
    ASSERT (SELECT count(*) FROM "public"."ToDoUser") = 2
        AND (SELECT count(*) FROM "public"."ToDoList") = 3
        AND (SELECT count(*) FROM "public"."ToDoItem") = 9,
        'После проверок должен сохраниться набор 2/3/9';

    RAISE NOTICE 'Проверены ограничения, индексы и правила удаления. Исходный набор 2/3/9 сохранён.';
END;
$verify$ LANGUAGE plpgsql;

ROLLBACK;
