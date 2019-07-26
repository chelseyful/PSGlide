#REQUIRES -Version 5.0
using module .\ServiceNow.psd1

$creds = Get-Credential
$server = [GlideFactory]::new('myserver', $creds)
$grInc = $server.newGlideRecord('incident')
$grInc.setLimit(10)
$grInc.addQuery('active', 'true')
$grInc.query()
if ($grInc.next()) {
    $grInc.getValue('number') | Write-Host
}