using Amazon;
using Amazon.SecretsManager;
using Amazon.SecretsManager.Model;

namespace SampleAspNetApi.AwsHelpers;
public static class AwsSecretHelper
{
    public static string GetSecret(string secretArn, string region = "us-east-2")
    {
        IAmazonSecretsManager client = new AmazonSecretsManagerClient(RegionEndpoint.GetBySystemName(region));

        GetSecretValueRequest request = new GetSecretValueRequest();
        request.SecretId = secretArn;
        request.VersionStage = "AWSCURRENT";

        GetSecretValueResponse? response = null;

        try
        {
            response = client.GetSecretValueAsync(request).Result;
        }
        catch (DecryptionFailureException e)
        {
            throw new Exception("Unable to decrypt the protected secret text using the provided KMS key: " + e);
        }
        catch (InternalServiceErrorException e)
        {
            throw new Exception("An error occurred on the server side: " + e);
        }
        catch (InvalidParameterException e)
        {
            throw new Exception("An invalid value for a parameter was provided: " + e);
        }
        catch (InvalidRequestException e)
        {
            throw new Exception("An invalid parameter value for the current state of the resource was provided: " + e);
        }
        catch (ResourceNotFoundException e)
        {
            throw new Exception("Unable to find requested resource: " + e);
        }
        catch (AggregateException ae)
        {
            throw new Exception("Multiple errors encountered: " + ae);
        }

        //Decrypts secret using the associated KMS key.
        //Depending on whether the secret is a string or binary, one of these fields will be populated.
        if (response.SecretString != null)
        {
            return response.SecretString;
        }
        else
        {
            MemoryStream memoryStream = new MemoryStream();
            memoryStream = response.SecretBinary;
            StreamReader reader = new StreamReader(memoryStream);
            return System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(reader.ReadToEnd()));
        }
    }
}
