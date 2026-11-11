namespace ToDoList.Core.Entities;

public sealed record ToDoItem
{
    public Guid Id { get; init; } = Guid.NewGuid();

    public required ToDoUser User { get; init; }

    public Guid UserId => User.UserId;

    public ToDoList? List { get; init; }

    public Guid? ListId => List?.Id;

    public required string Name { get; init; }

    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;

    public ToDoItemState State { get; init; } = ToDoItemState.Active;

    /// <summary>UTC time of the last state transition; null until the first transition.</summary>
    public DateTime? StateChangedAt { get; init; }

    /// <summary>The required task deadline, supplied in UTC.</summary>
    public required DateTime Deadline { get; init; }
}
