# File: Greeter.ps1
class ITimeProvider {
    [datetime] Now() { return [datetime]::UtcNow }
}

class Greeter {
    [ITimeProvider] $Clock
    Greeter([ITimeProvider] $clock) { $this.Clock = $clock }

    [string] GetGreeting() {
        $h = ($this.Clock.Now()).Hour
        if ($h -lt 12) { return 'Good morning!' }
        elseif ($h -lt 18) { return 'Good afternoon!' }
        else { return 'Good evening!' }
    }
}