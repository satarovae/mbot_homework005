namespace ToDoList.Core.Entities;

public sealed record ToDoList
{
    public Guid Id { get; init; } = Guid.NewGuid();

    public required string Name { get; init; }

    public required ToDoUser User { get; init; }

    public Guid UserId => User.UserId;

    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;
}
