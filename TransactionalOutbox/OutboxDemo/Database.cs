using Npgsql;

namespace OutboxDemo;

public static class Database
{
    public static async Task<NpgsqlConnection> Open(string connectionString, CancellationToken ct)
    {
        var connection = new NpgsqlConnection(connectionString);
        try
        {
            await connection.OpenAsync(ct);
            return connection;
        }
        catch
        {
            await connection.DisposeAsync();
            throw;
        }
    }
}
