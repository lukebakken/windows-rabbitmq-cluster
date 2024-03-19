$ProgressPreference = 'Continue'
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

New-Variable -Name curdir  -Option Constant -Value $PSScriptRoot
Write-Host "[INFO] script directory: $curdir"

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 'Tls12'

New-Variable -Name rmq_version -Option Constant -Value '3.13.0'

$rmq_dir = Join-Path -Path $curdir -ChildPath "rabbitmq_server-$rmq_version"
$rmq_sbin = Join-Path -Path $rmq_dir -ChildPath 'sbin'
$rmq_download_url = "https://github.com/rabbitmq/rabbitmq-server/releases/download/v$rmq_version/rabbitmq-server-windows-$rmq_version.zip"
$rmq_zip_file = Join-Path -Path $curdir -ChildPath "rabbitmq-server-windows-$rmq_version.zip"
$rmq_plugins_cmd = Join-Path -Path $rmq_sbin -ChildPath 'rabbitmq-plugins.bat'
$curdir_with_slashes = $curdir -Replace '\\','/'

New-Variable -Name rmq_server_cmd -Option Constant -Scope Script  `
    -Value (Join-Path -Path $rmq_sbin -ChildPath 'rabbitmq-server.bat')

if (!(Test-Path -Path $rmq_dir))
{
    Invoke-WebRequest -Verbose -UseBasicParsing -Uri $rmq_download_url -OutFile $rmq_zip_file
    Expand-Archive -Path $rmq_zip_file -DestinationPath $curdir
    & $rmq_plugins_cmd enable rabbitmq_management
}

Function Run-RabbitMQ
{
    Param(
        [string]$ServerCmd='rabbitmq-server.bat',
        [string]$NodeName='rmq0',
        [int]$NodePort=5672,
        [string]$Config="$curdir\rmq0\rabbitmq.conf",
        [string]$ConfEnvFile="$curdir\rmq0\rabbitmq-env-conf.bat"
    )

    $jobArgs = @{
        ArgumentList = $ServerCmd, $NodeName, $NodePort, $Config, $ConfEnvFile
        ScriptBlock = {
            param([string]$rmq_server_cmd, [string]$node_name, [int]$node_port, [string]$cfg, [string]$conf_env_file)
            Remove-Item -ErrorAction SilentlyContinue -Verbose env:\LOG
            $env:RABBITMQ_CONF_ENV_FILE = $conf_env_file
            $env:RABBITMQ_CONFIG_FILE = $cfg
            $env:RABBITMQ_NODENAME = $node_name
            $env:RABBITMQ_NODE_PORT = $node_port
            $env:LOG = 'debug'
            [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding
            & "$rmq_server_cmd"
        }
    }

    Start-Job -Verbose @jobArgs
}

[console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding

$rmq_env_conf_bat_in = Join-Path -Path $curdir -ChildPath 'rabbitmq-env-conf.txt'
$rmq_base_data_dir = Join-Path -Path $env:APPDATA -ChildPath 'RabbitMQ' | Join-Path -ChildPath 'db'
$erl_ssl_path = $(erl -noinput -eval "io:format(""~s"",[filename:dirname(code:which(inet_tls_dist))])" -s init stop)

for ($i = 0; $i -lt 3; $i++)
{
    $rmq_node_name = "rmq$i"
    $rmq_base = Join-Path -Path $curdir -ChildPath "$rmq_node_name Евгений"

    if (Test-Path -LiteralPath $rmq_base)
    {
        $rmq_node_port = 5672 + $i
        Write-Host "[INFO] configuring server '$rmq_node_name'"
        Remove-Item -Recurse -Force "$rmq_base_data_dir\$rmq_node_name*"

        $rmq_conf_in = Join-Path -Path $rmq_base -ChildPath 'rabbitmq.conf.in'
        $rmq_conf_out = Join-Path -Path $rmq_base -ChildPath 'rabbitmq.conf'
        $inter_node_tls_conf_in = Join-Path -Path $rmq_base -ChildPath 'inter_node_tls.config.in'
        $inter_node_tls_conf_out = Join-Path -Path $rmq_base -ChildPath 'inter_node_tls.config'
        $rmq_env_conf_bat_out = Join-Path -Path $rmq_base -ChildPath 'rabbitmq-env-conf.bat'

        (Get-Content -Raw -LiteralPath $rmq_conf_in) -Replace '@@CURDIR@@', $curdir_with_slashes `
            -Replace '@@COMPUTERNAME@@', $env:COMPUTERNAME | Set-Content -LiteralPath $rmq_conf_out

        (Get-Content -Raw -LiteralPath $inter_node_tls_conf_in) -Replace '@@CURDIR@@', $curdir_with_slashes `
            | Set-Content -LiteralPath $inter_node_tls_conf_out

        (Get-Content -Raw -LiteralPath $rmq_env_conf_bat_in) -Replace '@@CURDIR@@', $curdir_with_slashes `
            -Replace '@@ERL_SSL_PATH@@', $erl_ssl_path `
            -Replace '@@NODENAME@@', $rmq_node_name | Set-Content -LiteralPath $rmq_env_conf_bat_out

        Run-RabbitMQ -ServerCmd $rmq_server_cmd `
            -NodeName $rmq_node_name `
            -NodePort $rmq_node_port `
            -Config $rmq_conf_out `
            -ConfEnvFile $rmq_env_conf_bat_out
    }
    else
    {
        throw "[ERROR] could not find path '$rmq_base'"
    }
}
