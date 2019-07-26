# PSGlide - PowerShell interface to NOW API

## Summary
This module aims to emulate the Server-Side Glide API within PowerShell.
Allowing you to query a ServiceNow instance with code that feels like the
native Glide API.

The module does this by replicating the various script includes that comprise
the server-side API, such as GlideRecord.

## Requirements

- One of;
  - Windows PowerShell 5.0 or later
  - PowerShell Core 6.0 or later
- All of
  - A ServiceNow instance with the NOW REST API
  - A username and password pair with API access

## Installation

### Windows
You may install the module system-wide, or for a particular user. Select one of
the following paths for your use case.

- Install for all users
  - %ProgramFiles%\WindowsPowerShell\Modules
- For a specific user
  - %UserProfile%\Documents\WindowsPowerShell\Modules
  - *NOTE:* You may beed to creaate this folder yourself

### Linux
Depending on your use case; copy the PSGlide folder to one of
these locations.

- All users
  - /opt/microsoft/powershell/6/Modules/
  - *NOTE:* Might not be a best practice to install 3rd party modules here
- Specific user
  - ~/.local/share/powershell/Modules

## Usage
Load the module with the `using` keyword to ensure the classes are available
in the current namespace.

```
using module PSGlide
```

Configure the connection to your ServiceNow instance by creating a new
GlideFactory. This new object will generate all the bits and pieces you would
expect from the Glide API

In the following example; assume your instance URL is; contoso.service-now.com

```
$credentials = Get-Credential
$myServer = [GlideFactory]::new('contoso', $credentials)
```

Spin up a new GlideRecord and start getting those wonderful rows!

```
$grTask = $myServer.newGlideRecord('task')
$grTask.addQuery('active','true')
$grTask.setLimit(1)
$grTask.query()
if ($grTask.next()) {
    $grTask.getValue('number') | Write-Host
}
```
