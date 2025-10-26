# Import-Module Pester
# File: AcmeHelper.Tests.ps1
# Requires: Pester 5.x

using module  "./AcmeHelperClasses.psm1"


Describe 'AcmeHelper' {


    It 'returns success' {
        # Create a mock AcmeClient and define its method behavior
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

    It 'throws exception with expected message when ExecuteCall fails' {
        $errorMessage = "Some error occurred"
        # Create a mock AcmeClient and define its method behavior
        $acmeClient = New-MockObject -Type ([AcmeClient]) -Methods @{
            SendRequest = { 
                $response = [AcmeResponse]::new();
                $response.IsSuccessful = $false;
                $response.Error = $errorMessage;
                return $response;
            }
        }

        $sut = [AcmeHelper]::new($acmeClient)
        { $sut.ExecuteCall() } | Should -Throw -ExpectedMessage "ExecuteCall failed with error: $errorMessage"
    }
}