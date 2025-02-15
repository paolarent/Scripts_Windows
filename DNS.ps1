Write-Host "[[[[[[[[[[[[[[[[... CONFIGURACION DNS EN WINDOWS SERVER ...]]]]]]]]]]]]]]]]"

#Variables para la ip y el dominio
$IP = ""
$DOMINIO = ""

#FUNCIONES PARA VALIDAD TANTO LA IP COMO EL DOMINIO
#Función para validar IP
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

#Función para validar dominio
function validacion_dominio {
    param ( [string]$DOMINIO )

    $regex_dominio = '^(www\.)?[a-z0-9-]{1,30}\.[a-z]{2,6}$'

    if ($DOMINIO -notmatch $regex_dominio) {
        Write-Host "El dominio ingresado no tiene el formato valido."
        return $false
    }

    if ($DOMINIO.StartsWith("-") -or $DOMINIO.EndsWith("-")) {
        Write-Host "El dominio ingresado no puede empezar ni terminar con un guion."
        return $false
    }

    Write-Host "Okay, el dominio es valido..."
    return $true
}

#Pedir la IP hasta que sea válida
do {
    $IP = Read-Host "Ingrese la IP: "
} until (
    (validacion_ip_correcta $IP) 
)

#Pedir el dominio hasta que sea válido
do {
    $DOMINIO = Read-Host "Ingrese el Dominio: "
} until (
    (validacion_dominio $DOMINIO)<# Condition that stops the loop if it returns true #>
)

#DIVIDIR LA IP EN OCTETOS Y ALACENARLOS EN UN ARRAY, SEPARANDO POR EL PUNTO
$OCTETOS = $IP -split '\.'
#Los tres primeros octetos
$Ptres_OCT = "$($OCTETOS[0]).$($OCTETOS[1]).$($OCTETOS[2])"  
#Los tres primeros octetos invertidos
$Ptres_INV_OCT = "$($OCTETOS[2]).$($OCTETOS[1]).$($OCTETOS[0])"
#Ultimo octeto
$ULT_OCT = $OCTETOS[3]

#Configuración del servidor DNS
Write-Host "Configurando el servidor DNS con la IP: $IP y el DOMINIO: $DOMINIO..."

#PONER LA IP ESTÁTICA en la interfaz de red (RED INTERNA)
New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress $IP -PrefixLength 24
Write-Host "La IP se configuro estatica...."
#Configurar la dirección del servidor DNS en la interfaz de red "Ethernet 2"
Set-DnsClientServerAddress -InterfaceAlias "Ethernet 2" -ServerAddresses "$IP", "8.8.8.8"
Write-Host "Configurando la direccion del servidor DNS con la interfaz de red..."

#INSTALAR EL SERVICIO DE DNS y sus herramientas de administración
Write-Host "COMENZANDO INSTALACION DEL SERVICIO DNS..."
Install-WindowsFeature -Name DNS -IncludeManagementTools
if ($?) {
    Write-Host "El servicio DNS se instalo correctamente.."
    Get-WindowsFeature -Name DNS        #VERIFICACIÓN DE INSTALACIÓN
} else {
    Write-Host "Hubo un error al instalar el servicio DNS"
    exit 1
}

#CREAR Y CONFIGURAR LAS ZONAS DNS
Write-Host "...Creando y configurando las zonas DNS..."
try { 
    Add-DnsServerPrimaryZone -Name "$DOMINIO" -ZoneFile "$DOMINIO.dns" -DynamicUpdate None
    Add-DnsServerResourceRecordA -Name "@" -ZoneName "$DOMINIO" -IPv4Address "$IP"          #Crear un registro A para el dominio principal
    Add-DnsServerResourceRecordCNAME -Name "www" -ZoneName "$DOMINIO" -HostNameAlias "$DOMINIO"     #Crear un registro CNAME para "www"
    Add-DnsServerPrimaryZone -Network "$Ptres_OCT.0/24" -ZoneFile "$Ptres_OCT.dns" -DynamicUpdate None      #Configurar zona inversa para la IP
    Add-DnsServerResourceRecordPtr -Name "$ULT_OCT" -ZoneName "$Ptres_INV_OCT.in-addr.arpa" -PtrDomainName "$DOMINIO"       #Crear un registro PTR para la resolución inversa
} catch {
    Write-Host "HUBO UN ERROR AL CREAR LAS ZONAS DNS: $_ "
    exit 1
}
Get-DnsServerZone

#REINICIANDO EL SERVICIO PARA APLICAR CAMBIOS
try {
    Restart-Service -Name DNS
    Write-Host "EL SERVICIO SE ESTA REINICIANDO...."

} catch {
    Write-Host "ERROR AL REINICIAR EL SERVICIO DNS: $_"
}

#CONFIGURAR LA REGLA PARA PODER HACER PING CON EL CLIENTE
Write-Host "Configurando para poder recibir y hacer ping con el cliente..."
try {
    New-NetFirewallRule -DisplayName "Permitir Ping Entrante" -Direction Inbound -Protocol ICMPv4 -Action Allow
} catch {
    Write-Host "ERROR AL CONFIGURAR LA REGLA DEL PING: $_"
}

Write-Host "LISTO CONFIGURACION COMPLETADA"
