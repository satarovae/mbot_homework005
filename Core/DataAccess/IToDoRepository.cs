using ToDoList.Core.Entities;

namespace ToDoList.Core.DataAccess;

public interface IToDoRepository
{
    Task<IReadOnlyList<ToDoItem>> GetAllByUserId(
        Guid userId, CancellationToken ct = default);

    Task<IReadOnlyList<ToDoItem>> GetActiveByUserId(
        Guid userId, CancellationToken ct = default);

    Task<ToDoItem?> Get(Guid id, CancellationToken ct = default);

    Task Add(ToDoItem item, CancellationToken ct = default);

    Task Update(ToDoItem item, CancellationToken ct = default);

    Task Delete(Guid id, CancellationToken ct = default);

    /// <summary>Checks the exact task name across all states for the specified user.</summary>
    Task<bool> ExistsByName(Guid userId, string name, CancellationToken ct = default);

    Task<int> CountActive(Guid userId, CancellationToken ct = default);

    /// <summary>
    /// Selects the user's tasks from storage, then applies the supplied predicate in C#.
    /// An arbitrary Func is not treated as a translatable SQL expression.
    /// </summary>
    Task<IReadOnlyList<ToDoItem>> Find(
        Guid userId, Func<ToDoItem, bool> predicate, CancellationToken ct = default);

    /// <summary>Returns all states in the specified list; null selects tasks without a list.</summary>
    Task<IReadOnlyList<ToDoItem>> GetByUserIdAndList(
        Guid userId, Guid? listId, CancellationToken ct = default);

    /// <summary>Returns completed tasks in the specified list; null selects tasks without a list.</summary>
    Task<IReadOnlyList<ToDoItem>> GetCompletedByUserIdAndList(
        Guid userId, Guid? listId, CancellationToken ct = default);
}
