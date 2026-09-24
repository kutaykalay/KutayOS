@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Build/dev tooling prints status to the console on purpose.
        'PSAvoidUsingWriteHost'
    )
}
