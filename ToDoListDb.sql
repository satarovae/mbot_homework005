BEGIN;

CREATE TABLE "public"."ToDoUser"
(
    "UserId" uuid NOT NULL DEFAULT gen_random_uuid(),
    "TelegramUserId" bigint NOT NULL,
    "TelegramUserName" text NOT NULL DEFAULT '',
    "RegisteredAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "PK_ToDoUser" PRIMARY KEY ("UserId"),
    CONSTRAINT "CK_ToDoUser_TelegramUserId" CHECK ("TelegramUserId" > 0)
);

CREATE TABLE "public"."ToDoList"
(
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "UserId" uuid NOT NULL,
    "Name" text NOT NULL,
    "CreatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "PK_ToDoList" PRIMARY KEY ("Id"),
    CONSTRAINT "UQ_ToDoList_Id_UserId" UNIQUE ("Id", "UserId"),
    CONSTRAINT "CK_ToDoList_Name" CHECK (length(btrim("Name")) > 0),
    CONSTRAINT "FK_ToDoList_UserId" FOREIGN KEY ("UserId")
        REFERENCES "public"."ToDoUser" ("UserId") ON DELETE CASCADE
);

CREATE TABLE "public"."ToDoItem"
(
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "UserId" uuid NOT NULL,
    "ListId" uuid,
    "Name" text NOT NULL,
    "CreatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "State" integer NOT NULL DEFAULT 0,
    "StateChangedAt" timestamp with time zone,
    "Deadline" timestamp with time zone NOT NULL,
    CONSTRAINT "PK_ToDoItem" PRIMARY KEY ("Id"),
    CONSTRAINT "CK_ToDoItem_Name" CHECK (length(btrim("Name")) > 0),
    CONSTRAINT "CK_ToDoItem_State" CHECK ("State" IN (0, 1)),
    CONSTRAINT "CK_ToDoItem_StateChangedAt" CHECK
        (("StateChangedAt" IS NULL OR "StateChangedAt" >= "CreatedAt")
         AND ("State" <> 1 OR "StateChangedAt" IS NOT NULL)),
    CONSTRAINT "FK_ToDoItem_UserId" FOREIGN KEY ("UserId")
        REFERENCES "public"."ToDoUser" ("UserId") ON DELETE CASCADE,
    CONSTRAINT "FK_ToDoItem_ListId" FOREIGN KEY ("ListId")
        REFERENCES "public"."ToDoList" ("Id") ON DELETE SET NULL,
    -- Задача может ссылаться только на список своего пользователя.
    CONSTRAINT "FK_ToDoItem_ListId_UserId" FOREIGN KEY ("ListId", "UserId")
        REFERENCES "public"."ToDoList" ("Id", "UserId") ON DELETE SET NULL ("ListId")
);

CREATE UNIQUE INDEX "UX_ToDoUser_TelegramUserId"
    ON "public"."ToDoUser" ("TelegramUserId");

CREATE INDEX "IX_ToDoList_UserId"
    ON "public"."ToDoList" ("UserId");

CREATE INDEX "IX_ToDoItem_UserId"
    ON "public"."ToDoItem" ("UserId");

-- Начальный столбец ListId обслуживает и одиночный FK, и составной FK.
CREATE INDEX "IX_ToDoItem_ListId_UserId"
    ON "public"."ToDoItem" ("ListId", "UserId");

COMMIT;
