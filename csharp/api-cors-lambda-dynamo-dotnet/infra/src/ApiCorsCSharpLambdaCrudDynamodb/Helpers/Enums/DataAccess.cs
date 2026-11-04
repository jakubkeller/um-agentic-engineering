namespace SampleAspNetApi.Helpers.Enums
{
    public enum DataAccess
    {
        enterprise,
        // public = ""; <- keyword wont work as an enum
        org,
        admin,
        vnp //(Value Not Provided) - If not provided assumed to True
    }
}
