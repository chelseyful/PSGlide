#REQUIRES -Version 5.0
<#
    ServiceNow API interface module

    Chelsey Ingersoll <cjingers>
    Lawrence Wetzel <lmwetzel>

    CHANGELOG
    7-25-19
    * Added setFields method to GlideRecord
    * Added support for pagination with limit constraint
      Setting the limit only loads the number of records
      desired. Pages beyond the limit will not be loaded.
      Page size is adjusted if necessary.
    * GlideRecord.query() no longer returns a boolean
      success of query can be determined by calling next()
#>


<#
    .DESCRIPTION
    Provides a factory for generating resources from a ServiceNow instance

    .EXAMPLE
    $credentials = Get-Credential
    $server = [GlideFactory]::new('myinstance', $credentials)
    $grInc = $server.newGlideRecord('incident')
#>
class GlideFactory {
    hidden [string]$baseURL
    hidden [pscredential]$credential
    hidden [HashTable]$commonParams

    <#
        .DESCRIPTION
        Creates an interface to a ServiceNow instance
        .PARAMETER instanceName
        A string containing the name of your instance
        For example; 'mycompany.service-now.com' would be 'mycompany'
        .PARAMETER credentials
        A set of credentials that have access to the NOW API
        Credentials are kepy in a SecureString and only
        decrypted during REST invocation
    #>
    GlideFactory ([String]$instanceName, [pscredential]$credentials) {
        $this.baseURL = "https://${instanceName}.service-now.com/api/now/v2"
        $this.credential = $credentials
        $this.commonParams = @{
            'Accept'        = 'application/json'
            'Content-Type'  = 'application/json'
            'Authorization' = $null
        }
    }

    <#
        .DESCRIPTION
        Returns the base API URL used by the specified server
    #>
    [String]getURL() {
        return $this.baseURL
    }

    [HashTable]getParams() {
        return $this.commonParams
    }

    <#
        .DESCRIPTION
        Returns an encoded string used for authenticating NOW API calls
    #>
    [String]getAuthString() {

        # Decrypt PSCredential into NetCredential for compiling the encoded string
        $netCred = $this.credential.GetNetworkCredential()
        $myToken = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $netCred.UserName, $netCred.Password)))
        $myToken = "Basic ${myToken}"

        # free the decrypted object and call garbage collector to remove ref
        $netCred = $null
        [gc]::Collect()

        return $myToken
    }

    <#
        .DESCRIPTION
        Factory method creates a new GlideRecord object for the specified table
        .PARAMETER tableName
        The name of the table to bind the GlideRecord to
    #>
    [GlideRecord]newGlideRecord([String]$tableName) {
        return [GlideRecord]::new($this, $tableName)
    }
}

<#
    .DESCRIPTION
    Base object for all factory objects produced by GlideFactory singleton
    All GlideObject children need a reference to the factory that made them
#>
class GlideObject {
    [GlideFactory]$factory
    [System.Object]$oldValue
    [System.Object]$newValue

    <#
        .PARAMETER myFactory
        A reference to the factory object that created us
        IMPORTANT! Inherted classes should call base constructor to populate
        factory member variable.
    #>
    GlideObject([GlideFactory]$myFactory) {
        $this.factory = $myFactory
    }
}

<#
    .DESCRIPTION
    Intended to mimic the nehavipr of the official GlideRecord API
    NOTE: Incomplete :-)
#>
class GlideRecord : GlideObject {

    # query settings
    hidden [string]$table
    hidden [String]$encodedQuery
    hidden [Int32]$limit
    hidden [System.Collections.ArrayList]$fields

    # pagination fields
    hidden [Uint32]$pageSize = 500

    # Data fields
    hidden [Int32]$recordPointer
    hidden [System.Collections.ArrayList]$data
    hidden [hashtable]$updates

    GlideRecord([GlideFactory]$myFactory, [string]$tableName) : base($myFactory) {
        $this.table = $tableName
        $this.limit = 0
        $this.fields = [System.Collections.ArrayList]::new()
        $this.recordPointer = -1
        $this.updates = [hashtable]::new()
    }

    <#
        .DESCRIPTION
        Add a simple equals condition to the query
        .PARAMETER field
        The field name to be filtered
        .PARAMETER value
        The exact value to match
    #>
    [void]addQuery($field, $value) {
        $this.concatQuery('{0}={1}' -f ($field, $value))
    }

    <#
        .DESCRIPTION
        Specify a query with the desired operator
        .PARAMETER field
        The field name to be filtered
        .PARAMETER operator
        One of the supported GlideRecord operators
        NOTE: Currently, you must provide the pre-encoded form of the operator
        .PARAMETER value
        value to match
    #>
    [void]addQuery([string]$field, [string]$operator, [string]$value) {
        $this.concatQuery('{0}{1}{2}' -f ($field, $operator, $value))
    }

    <#
        .DESCRIPTION
        Add an encoded query string; it will be AND'd with other elements
        .PARAMETER query
        The encoded query string to be added
    #>
    [void]addEncodedQuery([string]$query) {
        $this.concatQuery($query)
    }

    <#
        .DESCRIPTION
        Set the maximum number of records to be returned
    #>
    [void]setLimit([Int32]$newLimit) {
        $this.limit = $newLimit
    }

    <#
        .DESCRIPTION
        Set a list of fields to be returned from the query
    #>
    [void]setFields([Array]$fieldList) {
        $this.fields = $fieldList
    }

    <#
        .DESCRIPTION
        Searches for a record with tyhe provided sys_id
        Returns true if a record was found, otherwise false
        .PARAMETER sysId
        The 32 alphanumeric sys_id string
    #>
    [boolean]get([string]$sysId) {
        return $this.get('sys_id', $sysId)
    }

