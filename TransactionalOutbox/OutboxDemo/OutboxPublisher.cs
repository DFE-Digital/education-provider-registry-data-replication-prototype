using Npgsql;

namespace OutboxDemo;

public class OutboxPublisher(Settings settings)
{
    public async Task<int> Publish(CancellationToken ct)
    {
        await using var conn = await Database.Open(settings.SourceConnectionString, ct);
        var pending = new List<(Guid Id, string Payload)>();
        await using (var select = new NpgsqlCommand("SELECT id, payload::text FROM outbox.messages WHERE published_at IS NULL ORDER BY occurred_at, id LIMIT 100", conn))
        await using (var rows = await select.ExecuteReaderAsync(ct))
            while (await rows.ReadAsync(ct)) pending.Add((rows.GetGuid(0), rows.GetString(1)));
        if (pending.Count == 0) return 0;
        await using var client = ServiceBusConnection.CreateClient(settings);
        await using var sender = client.CreateSender(settings.Topic);
        foreach (var item in pending)
        {
            await sender.SendMessageAsync(ServiceBusConnection.CreateMessage(item.Id, item.Payload), ct);
            await using var mark = new NpgsqlCommand("UPDATE outbox.messages SET published_at = clock_timestamp() WHERE id = @id", conn);
            mark.Parameters.AddWithValue("id", item.Id);
            await mark.ExecuteNonQueryAsync(ct);
            Console.WriteLine($"Published {item.Id}.");
        }
        return pending.Count;
    }

    public async Task Replay(Guid id, CancellationToken ct)
    {
        await using var conn = await Database.Open(settings.SourceConnectionString, ct);
        await using var select = new NpgsqlCommand("SELECT payload::text FROM outbox.messages WHERE id = @id", conn);
        select.Parameters.AddWithValue("id", id);
        var payload = await select.ExecuteScalarAsync(ct) as string ?? throw new ArgumentException("Event not found.");
        await using var client = ServiceBusConnection.CreateClient(settings);
        await using var sender = client.CreateSender(settings.Topic);
        await sender.SendMessageAsync(ServiceBusConnection.CreateMessage(id, payload), ct);
        Console.WriteLine($"Replayed {id} with the same event ID.");
    }
}
