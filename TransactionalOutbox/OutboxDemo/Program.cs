namespace OutboxDemo;

internal static class Program
{
    private static async Task Main()
    {
        var settings = new Settings();
        var writer = new SourceWriter(settings);
        var publisher = new OutboxPublisher(settings);
        var consumer = new ReadModelConsumer(settings);
        while (true)
        {
            Console.WriteLine("""

                Transactional outbox demo
                1. Write or update an establishment
                2. Publish pending events
                3. Consume one event
                4. Try a write, then roll it back
                5. Replay an event
                0. Exit
                """);

            var choice = Prompt("Choose an option");
            if (choice is null or "0") return;

            try
            {
                switch (choice)
                {
                    case "1":
                    case "4":
                        if (!int.TryParse(Prompt("URN"), out var urn) || urn <= 0)
                        {
                            Console.WriteLine("Enter a positive number for the URN.");
                            break;
                        }
                        var name = Prompt("Establishment name");
                        if (name is null) return;
                        await writer.Write(urn, name, choice == "4", CancellationToken.None);
                        break;

                    case "2":
                        var count = await publisher.Publish(CancellationToken.None);
                        Console.WriteLine($"Published {count} event(s).");
                        break;

                    case "3":
                        Console.WriteLine("Waiting up to 10 seconds...");
                        if (await consumer.Consume(10, CancellationToken.None) == 0)
                            Console.WriteLine("No messages waiting.");
                        break;

                    case "5":
                        if (!Guid.TryParse(Prompt("Event ID from outbox.messages"), out var id))
                        {
                            Console.WriteLine("Enter a valid event UUID.");
                            break;
                        }
                        await publisher.Replay(id, CancellationToken.None);
                        break;

                    default:
                        Console.WriteLine("Choose a number from 0 to 5.");
                        break;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Something went wrong: {ex.Message}");
            }
        }
    }

    private static string? Prompt(string label)
    {
        Console.Write($"{label}: ");
        return Console.ReadLine()?.Trim();
    }
}
