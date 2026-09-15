namespace OutboxDemo;

public class Settings
{
    public string SourceConnectionString { get; } = Read("SOURCE_CONNECTION_STRING",
        "Host=localhost;Port=18432;Database=outbox_source;Username=postgres;Password=postgres");

    public string ReadConnectionString { get; } = Read("READ_CONNECTION_STRING",
        "Host=localhost;Port=18433;Database=outbox_read;Username=postgres;Password=postgres");

    public string ServiceBusConnectionString { get; } = Read("SERVICEBUS_CONNECTION_STRING",
        "Endpoint=sb://localhost:5673;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SAS_KEY_VALUE;UseDevelopmentEmulator=true;");

    public string Topic { get; } = Read("SERVICEBUS_TOPIC", "establishment-events");
    public string Subscription { get; } = Read("SERVICEBUS_SUBSCRIPTION", "read-model");

    private static string Read(string name, string fallback)
    {
        var value = Environment.GetEnvironmentVariable(name);
        return string.IsNullOrEmpty(value) ? fallback : value;
    }
}
