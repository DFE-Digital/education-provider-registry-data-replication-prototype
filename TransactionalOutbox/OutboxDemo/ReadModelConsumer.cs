using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Npgsql;

namespace OutboxDemo;

public class ReadModelConsumer(Settings settings)
{
    public async Task<int> Consume(int waitSeconds, CancellationToken ct)
    {
        await using var client = ServiceBusConnection.CreateClient(settings);
        await using var receiver = client.CreateReceiver(settings.Topic, settings.Subscription,
            new ServiceBusReceiverOptions { ReceiveMode = ServiceBusReceiveMode.PeekLock });
        var message = await receiver.ReceiveMessageAsync(TimeSpan.FromSeconds(waitSeconds), ct);
        if (message is null) return 0;
        // Errors leave the message uncompleted. It becomes available after its lock expires.
        var change = JsonSerializer.Deserialize<EstablishmentChanged>(message.Body.ToString())
            ?? throw new InvalidOperationException("Empty event.");
        if (change.EventId == Guid.Empty || message.MessageId != change.EventId.ToString() ||
            change.Urn <= 0 || change.Version <= 0 || string.IsNullOrWhiteSpace(change.Name) ||
            string.IsNullOrWhiteSpace(change.LocalAuthorityName))
            throw new InvalidOperationException("Invalid event.");
        await Apply(change, ct);
        // Acknowledge only after the database transaction commits.
        await receiver.CompleteMessageAsync(message, ct);
        return 1;
    }

    async Task Apply(EstablishmentChanged change, CancellationToken ct)
    {
        await using var conn = await Database.Open(settings.ReadConnectionString, ct);
        await using var tx = await conn.BeginTransactionAsync(ct);
        await using var inbox = new NpgsqlCommand("INSERT INTO inbox.processed_messages(message_id) VALUES (@id) ON CONFLICT DO NOTHING", conn, tx);
        inbox.Parameters.AddWithValue("id", change.EventId);
        if (await inbox.ExecuteNonQueryAsync(ct) == 0)
        {
            await tx.CommitAsync(ct);
            Console.WriteLine($"Duplicate ignored: {change.EventId}.");
            return;
        }
        await using var upsert = new NpgsqlCommand("""
            INSERT INTO read_model.establishment (urn, name, local_authority_name, display_name, version)
            VALUES (@urn, @name, @authority, @display, @version)
            ON CONFLICT (urn) DO UPDATE SET
                name = EXCLUDED.name, local_authority_name = EXCLUDED.local_authority_name,
                display_name = EXCLUDED.display_name, version = EXCLUDED.version, updated_at = clock_timestamp()
            WHERE EXCLUDED.version > read_model.establishment.version
            """, conn, tx);
        upsert.Parameters.AddWithValue("urn", change.Urn);
        upsert.Parameters.AddWithValue("name", change.Name);
        upsert.Parameters.AddWithValue("authority", change.LocalAuthorityName);
        upsert.Parameters.AddWithValue("display", $"{change.Name} ({change.LocalAuthorityName})");
        upsert.Parameters.AddWithValue("version", change.Version);
        var updated = await upsert.ExecuteNonQueryAsync(ct);
        await tx.CommitAsync(ct);
        Console.WriteLine($"{(updated == 1 ? "Applied" : "Older version ignored")}: {change.EventId}, URN {change.Urn}, version {change.Version}.");
    }
}
