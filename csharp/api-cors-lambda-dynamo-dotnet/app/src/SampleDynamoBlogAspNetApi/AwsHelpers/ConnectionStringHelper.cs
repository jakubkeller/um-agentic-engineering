using System.Text.Json;

namespace SampleAspNetApi.AwsHelpers;
public static class ConnectionStringHelper
{
    public static string GetPostgresConnectionString(string dbSecret)
    {
        var connectionStringOptions = JsonSerializer.Deserialize<PostgresConnectionStringOptions>(dbSecret, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
        });

        if (connectionStringOptions == null || connectionStringOptions.Host == null) throw new Exception("Unable to get connection string.");

        var connectionString = $"Host={connectionStringOptions.Host};Username={connectionStringOptions.UserName};" +
            $"Password={connectionStringOptions.Password};Database={connectionStringOptions.DbName}";
        return connectionString;
    }

    private sealed partial class PostgresConnectionStringOptions
    {
        public string? UserName { get; set; }
        public string? Password { get; set; }
        public string? DbName { get; set; }
        public string? Host { get; set; }
        public int Port { get; set; }
    }
}