Write-Host "[[[[[[[[[[[[[[[[... CONFIGURACION DHCP EN WINDOWS SERVER ...]]]]]]]]]]]]]]]]"

#Variables
$IP = ""
$IP_INICIO_RANGO = ""
$IP_FIN_RANGO = ""
$MASCARA = ""

#Funcion para validar IP
function validacion_ip_correcta {
    param ( [string]$IP )
    $regex_ipv4 = '^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if ($IP -notmatch $regex_ipv4) {
        Write-Host "La IP ingresada no tiene el formato valido."
        return $false
    }

    $octets = $IP.Split('.')
    foreach ($octet in $octets) {
        if (-not ($octet -as [int] -and $octet -ge 0 -and $octet -le 255)) {
            Write-Host "Error: La IP no es valida, los octetos deben estar entre 0 y 255."
            return $false
        }
    }

    if ([int]$octets[3] -eq 0) {
        Write-Host "Error: La IP ingresada es una direccion de red y no es valida."
        return $false
    }

    if ([int]$octets[3] -eq 255) {
        Write-Host "Error: La IP ingresada es una direccion de broadcast y no es valida."
        return $false
    }

    Write-Host "Okay, la IP ingresada es valida..."
    return $true
}

#Funcion para validar el inicio y fin del rango de IP
function validacion_rangos_ip {
    param($IP_INICIO, $IP_FIN, $IP_SERVIDOR)

    if (-not (Validacion-IP-Correcta $IP_INICIO)) { return $false }
    if (-not (Validacion-IP-Correcta $IP_FIN)) { return $false }

    #Convertir IPs a numeros enteros y comparar
    $octetos_inicial = $IP_INICIO -split '\.'
    $octetos_final = $IP_FIN -split '\.'

    $NUM_IP_INICIO = 0
    $NUM_IP_FIN = 0
    for ($i = 0; $i -lt 4; $i++) {
        $NUM_IP_INICIO = $NUM_IP_INICIO * 256 + [int]$octetos_inicial[$i]
        $NUM_IP_FIN = $NUM_IP_FIN * 256 + [int]$octetos_final[$i]
    }

    if ($NUM_IP_INICIO -ge $NUM_IP_FIN) {
        Write-Host "La IP de inicio debe ser menor que la IP de fin."
        return $false
    }

    # Verificar que las IPs de inicio y fin esten dentro del mismo segmento de red que la IP del servidor
    $IP_SERVIDOR_ARRAY = $IP_SERVIDOR -split '\.'
    $IP_INICIO_ARRAY = $IP_INICIO -split '\.'
    $IP_FIN_ARRAY = $IP_FIN -split '\.'

    if ($IP_INICIO_ARRAY[0] -ne $IP_SERVIDOR_ARRAY[0] -or $IP_INICIO_ARRAY[1] -ne $IP_SERVIDOR_ARRAY[1] -or $IP_INICIO_ARRAY[2] -ne $IP_SERVIDOR_ARRAY[2]) {
        Write-Host "Las IPs de inicio y fin no están en el mismo segmento de red que la IP del servidor."
        return $false
    }

    return $true
}

#Funcion para obtener la mascara de subred
function obtener_mascara {
    param($IP)

    $octeto = $IP -split '\.' | Select-Object -First 1
    if ($octeto -ge 0 -and $octeto -le 127) {
        return "255.0.0.0" #Clase A
    }
    elseif ($octeto -ge 128 -and $octeto -le 191) {
        return "255.255.0.0" #Clase B
    }
    elseif ($octeto -ge 192 -and $octeto -le 223) {
        return "255.255.255.0" #Clase C
    }
    else {
        Write-Host "Mascara no valida para redes publicas"
        exit 1
    }
}

#Pedir la IP del servidor hasta que sea válida
do {
    $IP = Read-Host "Ingrese la IP del servidor DHCP: "
} while (-not (validacion_ip_correcta $IP))

#Solicitar las IPs de inicio y fin del rango
do {
    $IP_INICIO_RANGO = Read-Host "Ingrese la IP de inicio del rango DHCP: "
    $IP_FIN_RANGO = Read-Host "Ingrese la IP de fin del rango DHCP: "

    if (validacion_rangos_ip $IP_INICIO_RANGO $IP_FIN_RANGO $IP) {
        break
    } else {
        Write-Host "Rango de IPs invalido. Intente nuevamente."
    }
} while ($true)

#Obtener la mascara de subred llamando a la funcion
$MASCARA = obtener_mascara $IP_INICIO_RANGO
#Variable con los tres primeros octetos de la IP de la subred
$PRIMEROS_TRES_OCTETOS = ($IP -split '\.' | Select-Object -First 3) -join '.'

#PONER LA IP ESTATICA en la interfaz de red (RED INTERNA)
New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress $IP -PrefixLength 24 -DefaultGateway "$($PRIMEROS_TRES_OCTETOS).1"
Write-Host "*** La IP se configuro estatica exitosamente ***"

#Configurar los servidores DNS
Set-DnsClientServerAddress -InterfaceAlias "Ethernet 2" -ServerAddresses 8.8.8.8, 1.1.1.1
Write-Host "*** SE HAN CONFIGURADO LOS SERVIDORES DNS EN LA INTERFAZ DE RED INTERNA ***"

#Instalar el rol de DHCP
Install-WindowsFeature -Name DHCP -IncludeManagementTools
Write-Host "*** INSTALANDO ROL Y SERVICIO DHCP ***"

#Configurar el ámbito DHCP (Rango de IPs)
Add-DhcpServerv4Scope -Name "Red-PR" -StartRange $IP_INICIO_RANGO -EndRange $IP_FIN_RANGO -SubnetMask $MASCARA
Write-Host "*** CONFIGURANDO EL AMBITO DHCP CON EL RANGO INGRESADO ***"

#Configurar la puerta de enlace y DNS en el ambito
Set-DhcpServerv4OptionValue -ScopeId "$($PRIMEROS_TRES_OCTETOS).0" -Router "$($PRIMEROS_TRES_OCTETOS).1"
Set-DhcpServerv4OptionValue -ScopeId "$($PRIMEROS_TRES_OCTETOS).0" -DnsServer 8.8.8.8, 1.1.1.1
Write-Host "*** CONFIGURANDO GATEWAY Y SERVIDORES DNS ***"

#Activar el ambito DHCP
Set-DhcpServerv4Scope -ScopeId "$($PRIMEROS_TRES_OCTETOS).0" -State Active
Write-Host "*** ACTIVANDO SERVICIO DHCP ***"
#Verificar la configuracion del servidor DHCP
Get-DhcpServerv4Scope

#REINICIAR EL SERVICIO
Restart-Service -Name DHCPServer
Write-Host "*** REINICIANDO EL SERVICIO ***"

#REGLA DEL PING ICMPV4 para el firewall
New-NetFirewallRule -DisplayName "Permitir Ping Entrante" -Direction Inbound -Protocol ICMPv4 -Action Allow
Write-Host "*** REGLA ICMPv4 CONFIGURADA, AHORA PUEDE RECIBIR PING DEL CLIENTE ***"

#Obtener lista de lease
#Get-DhcpServerv4Lease -ScopeId "$($PRIMEROS_TRES_OCTETOS).0"
