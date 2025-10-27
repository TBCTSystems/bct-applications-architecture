# Import-Module Pester
# File: AcmeHelper.Tests.ps1
# Requires: Pester 5.x

using module  "./AcmeHelper.psm1"


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


   It 'successfully executes Invoke-ExecuteApiCall' {

      $response = Invoke-ExecuteApiCall -url "https://www.google.com"
      $response.StatusCode | Should -Be 200
   }

   It 'fails Invoke-ExecuteApiCall when mocking Invoke-WebRequest' {


      $fakeResponse = [PSCustomObject]@{
         StatusCode = 401
         Content    = 'Mocked website content'
      }

      # if you dont specify ModuleName, the Mock isnt called.
      Mock -CommandName Invoke-WebRequest -ModuleName AcmeHelper -MockWith {
         return $fakeResponse
      }

      $response = Invoke-ExecuteApiCall -url "https://www.google.com"
      $response.StatusCode | Should -Be $fakeResponse.StatusCode
      $response.Content | Should -Be $fakeResponse.Content
   }

}