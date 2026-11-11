namespace ToDoList.Core.Entities;

public sealed record ToDoUser
{
    public Guid UserId { get; init; } = Guid.NewGuid();

    public long TelegramUserId { get; init; }

    public string TelegramUserName { get; init; } = string.Empty;

    public DateTime RegisteredAt { get; init; } = DateTime.UtcNow;
}
