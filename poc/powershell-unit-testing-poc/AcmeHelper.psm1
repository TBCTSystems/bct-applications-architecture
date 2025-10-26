

class AcmeResponse {
    [bool] $IsSuccessful = $false;
    [string] $Error = ""
}

class AcmeClient {
    [AcmeResponse] SendRequest() {
        $response = [AcmeResponse]::new();
        $response.Error = "";
        $response.IsSuccessful = $true;
        return $response;
    }
}

class AcmeHelper {

    [AcmeClient] $AcmeClient
    AcmeHelper([AcmeClient] $acmeClient) 
    { 
        $this.AcmeClient = $acmeClient 
    }

    [AcmeResponse] ExecuteCall() {
        return $this.AcmeClient.SendRequest();
    }
}

Export-ModuleMember -Variable * -Function * -Alias *

