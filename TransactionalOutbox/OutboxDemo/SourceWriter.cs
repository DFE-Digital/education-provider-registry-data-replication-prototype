using System.Text.Json;
using Npgsql;
using NpgsqlTypes;

namespace OutboxDemo;

public class SourceWriter(Settings settings)
{
    public async Task<Guid> Write(int urn, string name, bool rollback, CancellationToken ct)
    {
        if (urn <= 0 || string.IsNullOrWhiteSpace(name)) throw new ArgumentException("A positive URN and nonempty name are required.");
        await using var conn = await Database.Open(settings.SourceConnectionString, ct);
        await using var tx = await conn.BeginTransactionAsync(ct);
        await using var write = new NpgsqlCommand("""
            INSERT INTO core.establishment (urn, name, local_authority_id, version)
            VALUES (@urn, @name, 1, 1)
            ON CONFLICT (urn) DO UPDATE
            SET name = EXCLUDED.name, version = core.establishment.version + 1
            RETURNING version;
            """, conn, tx);
        write.Parameters.AddWithValue("urn", urn);
        write.Parameters.AddWithValue("name", name);
        var version = (long)(await write.ExecuteScalarAsync(ct))!;
        await using var authority = new NpgsqlCommand("SELECT name FROM core.local_authority WHERE id = 1", conn, tx);
        var authorityName = (string)(await authority.ExecuteScalarAsync(ct))!;
        var change = new EstablishmentChanged(Guid.NewGuid(), urn, name, authorityName, version);
        await using var insert = new NpgsqlCommand("""
            INSERT INTO outbox.messages (id, aggregate_id, aggregate_version, payload)
            VALUES (@id, @urn, @version, @payload)
            """, conn, tx);
        insert.Parameters.AddWithValue("id", change.EventId);
        insert.Parameters.AddWithValue("urn", urn);
        insert.Parameters.AddWithValue("version", version);
        insert.Parameters.AddWithValue("payload", NpgsqlDbType.Jsonb, JsonSerializer.Serialize(change));
        await insert.ExecuteNonQueryAsync(ct);
        if (rollback)
        {
            await tx.RollbackAsync(ct);
            Console.WriteLine($"Rolled back source write AND event {change.EventId}.");
        }
        else
        {
            await tx.CommitAsync(ct);
            Console.WriteLine($"Committed URN {urn}, version {version}, event {change.EventId}.");
        }
        return change.EventId;
    }
}
