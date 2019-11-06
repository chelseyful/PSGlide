using module ..\PSGlide\dev\PSGlide.psm1
Describe "GlideFactory" {

    $instance = "fakeinstancenotreal"
    $name = "NotARealUser"
    $secret = ConvertTo-SecureString -String "NotARealPassword" -AsPlainText -Force
    $creds = [pscredential]::new($name, $secret)

    It "Newsup without exploding" {
        $server = [GlideFactory]::new($instance, $creds)
        [boolean]($server) | Should Be $true
    }

    It "Calculates instance URL correctly" {
        $server = [GlideFactory]::new($instance, $creds)
        $server.getURL() | Should Be "https://fakeinstancenotreal.service-now.com/api/now/v2"
    }

    It "Calculates auth string correctly" {
        $server = [GlideFactory]::new($instance, $creds)
        $server.getAuthString() | Should Be "Basic Tm90QVJlYWxVc2VyOk5vdEFSZWFsUGFzc3dvcmQ="
    }
}