using SampleAspNetApi.Helpers.Enums;

namespace SampleAspNetApi.Helpers
{
    public class BaseTaggingOptions
    {
        #region Properties

        public string Name { get; set; } = "SampleAspNetApi";

        public DataClassification DataClassification { get; set; } = DataClassification.Clear;

        public string Context { get; set; } = "SampleAspNetApi";

        public string Environment 
        { 
            get
            {
                if (!string.IsNullOrEmpty(System.Environment.GetEnvironmentVariable("ENVIRONMENTTYPE")))
                {
                    return System.Environment.GetEnvironmentVariable("ENVIRONMENTTYPE");
                }   
                else
                {
                    return "vnp";
                }
            }
        }     

        public string Creator
        {
            get
            {
                if (!string.IsNullOrEmpty(System.Environment.GetEnvironmentVariable("USERNAME")))
                {
                    return System.Environment.GetEnvironmentVariable("USERNAME");
                }
                else
                {
                    return "CI/CD";
                }
            }
        }

        public string Department { get; set; } = "1000-700-710-5650";

        public string ShutdownSchedule { get; set; } = "officehours";

        public string OwningTeam { get; set; } = "teamname";

        public bool SafeShutdown { get; set; } = false;

        public string AwsBackup { get; set; } = "vnp";

        public string BusinessOwner { get; set; } = "email-address@navitus.com";

        public string CostCenter { get; set; } = "np";

        public string MapMigrated { get; set; } = "d-server-01d4ezvkexutz3";

        public string MapDba { get; set; } = "d-server-01d4ezvkexutz3";

        public string AwsMigrationProjectId { get; set; } = "mpe29468";

        public Compliance Compliance { get; set; } = Compliance.vnp;

        public string DataAccess { get; set; } = "vnp";

        public Customer Customer { get; set; } = Customer.vnp;

        public CustomerType CustomerType { get; set; } = CustomerType.vnp;

        public string Version { get; set; } = "vnp";

        public string ServiceRequest { get; set; } = "vnp";

        public string MaintenanceWindow { get; set; } = "vnp";

        public string Notification { get; set; } = "email-address@navitus.com";

        public OS OS { get; set; } = OS.vnp;

        #endregion End Properties
    }
}
