using Azure.Messaging.ServiceBus;

namespace OutboxDemo;

public static class ServiceBusConnection
{
    public static ServiceBusClient CreateClient(Settings settings) =>
        new(settings.ServiceBusConnectionString, new ServiceBusClientOptions
        {
            RetryOptions = new ServiceBusRetryOptions
            {
                MaxRetries = 2,
                TryTimeout = TimeSpan.FromSeconds(15)
            }
        });

    public static ServiceBusMessage CreateMessage(Guid id, string payload) => new(payload)
    {
        MessageId = id.ToString(),
        ContentType = "application/json",
        Subject = "EstablishmentChanged"
    };
}