    <#
        .DESCRIPTION
        Instantly searches for a single record where the specified field matches
        the associated value.Returns true if a record is found, otherwise false
        .PARAMETER field
        The field name to search on
        .PARAMETER value
        The value to use in the search
    #>
    [boolean]get($field, $value) {
        $this.setLimit(1)
        $this.addQuery($field, $value)
        $this.query()
        return $this.next()
    }

    [void]query() {
        $result = [System.Collections.ArrayList]::new()

        $paramList = [System.Collections.ArrayList]::new()
        if ($this.encodedQuery -ne '') {
            $paramList.add("sysparm_query=$($this.encodedQuery)") | Out-Null
        }

        if ($this.fields.Count -gt 0) {
            $paramList.add("sysparm_fields=$($this.fields -join ',')")  | Out-Null
        }

        if ($this.limit -gt 0 -and $this.limit -lt $this.pageSize) {
            $paramList.add("sysparm_limit=$($this.limit)") | Out-Null
        } else {
            $paramList.add("sysparm_limit=$($this.pageSize)") | Out-Null
        }

        # Build request elements
        $queryURL = "$($this.factory.getURL())/table/$($this.table)?$($paramList -join '&')"
        $queryParams = $this.factory.getParams();
        $queryParams.Authorization = $this.factory.getAuthString()

        # get those pages!
        while ($null -ne $queryURL) {
            try {

                # invoke and validate request response
                $response = Invoke-WebRequest -Uri $queryURL -Method 'GET' -Headers $queryParams -UseBasicParsing
                if ($response.StatusCode -eq 200 -or $response.StatusDescription -eq 'OK') {

                    # Parse JSON and add to local heap
                    $response.content | ConvertFrom-Json | Select-Object -ExpandProperty 'result' | ForEach-Object {
                        if (
                            ($this.limit -eq 0) -or
                            ($result.count -lt $this.limit)
                        ) {
                            $result.add($_) | Out-Null
                        }
                    }

                    # Do we hunger for more data?
                    # Check the links provided by NOW to see if there is
                    # one referencing 'next'
                    $links = $response.Headers['link'] -split ','
                    if (
                        ($this.limit -eq 0 -or $result.count -lt $this.limit) -and
                        ($null -ne $links) -and
                        ($links.count -gt 1)
                    ) {
                        $queryURL = $null
                        $links | Foreach-Object {
                            if ($_.endsWith(';rel="next"')) {
                                $queryURL = ($_ -split ';')[0] -replace '<|>',''
                            }
                        }
                    } else {
                        $queryURL = $null
                    }
                } else {
                    $queryURL = $null
                }
            }
            catch {
                $result.Clear()
                $queryURL = $null
            }
        }
        $this.data = $result.ToArray()
    }

    <#
        .DESCRIPTION
        Increments the record pointer if there is an additional record in the data
        Returns true: a new row is available and pointer has been updated
        Returns false: no more data in dataset (EOF)
    #>
    [Boolean]next() {
        $newData = $false
        if ($this.recordPointer -lt $this.data.Count - 1) {
            $this.recordPointer++
            $this.updates = [hashtable]::new()
            $newData = $true
        }
        return $newData
    }

    <#
        .DESCRIPTION
        Checks to see if there is another record in the dataset without
        updating the pointer
    #>
    [Boolean]hasNext() {
        return ($this.recordPointer -lt $this.data.Count - 1)
    }

    <#
        .DESCRIPTION
        Returns the value of the specified field on the record referenced by
        the pointer in the curren data view
        .PARAMETER field
        Name of the field to get value from
    #>
    [String]getValue([string]$field) {
        $retVal = $null
        $field = $field.toLower()
        try {

            # Check if value is queued for update
            if ($this.updates.keys -contains $field) {
                $retVal = $this.updates[$field]
            } else {
                $retVal = $this.data[$this.recordPointer] | Select-Object -ExpandProperty $field
            }

            # further expand if field has a reference link
            if ($retVal -is [PSCustomObject] -and $retVal.value) {
                $retVal = $retVal.value
            }
        }
        catch {
            $retVal = $null
        }
        return $retVal
    }

    <#
        .DESCRIPTION
        Sets the value of a desired field
        .PARAMETER field
        Name of field to update
        .PARAMETER value
        Value to change the field to
    #>
    [void]setValue([string]$field, [string]$value) {
        $this.updates[$field] = $value
    }

    <#
        .DESCRIPTION
        Requests an update of the current record. Returns true on success, false
        on failure.
    #>
    [boolean]update() {
        $return = $false
        $paramList = [System.Collections.ArrayList]::new()
        if ($this.fields.Count -gt 0) {
            $paramList.add("sysparm_fields=$($this.fields -join ',')")  | Out-Null
        }

        # Build request elements
        $queryURL = "{0}/table/{1}/{2}{3}" -f (
            "$($this.factory.getURL())",
            "$($this.table)",
            "$($this.getValue('sys_id'))",
            "$($paramList -join '&')"
        )
        $global:fooo =  $queryURL
        $queryParams = $this.factory.getParams();
        $queryParams.Authorization = $this.factory.getAuthString()
        $body = $this.updates | ConvertTo-Json
        try {
            $response = Invoke-WebRequest -Uri $queryURL -Method 'PATCH' -Headers $queryParams -Body $body -UseBasicParsing
            if ($response.StatusCode -eq 200 -or $response.StatusDescription -eq 'OK') {
                $return = $true
            }
        } catch {
            $return = $false
        }
        return $return
    }

    hidden [void]concatQuery($queryString) {
        if ($this.encodedQuery.Length -gt 0) {
            $this.encodedQuery = '{0}^{1}' -f ($this.encodedQuery, $queryString)
        }
        else {
            $this.encodedQuery = $queryString
        }
    }
}
