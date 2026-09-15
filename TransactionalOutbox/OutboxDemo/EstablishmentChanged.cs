namespace OutboxDemo;

public record EstablishmentChanged(
    Guid EventId,
    int Urn,
    string Name,
    string LocalAuthorityName,
    long Version);
