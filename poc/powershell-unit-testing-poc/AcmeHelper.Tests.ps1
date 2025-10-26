# Import-Module Pester

# File: AcmeHelper.Tests.ps1
# Requires: Pester 5.x

using module  "./AcmeHelper.psm1"


Describe 'AcmeHelper' {

    It 'returns success' {
        # Create a fake AcmeClient and define its method behavior
        $acmeClient = New-MockObject -Type ([AcmeClient]) -Methods @{
            SendRequest = { 
                $response = [AcmeResponse]::new() 
                $response.IsSuccessful = $true;
                $response.Error = "";
                return $response;
            }
        }

        $sut = [AcmeHelper]::new($acmeClient)
        $result = $sut.ExecuteCall() 
        $result.IsSuccessful | Should -Be $true
    }

    It 'returns failure' {
        $errorMessage = "Some error occurred"
        # Create a fake AcmeClient and define its method behavior
        $acmeClient = New-MockObject -Type ([AcmeClient]) -Methods @{
            SendRequest = { 
                $response = [AcmeResponse]::new();
                $response.IsSuccessful = $false;
                $response.Error = $errorMessage;
                return $response;
            }
        }

        $sut = [AcmeHelper]::new($acmeClient)
        $result = $sut.ExecuteCall() 
        $result.IsSuccessful | Should -Be $false
        $result.Error | Should -Be $errorMessage
    }


}