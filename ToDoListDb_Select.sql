-- Параметры uuid соответствуют Guid; значения 0/1 - ToDoItemState.

PREPARE "GetAllByUserId" (uuid) AS
SELECT "Id", "UserId", "ListId", "Name", "CreatedAt", "State", "StateChangedAt", "Deadline"
FROM "public"."ToDoItem"
WHERE "UserId" = $1
ORDER BY "CreatedAt", "Id";

PREPARE "GetActiveByUserId" (uuid) AS
SELECT "Id", "UserId", "ListId", "Name", "CreatedAt", "State", "StateChangedAt", "Deadline"
FROM "public"."ToDoItem"
WHERE "UserId" = $1 AND "State" = 0
ORDER BY "CreatedAt", "Id";

PREPARE "Get" (uuid) AS
SELECT "Id", "UserId", "ListId", "Name", "CreatedAt", "State", "StateChangedAt", "Deadline"
FROM "public"."ToDoItem"
WHERE "Id" = $1;

PREPARE "ExistsByName" (uuid, text) AS
SELECT EXISTS
(
    SELECT 1 FROM "public"."ToDoItem"
    WHERE "UserId" = $1 AND "Name" = $2
) AS "ExistsByName";

PREPARE "CountActive" (uuid) AS
SELECT count(*)::integer AS "CountActive"
FROM "public"."ToDoItem"
WHERE "UserId" = $1 AND "State" = 0;

-- Find возвращает кандидатов пользователя; Func<ToDoItem, bool> применяется в C#.
PREPARE "Find" (uuid) AS
SELECT "Id", "UserId", "ListId", "Name", "CreatedAt", "State", "StateChangedAt", "Deadline"
FROM "public"."ToDoItem"
WHERE "UserId" = $1
ORDER BY "CreatedAt", "Id";

-- NULL во втором параметре означает только задачи без списка.
PREPARE "GetByUserIdAndList" (uuid, uuid) AS
SELECT "Id", "UserId", "ListId", "Name", "CreatedAt", "State", "StateChangedAt", "Deadline"
FROM "public"."ToDoItem"
WHERE "UserId" = $1 AND "ListId" IS NOT DISTINCT FROM $2
ORDER BY "CreatedAt", "Id";

PREPARE "GetCompletedByUserIdAndList" (uuid, uuid) AS
SELECT "Id", "UserId", "ListId", "Name", "CreatedAt", "State", "StateChangedAt", "Deadline"
FROM "public"."ToDoItem"
WHERE "UserId" = $1 AND "ListId" IS NOT DISTINCT FROM $2 AND "State" = 1
ORDER BY "CreatedAt", "Id";

-- Примеры выполнения на данных ToDoListDb_Insert.sql.
EXECUTE "GetAllByUserId" ('10000000-0000-0000-0000-000000000001');
EXECUTE "GetActiveByUserId" ('10000000-0000-0000-0000-000000000001');
EXECUTE "Get" ('30000000-0000-0000-0000-000000000002');
EXECUTE "ExistsByName" ('10000000-0000-0000-0000-000000000001', 'Купить книгу');
EXECUTE "CountActive" ('10000000-0000-0000-0000-000000000001');
EXECUTE "Find" ('10000000-0000-0000-0000-000000000001');
EXECUTE "GetByUserIdAndList" ('10000000-0000-0000-0000-000000000001', NULL);
EXECUTE "GetCompletedByUserIdAndList"
    ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001');

DEALLOCATE "GetAllByUserId";
DEALLOCATE "GetActiveByUserId";
DEALLOCATE "Get";
DEALLOCATE "ExistsByName";
DEALLOCATE "CountActive";
DEALLOCATE "Find";
DEALLOCATE "GetByUserIdAndList";
DEALLOCATE "GetCompletedByUserIdAndList";
