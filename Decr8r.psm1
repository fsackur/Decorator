$TypeAccelerators = [PSObject].Assembly.GetType("System.Management.Automation.TypeAccelerators")
$TypeAccelerators::Add("DecorateWith", [Decr8r.DecorateWithAttribute])
$TypeAccelerators::Add("DecoratedCommand", [Decr8r.DecoratedCommand])
