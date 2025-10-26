# Import-Module Pester

# File: Greeter.Tests.ps1
# Requires: Pester 5.x

. "$PSScriptRoot\ClassUnderTest.ps1"   # load the classes

Describe 'Greeter with DI + New-MockObject' {

    It 'returns morning greeting' {
        # Create a fake ITimeProvider and define its method behavior
        $clock = New-MockObject -Type ([ITimeProvider]) -Methods @{
            Now = { [datetime]'2025-10-25T08:00:00Z' }
        }

        $sut = [Greeter]::new($clock)
        $sut.GetGreeting() | Should -Be 'Good morning!'

        # Each mocked method keeps a call history in _<MethodName>
        $clock._Now | Should -HaveCount 1
    }

    It 'returns afternoon greeting' {
        $clock = New-MockObject -Type ([ITimeProvider]) -Methods @{
            Now = { [datetime]'2025-10-25T15:00:00Z' }
        }

        $sut = [Greeter]::new($clock)
        $sut.GetGreeting() | Should -Be 'Good afternoon!'
        $clock._Now | Should -HaveCount 1
    }

    It 'can also decorate an existing instance (InputObject)' {
        $realClock = [ITimeProvider]::new()  # real instance
        # Decorate it: override behavior + keep history
        $clock = New-MockObject -InputObject $realClock -Methods @{
            Now = { [datetime]'2025-10-25T21:30:00Z' }
        }

        [Greeter]::new($clock).GetGreeting() | Should -Be 'Good evening!'
        $clock._Now | Should -HaveCount 1
    }
}