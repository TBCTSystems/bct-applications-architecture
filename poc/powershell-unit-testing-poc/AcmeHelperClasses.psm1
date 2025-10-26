

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
        $response = $this.AcmeClient.SendRequest();
        if ($response.IsSuccessful) {
            return $response
        } else {
            throw "ExecuteCall failed with error: $($response.Error)"
        }
    }
}

Export-ModuleMember -Variable * -Function * -Alias *

