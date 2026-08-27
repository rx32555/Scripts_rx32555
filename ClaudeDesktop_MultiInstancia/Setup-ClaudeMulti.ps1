<#
.SYNOPSIS
    Configura Claude Desktop para correr tres (o mas) instancias aisladas en el mismo PC,
    cada una con su propia cuenta, sesion, MCPs y configuracion.

.DESCRIPTION
    Claude Desktop es una app Electron. Electron guarda TODO el estado de usuario
    (token de sesion, configuracion, MCPs, cache) en una carpeta "user data".
    Si se lanza el ejecutable con --user-data-dir="ruta", esa instancia usa una
    carpeta distinta y por lo tanto es una sesion completamente independiente.

    Este script:
      1. Detecta donde esta instalado Claude Desktop.
      2. Si la instalacion es MSIX (Microsoft Store / WindowsApps), hace una copia
         portable a una carpeta normal, porque Windows bloquea ejecutar el .exe
         desde WindowsApps con parametros.
      3. Crea un acceso directo por perfil en el Escritorio.

    En instalaciones MSIX el PRIMER perfil se lanza a traves del paquete de la
    Store (no de la copia portable), asi conserva las auto-actualizaciones.

.PARAMETER Profiles
    Nombres de los perfiles. El PRIMERO usa la carpeta de datos por defecto
    (%APPDATA%\Claude), asi conservas la sesion y los MCPs que ya tienes.
    Los siguientes usan %APPDATA%\Claude-<Nombre>.

.PARAMETER PortableDir
    Carpeta destino de la copia portable (solo se usa en instalaciones MSIX).

.PARAMETER CopyMcpConfig
    Copia el nodo mcpServers de claude_desktop_config.json del perfil por defecto
    a cada perfil nuevo. Solo esa clave: no copia sesion, credenciales ni las
    preferencias de UI ligadas a tu cuenta que viven en el mismo archivo.

.PARAMETER SharedMemory
    Siembra en TODOS los perfiles (incluido el primero) dos servidores MCP
    apuntando a una carpeta comun, para que las cuentas compartan contexto.
    Requiere Node.js. No comparte la memoria del chat: esa vive en el servidor
    y esta atada a cada cuenta.

.PARAMETER SharedDir
    Carpeta de la memoria compartida. Por defecto %APPDATA%\ClaudeShared.
    Queda fuera de %APPDATA%\ClaudeMulti a proposito: -Revert no la borra.

.PARAMETER NoLauncher
    Los accesos directos apuntan directo al .exe, sin pasar por el lanzador que
    comprueba actualizaciones. Los iconos de color se siguen aplicando.

.PARAMETER GrantWindowsAppsRead
    Autoriza sin preguntar el takeown+icacls sobre la carpeta del paquete MSIX,
    para escenarios desatendidos. Solo se usa si la copia falla por permisos.

.PARAMETER Revert
    Deshace la configuracion: borra los accesos directos, las carpetas de datos
    de los perfiles extra y la copia portable. Nunca toca %APPDATA%\Claude.

.PARAMETER Force
    Rehace la copia portable si ya existe, sobrescribe la config MCP ya copiada
    y, con -Revert, borra sin pedir confirmacion.

.EXAMPLE
    .\Setup-ClaudeMulti.ps1

.EXAMPLE
    .\Setup-ClaudeMulti.ps1 -Profiles 'Personal','Trabajo','Cliente' -CopyMcpConfig

.EXAMPLE
    .\Setup-ClaudeMulti.ps1 -Profiles 'Personal','Trabajo','Cliente' -Revert
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string[]]$Profiles    = @('Cuenta1', 'Cuenta2', 'Cuenta3'),
    [string]  $PortableDir = 'C:\ClaudePortable',
    [switch]  $CopyMcpConfig,
    [switch]  $SharedMemory,
    [string]  $SharedDir   = (Join-Path $env:APPDATA 'ClaudeShared'),
    [switch]  $NoLauncher,
    [switch]  $GrantWindowsAppsRead,
    [switch]  $Revert,
    [switch]  $Force,
    [string]  $Language    = $null,
    [switch]  $GUI,
    [switch]  $CLI
)

$ErrorActionPreference = 'Stop'

# --- Idioma e Internacionalizacion (i18n) -------------------------------------
$script:Lang = 'en'
if (-not [string]::IsNullOrWhiteSpace($Language)) {
    if ($Language -match '^es') { $script:Lang = 'es' }
    else { $script:Lang = 'en' }
}
else {
    try {
        $uiCulture = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
        if ($uiCulture -eq 'es') { $script:Lang = 'es' }
    } catch {
        $script:Lang = 'en'
    }
}

$script:I18n = @{
    es = @{
        HeaderTitle               = 'Claude Desktop - configuracion de multiples instancias'
        MenuTitle                 = 'Claude Desktop - Multi Instancia (Menu)'
        CurrentInstances          = 'Instancias configuradas actualmente'
        ReadyTitle                = 'Listo'
        HeaderPerfil              = 'Perfil'
        HeaderColor               = 'Color'
        HeaderLanza               = 'Lanza'
        HeaderAcceso              = 'Acceso'
        ProfileLabelOriginal      = 'Claude - {0} (perfil actual)'
        ProfileLabelOriginalNote  = 'Claude - {0} ({1}) (perfil actual)'
        ProfileLabelExtra         = 'Claude - {0}'
        ProfileLabelExtraNote     = 'Claude - {0} ({1})'
        CopyMcpsLabel             = 'Copiar MCPs (-CopyMcpConfig)'
        SharedMemLabel            = 'Memoria compartida (-SharedMemory)'
        SharedMemOnAt             = 'SI -> {0}'
        NoShort                   = 'NO'
        MenuOpt1                  = '[1] Ejecutar / Actualizar instalacion actual ({0})'
        MenuOpt2                  = '[2] Especificar cantidad total de instancias (ej: 4 -> Cuenta1..Cuenta4)'
        MenuOpt3                  = '[3] Anadir una nueva instancia / perfil (ej: "Cuenta4" o "Trabajo")'
        MenuOpt4                  = '[4] Asignar nota / correo a un perfil (ej: trabajo@empresa.com)'
        MenuOpt5                  = '[5] Diagnostico de salud del sistema (Health Check)'
        MenuOpt6                  = '[6] Limpiar cache y archivos temporales (liberar espacio en disco)'
        MenuOpt7                  = '[7] Crear Backup de perfiles (.zip)'
        MenuOpt8                  = '[8] Restaurar perfiles desde Backup (.zip)'
        MenuOpt9                  = '[9] Alternar copia de MCPs a nuevos perfiles'
        MenuOpt10                 = '[10] Alternar memoria compartida entre instancias (MCP)'
        MenuOpt11                 = '[11] Revertir / Eliminar perfiles'
        MenuOpt0                  = '[0] Salir'
        SelectOpt                 = 'Selecciona una opcion (0-11)'
        EnterTotalNum             = 'Ingresa el numero total de instancias deseado (ej: 4)'
        InvalidNum                = 'Numero no valido.'
        EnterNewName              = 'Ingresa el nombre del nuevo perfil o instancia (ej: Cuenta4 o Trabajo)'
        ProfileExists             = 'El perfil "{0}" ya existe.'
        NameCannotBeEmpty         = 'El nombre no puede estar vacio.'
        CopyMcpsActive            = 'Copia de MCPs: ACTIVADA'
        CopyMcpsInactive          = 'Copia de MCPs: DESACTIVADA'
        WarnDeleteData            = 'Se eliminaran accesos directos y datos de perfiles extra.'
        ConfirmRevert             = 'Confirmas revertir la configuracion? (S/N)'
        OpCancelled               = 'Operacion cancelada.'
        InvalidOpt                = 'Opcion invalida.'
        AskDeepClean              = 'Borrar tambien la imagen de la VM de Cowork? (S/N)'
        AskBackupPath             = 'Ingresa la ruta completa del archivo .zip de backup'
        AskProfileToEdit          = 'Selecciona el numero de perfil a editar (vacio para cancelar)'
        AskNoteFor                = 'Ingresa la nota/correo para "{0}" (vacio para borrar)'
        EditNotesTitle            = '--- Asignar Nota / Correo a Perfil ---'
        SharedMemOn               = 'Memoria compartida: ACTIVADA -> {0}'
        SharedMemOff              = 'Memoria compartida: DESACTIVADA (no se quita de los perfiles ya configurados).'
        SharedMemApplyHint        = 'Se aplica al ejecutar la opcion [1].'
        NoNpxWarnMenu             = 'No se encontro npx en el PATH. Instala Node.js o los servidores no arrancaran.'
        GuiTitle                  = 'Claude Desktop - Multi Instancia'
        GuiBtnRun                 = 'Ejecutar / Actualizar Instancias'
        GuiBtnAdd                 = '+ Anadir Perfil'
        GuiBtnNote                = 'Editar Nota/Email'
        GuiBtnHealth              = 'Health Check'
        GuiBtnCache               = 'Limpiar Cache'
        GuiBtnBackup              = 'Crear Backup (.zip)'
        GuiBtnRestore             = 'Restaurar Backup'
        GuiBtnRevert              = 'Revertir / Eliminar Perfiles Extra'
        GuiRunning                = '==> Ejecutando configuracion para perfiles: {0}'
        GuiRunningHint            = '    (si toca copiar Claude, la ventana quedara sin responder unos minutos)'
        GuiAddPrompt              = 'Ingresa el nombre de la nueva instancia:'
        GuiAddTitle               = 'Anadir Perfil'
        GuiAddDefault             = 'Trabajo'
        GuiAdding                 = '==> Anadiendo perfil "{0}". Configurando...'
        GuiPickProfile            = 'Por favor selecciona un perfil de la lista para editar su nota/correo.'
        GuiNotePrompt             = 'Ingresa la nota/correo para "{0}":'
        GuiNoteTitle              = 'Editar Nota/Email'
        GuiNoteUpdated            = 'Nota de "{0}" actualizada a: "{1}".'
        GuiRebuilding             = '==> Reconstruyendo accesos directos en el Escritorio con los nuevos nombres...'
        GuiStartHealth            = 'Iniciando Diagnostico Health Check...'
        GuiStartCache             = 'Iniciando Limpieza de Cache...'
        GuiZipFilter              = 'Archivos ZIP (*.zip)|*.zip'
        GuiSaveBackupTitle        = 'Guardar Backup de Perfiles'
        GuiOpenBackupTitle        = 'Seleccionar Backup a Restaurar'
        GuiConfirmRevert          = 'Seguro que deseas revertir y eliminar los accesos directos y datos de perfiles extra?'
        GuiConfirmRevertTitle     = 'Confirmar Reversion'
        GuiReverting              = '==> Revirtiendo instalacion de perfiles extra...'
        GuiDeepCleanTitle         = 'Limpieza profunda'
        GuiPermTitle              = 'Permisos WindowsApps'
        GuiPermAsk                = 'Dar permisos de lectura al grupo Administradores sobre {0}?'
        MsgOneProfileOnly         = 'Solo se indico un perfil: no se crea ninguna instancia adicional.'
        MsgNoAppx                 = 'Get-AppxPackage no esta disponible en esta edicion de PowerShell.'
        MsgNoAppx2                = 'No se puede detectar una instalacion de Microsoft Store desde aqui.'
        MsgNoAppx3                = 'Vuelve a ejecutar con Windows PowerShell 5.1:'
        MsgShortcutExists         = 'Ya existia ''{0}.lnk'' en el Escritorio: se sobrescribe.'
        MsgNoAppx4                = '  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup-ClaudeMulti.ps1'
        MsgReuseCopy              = 'Se reutilizara la copia existente.'
        MsgDeletingOldCopy        = 'Borrando copia anterior...'
        MsgCopying                = 'Copiando {0}'
        MsgCopyingTo              = '     ->  {0}'
        MsgBadJsonKeep            = 'No se pudo leer {0} como JSON: se deja como esta.'
        MsgServerKept             = '''{0}'' ya existe en {1} y se conserva (usa -Force para reemplazarlo).'
        MsgNoSrcConfig            = 'No hay claude_desktop_config.json en {0}; no se copian MCPs.'
        MsgBadSrcJson             = 'No se pudo leer {0} como JSON; no se copian MCPs.'
        MsgNoMcpsToCopy           = 'Tu perfil actual no tiene MCP servers configurados: no hay nada que copiar.'
        MsgMcpsCopied             = 'MCPs copiados ({0}) -> {1}'
        StepDeletingShortcuts     = 'Borrando accesos directos...'
        MsgDeleted                = 'Borrado: {0}'
        StepDeletingProfileData   = 'Borrando carpetas de datos de los perfiles extra...'
        MsgNoExtraData            = 'No hay carpetas de perfiles extra que borrar.'
        MsgNoConfirmHost          = 'No se puede pedir confirmacion en este host.'
        MsgAddForce               = 'Anade -Force para borrar las carpetas de datos sin preguntar.'
        MsgDataKept               = 'Carpetas de datos conservadas.'
        StepRemovingShared        = 'Quitando los servidores de memoria compartida del perfil principal...'
        MsgRemoved                = 'Quitados: {0}'
        MsgNoSharedToRemove       = 'No habia servidores compartidos que quitar.'
        StepDeletingLauncher      = 'Borrando lanzador e iconos...'
        MsgDoesNotExist           = 'No existe {0}.'
        StepDeletingPortable      = 'Borrando la copia portable...'
        MsgUntouchedMain          = 'Intacto: {0} (tu perfil original).'
        MsgUntouchedShared        = 'Intacto: {0} (memoria compartida). Borrala a mano si ya no la quieres.'
        MsgNoteUpdated            = 'Nota de ''{0}'' actualizada.'
        MsgCfgUpdateFailed        = 'No se pudo actualizar config.json: {0}'
        HcTitle                   = '  Diagnostico de Salud del Sistema (Health Check)'
        HcMainExe                 = 'Ejecutable principal: {0}'
        MsgInstallMode            = 'Modo de instalacion: {0}'
        MsgInstalledVer           = 'Version instalada: {0}'
        HcNoInstall               = 'No se detecto instalacion activa de Claude Desktop.'
        HcLauncherDir             = 'Carpeta de lanzadores e iconos: {0} [OK]'
        HcNoLauncherDir           = 'No existe la carpeta de lanzadores: {0}'
        HcProfileStates           = 'Estado de perfiles configurados:'
        HcNotCreated              = 'No creada'
        HcLnkOk                   = 'Acceso directo [OK]'
        HcLnkMissing              = 'Acceso directo [FALTA]'
        HcProfileLine             = '{0}{1} -> {2} | {3}'
        HcNoProfiles              = 'No hay perfiles configurados actualmente.'
        HcOrphans                 = 'Perfiles huerfanos (existen en disco pero no en config.json):'
        PairArrow                 = '{0} -> {1}'
        HcOrphanHint1             = 'Vuelve a ejecutar la configuracion incluyendolos en -Profiles'
        HcOrphanHint2             = 'para readoptarlos, o borra la carpeta a mano si ya no los usas.'
        HcSharedTitle             = 'Memoria compartida entre instancias:'
        HcSharedOn                = 'Activa -> {0} ({1} KB de memoria, {2} documento(s) .md)'
        HcSharedNoDir             = 'Activa en config.json pero la carpeta no existe: {0}'
        HcSharedConnected         = '  {0} -> conectado'
        HcSharedMissing           = '  {0} -> SIN los servidores compartidos'
        HcNoNpx                   = '  npx no esta en el PATH: los servidores compartidos no van a arrancar.'
        HcSharedOff               = 'Desactivada. Activala con -SharedMemory o desde la interfaz.'
        HcRunningProcs            = 'Procesos de Claude en ejecucion: {0}'
        MsgOldBinaryDeleted       = 'Binario viejo borrado: {0}\claude-code\{1}'
        CacheTitle                = '--- Limpiador de Cache y Archivos Temporales ---'
        MsgProcsRunning           = 'Hay {0} proceso(s) de Claude en ejecucion.'
        MsgCloseBeforeClean       = 'Cierra todas las ventanas de Claude antes de limpiar la cache.'
        MsgNoProfilesToClean      = 'No se encontraron carpetas de perfiles para limpiar.'
        MsgCleanDone              = 'Limpieza completada. Espacio en disco liberado: {0} MB'
        MsgHeavyPending           = 'Ademas hay {0} MB en la imagen de la VM de Cowork ({1}).'
        MsgHeavyHint              = 'Se puede borrar, pero la app la vuelve a descargar entera la proxima vez que uses Cowork.'
        BackupTitle               = '--- Respaldar Perfiles (Backup .zip) ---'
        MsgCloseBeforeBackup      = 'Cierra todas las ventanas de Claude antes de respaldar:'
        MsgCloseBeforeBackup2     = 'con la app abierta, la sesion queda bloqueada y no se copia.'
        MsgBackupHasTokens        = 'El backup incluye los tokens de sesion de todas las cuentas.'
        MsgBackupKeepSafe         = 'Guarda el .zip en un sitio seguro: equivale a tus credenciales.'
        MsgFilesInUse             = 'Algunos archivos de "{0}" estaban en uso y se omitieron.'
        MsgIncluded               = 'Incluido: {0}'
        MsgBackupOk               = 'Backup creado exitosamente:'
        MsgBackupPath             = '{0} ({1} MB)'
        MsgBackupIncomplete       = '{0} perfil(es) quedaron incompletos por archivos en uso.'
        MsgBackupError            = 'Error al crear el backup: {0}'
        MsgFileNotFound           = 'No se encontro el archivo: {0}'
        MsgCloseBeforeRestore     = 'Cierra todas las ventanas de Claude antes de restaurar.'
        MsgLauncherRestored       = 'Configuracion de lanzador restaurada.'
        MsgProfileRestored        = 'Restaurado perfil: {0}'
        MsgRestoreOk              = 'Restauracion completada exitosamente.'
        MsgRestoreHint            = 'Se recomienda ejecutar la configuracion para actualizar los accesos directos.'
        MsgRestoreError           = 'Error al restaurar el backup: {0}'
        StepSearchingInstall      = 'Buscando la instalacion de Claude Desktop...'
        MsgNotFound               = 'No se encontro Claude Desktop en este equipo.'
        MsgPathsChecked           = 'Rutas revisadas: %LOCALAPPDATA%\AnthropicClaude, %ProgramFiles%\Claude y paquetes MSIX.'
        MsgInstallClaude          = 'Instala Claude Desktop y vuelve a ejecutar este script.'
        MsgFolder                 = 'Carpeta: {0}'
        StepMsixDetected          = 'Instalacion tipo MSIX detectada (Microsoft Store).'
        MsgMsixNote1              = 'Windows no permite lanzar el .exe desde WindowsApps con parametros,'
        MsgMsixNote2              = 'asi que hay que hacer una copia portable en una carpeta normal.'
        MsgPortableUpToDate       = 'Copia portable al dia (version {0}). No hay nada que actualizar.'
        MsgNoPortableYet          = 'No hay copia portable todavia.'
        MsgForceRecopy            = 'Se pidio -Force: se rehace la copia.'
        MsgClaudeUpdated          = 'Claude se actualizo: {0} -> {1}. Actualizando la copia...'
        MsgPortableIncomplete     = 'La copia portable esta incompleta o movida: se rehace.'
        MsgPortableNoStamp        = 'Hay una copia portable sin sello de version: se rehace para poder controlarla.'
        MsgPortableBusy           = 'Hay {0} proceso(s) de Claude corriendo desde {1}.'
        MsgCannotReplace          = 'No se puede reemplazar la copia mientras esten abiertos.'
        MsgCloseAndRetry          = 'Cierra esas ventanas de Claude y vuelve a intentar.'
        MsgKeepUsingCurrent       = 'Por ahora se sigue usando la copia actual.'
        MsgUpdateFailedBusy       = 'La actualizacion fallo: hay Claude abierto desde la copia portable.'
        MsgCloseAllAndRetry       = 'Cierra todas las ventanas de Claude y vuelve a intentar.'
        MsgCopyFailedPerms        = 'La copia fallo por los permisos restrictivos de WindowsApps.'
        MsgPermsFix1              = 'La solucion es dar permiso de lectura al grupo Administradores'
        MsgPermsFix2              = 'sobre esa carpeta.'
        MsgPermsAsk               = 'Dar lectura al grupo Administradores sobre {0}?'
        MsgPermsCaption           = 'Permisos de WindowsApps'
        MsgNonInteractive         = 'Ejecucion no interactiva: usa -GrantWindowsAppsRead para autorizarlo.'
        MsgCancelled              = 'Cancelado.'
        MsgNeedsAdmin             = 'Este paso necesita permisos de Administrador.'
        MsgRunAsAdmin             = 'Cierra esta ventana y ejecuta con "Ejecutar como administrador".'
        MsgTakingOwnership        = 'Tomando posesion de la carpeta del paquete...'
        MsgGrantingRead           = 'Otorgando lectura a Administradores...'
        MsgPortableReady          = 'Copia portable lista (version {0}): {1}'
        MsgNoPortableNeeded       = 'No hace falta copia portable: el ejecutable se puede lanzar directo.'
        MsgVersionedFolder        = 'El ejecutable esta dentro de una carpeta con numero de version.'
        StepPreparingShared       = 'Preparando la memoria compartida entre instancias...'
        MsgNoNpxSetup             = 'No se encontro npx en el PATH: los servidores MCP compartidos necesitan Node.js.'
        MsgNodeOutsidePath        = 'Node parece estar en {0} pero no esta en el PATH.'
        MsgAddToPath              = 'Anade esa carpeta al PATH y vuelve a ejecutar con -SharedMemory.'
        MsgInstallNode            = 'Instala Node.js (https://nodejs.org) y vuelve a ejecutar con -SharedMemory.'
        MsgRestContinues          = 'El resto de la configuracion sigue normalmente.'
        MsgSharedFolder           = 'Carpeta compartida: {0}'
        MsgNpxAt                  = 'npx: {0}'
        StepGeneratingIcons       = 'Generando iconos de color por perfil...'
        MsgIconFailed             = 'No se pudo generar el icono de ''{0}'': {1}'
        StepInstallingLauncher    = 'Instalando lanzador (comprueba actualizaciones antes de abrir)...'
        StepCreatingShortcuts     = 'Creando accesos directos en el Escritorio...'
        MsgWhatIfRemoveOld        = 'Whatif: se borraria el acceso anterior: {0}'
        MsgRemovedOldLnk          = 'Removido acceso directo anterior: {0}'
        MsgSharedInProfile        = 'Memoria compartida en "{0}" ({1}).'
        MsgProfileDone            = '{0}  [{1}]'
        MsgNonInteractiveDefaults = 'Host no interactivo: se usan los perfiles por defecto.'
        DescStore                 = 'Claude Desktop - perfil "{0}"{1} (paquete de la Store)'
        DescExe                   = 'Claude Desktop - perfil "{0}"{1} en {2}'
        DescLauncher              = 'Claude Desktop - perfil "{0}"{1} (comprueba actualizaciones al abrir)'
        ErrEmptyProfiles          = 'La lista de perfiles esta vacia.'
        ErrEmptyName              = 'Hay un nombre de perfil vacio en -Profiles.'
        ErrBadChars               = 'El nombre de perfil ''{0}'' contiene caracteres no validos para un archivo o carpeta.'
        ErrBadEdges               = 'El nombre de perfil ''{0}'' no puede empezar/terminar en espacio ni terminar en punto.'
        ErrDupNames               = 'Hay nombres de perfil repetidos: {0}'
        ErrRobocopy               = 'robocopy fallo (codigo {0}). Probablemente por permisos de WindowsApps.'
        ErrRobocopyProfile        = 'robocopy fallo copiando {0} (codigo {1}).'
        ErrNoClaudeExe            = 'No se encontro claude.exe dentro de {0}'
        ErrNoTargetExe            = 'No se pudo determinar el ejecutable de Claude Desktop.'
        MenuProfileLine           = '  [{0}] {1}{2}'
        GuiDeepCleanMsg           = 'Quedan {0} MB en la imagen de la VM de Cowork.`n`nSe puede borrar, pero la app la volvera a descargar entera la proxima vez que uses Cowork.`n`nBorrarla igual?'
        YesShort                  = 'SI'
        ColorAzul                 = 'azul'
        ColorVerde                = 'verde'
        ColorMorado               = 'morado'
        ColorCian                 = 'cian'
        ColorRosa                 = 'rosa'
        ColorAzabache             = 'azabache'
        ColorOliva                = 'oliva'
        ViaStore                  = 'Store'
        ViaExe                    = 'Exe'
        ViaLauncher               = 'Lanzador'
    }
    en = @{
        HeaderTitle               = 'Claude Desktop - Multi-Instance Setup'
        MenuTitle                 = 'Claude Desktop - Multi-Instance (Menu)'
        CurrentInstances          = 'Currently configured instances'
        ReadyTitle                = 'Ready'
        HeaderPerfil              = 'Profile'
        HeaderColor               = 'Color'
        HeaderLanza               = 'Launcher'
        HeaderAcceso              = 'Shortcut'
        ProfileLabelOriginal      = 'Claude - {0} (current profile)'
        ProfileLabelOriginalNote  = 'Claude - {0} ({1}) (current profile)'
        ProfileLabelExtra         = 'Claude - {0}'
        ProfileLabelExtraNote     = 'Claude - {0} ({1})'
        CopyMcpsLabel             = 'Copy MCPs (-CopyMcpConfig)'
        SharedMemLabel            = 'Shared memory (-SharedMemory)'
        SharedMemOnAt             = 'YES -> {0}'
        NoShort                   = 'NO'
        MenuOpt1                  = '[1] Run / Update current installation ({0})'
        MenuOpt2                  = '[2] Set total number of instances (e.g. 4 -> Cuenta1..Cuenta4)'
        MenuOpt3                  = '[3] Add a new instance / profile (e.g. "Cuenta4" or "Work")'
        MenuOpt4                  = '[4] Assign a note / email to a profile (e.g. work@company.com)'
        MenuOpt5                  = '[5] System health check'
        MenuOpt6                  = '[6] Clean cache and temporary files (free up disk space)'
        MenuOpt7                  = '[7] Create profile backup (.zip)'
        MenuOpt8                  = '[8] Restore profiles from backup (.zip)'
        MenuOpt9                  = '[9] Toggle copying MCPs to new profiles'
        MenuOpt10                 = '[10] Toggle shared memory across instances (MCP)'
        MenuOpt11                 = '[11] Revert / Delete profiles'
        MenuOpt0                  = '[0] Exit'
        SelectOpt                 = 'Select an option (0-11)'
        EnterTotalNum             = 'Enter the desired total number of instances (e.g. 4)'
        InvalidNum                = 'Invalid number.'
        EnterNewName              = 'Enter the name of the new profile or instance (e.g. Cuenta4 or Work)'
        ProfileExists             = 'Profile "{0}" already exists.'
        NameCannotBeEmpty         = 'Name cannot be empty.'
        CopyMcpsActive            = 'Copy MCPs: ENABLED'
        CopyMcpsInactive          = 'Copy MCPs: DISABLED'
        WarnDeleteData            = 'Shortcuts and extra profile data will be deleted.'
        ConfirmRevert             = 'Confirm reverting the configuration? (Y/N)'
        OpCancelled               = 'Operation cancelled.'
        InvalidOpt                = 'Invalid option.'
        AskDeepClean              = 'Delete the Cowork VM image too? (Y/N)'
        AskBackupPath             = 'Enter the full path to the backup .zip file'
        AskProfileToEdit          = 'Select the profile number to edit (empty to cancel)'
        AskNoteFor                = 'Enter the note/email for "{0}" (empty to clear)'
        EditNotesTitle            = '--- Assign Note / Email to Profile ---'
        SharedMemOn               = 'Shared memory: ENABLED -> {0}'
        SharedMemOff              = 'Shared memory: DISABLED (not removed from already-configured profiles).'
        SharedMemApplyHint        = 'It is applied when you run option [1].'
        NoNpxWarnMenu             = 'npx was not found on PATH. Install Node.js or the servers will not start.'
        GuiTitle                  = 'Claude Desktop - Multi-Instance'
        GuiBtnRun                 = 'Run / Update Instances'
        GuiBtnAdd                 = '+ Add Profile'
        GuiBtnNote                = 'Edit Note/Email'
        GuiBtnHealth              = 'Health Check'
        GuiBtnCache               = 'Clean Cache'
        GuiBtnBackup              = 'Create Backup (.zip)'
        GuiBtnRestore             = 'Restore Backup'
        GuiBtnRevert              = 'Revert / Delete Extra Profiles'
        GuiRunning                = '==> Running setup for profiles: {0}'
        GuiRunningHint            = '    (if Claude has to be copied, the window will stop responding for a few minutes)'
        GuiAddPrompt              = 'Enter the name of the new instance:'
        GuiAddTitle               = 'Add Profile'
        GuiAddDefault             = 'Work'
        GuiAdding                 = '==> Adding profile "{0}". Configuring...'
        GuiPickProfile            = 'Please select a profile from the list to edit its note/email.'
        GuiNotePrompt             = 'Enter the note/email for "{0}":'
        GuiNoteTitle              = 'Edit Note/Email'
        GuiNoteUpdated            = 'Note for "{0}" updated to: "{1}".'
        GuiRebuilding             = '==> Rebuilding desktop shortcuts with the new names...'
        GuiStartHealth            = 'Starting health check...'
        GuiStartCache             = 'Starting cache cleanup...'
        GuiZipFilter              = 'ZIP files (*.zip)|*.zip'
        GuiSaveBackupTitle        = 'Save Profile Backup'
        GuiOpenBackupTitle        = 'Select Backup to Restore'
        GuiConfirmRevert          = 'Are you sure you want to revert and delete the shortcuts and data of the extra profiles?'
        GuiConfirmRevertTitle     = 'Confirm Revert'
        GuiReverting              = '==> Reverting the extra profile setup...'
        GuiDeepCleanTitle         = 'Deep cleanup'
        GuiPermTitle              = 'WindowsApps permissions'
        GuiPermAsk                = 'Grant read permissions to the Administrators group on {0}?'
        MsgOneProfileOnly         = 'Only one profile was given: no additional instance will be created.'
        MsgNoAppx                 = 'Get-AppxPackage is not available in this edition of PowerShell.'
        MsgNoAppx2                = 'A Microsoft Store installation cannot be detected from here.'
        MsgNoAppx3                = 'Run again with Windows PowerShell 5.1:'
        MsgShortcutExists         = '''{0}.lnk'' already existed on the Desktop: overwriting.'
        MsgNoAppx4                = '  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup-ClaudeMulti.ps1'
        MsgReuseCopy              = 'The existing copy will be reused.'
        MsgDeletingOldCopy        = 'Deleting previous copy...'
        MsgCopying                = 'Copying {0}'
        MsgCopyingTo              = '     ->  {0}'
        MsgBadJsonKeep            = 'Could not read {0} as JSON: leaving it as is.'
        MsgServerKept             = '''{0}'' already exists in {1} and is kept (use -Force to replace it).'
        MsgNoSrcConfig            = 'There is no claude_desktop_config.json in {0}; MCPs will not be copied.'
        MsgBadSrcJson             = 'Could not read {0} as JSON; MCPs will not be copied.'
        MsgNoMcpsToCopy           = 'Your current profile has no MCP servers configured: there is nothing to copy.'
        MsgMcpsCopied             = 'MCPs copied ({0}) -> {1}'
        StepDeletingShortcuts     = 'Deleting shortcuts...'
        MsgDeleted                = 'Deleted: {0}'
        StepDeletingProfileData   = 'Deleting data folders of the extra profiles...'
        MsgNoExtraData            = 'There are no extra profile folders to delete.'
        MsgNoConfirmHost          = 'Confirmation cannot be requested in this host.'
        MsgAddForce               = 'Add -Force to delete the data folders without asking.'
        MsgDataKept               = 'Data folders kept.'
        StepRemovingShared        = 'Removing the shared memory servers from the main profile...'
        MsgRemoved                = 'Removed: {0}'
        MsgNoSharedToRemove       = 'There were no shared servers to remove.'
        StepDeletingLauncher      = 'Deleting launcher and icons...'
        MsgDoesNotExist           = '{0} does not exist.'
        StepDeletingPortable      = 'Deleting the portable copy...'
        MsgUntouchedMain          = 'Untouched: {0} (your original profile).'
        MsgUntouchedShared        = 'Untouched: {0} (shared memory). Delete it by hand if you no longer want it.'
        MsgNoteUpdated            = 'Note for ''{0}'' updated.'
        MsgCfgUpdateFailed        = 'Could not update config.json: {0}'
        HcTitle                   = '  System Health Check'
        HcMainExe                 = 'Main executable: {0}'
        MsgInstallMode            = 'Installation mode: {0}'
        MsgInstalledVer           = 'Installed version: {0}'
        HcNoInstall               = 'No active Claude Desktop installation was detected.'
        HcLauncherDir             = 'Launcher and icon folder: {0} [OK]'
        HcNoLauncherDir           = 'The launcher folder does not exist: {0}'
        HcProfileStates           = 'Status of configured profiles:'
        HcNotCreated              = 'Not created'
        HcLnkOk                   = 'Shortcut [OK]'
        HcLnkMissing              = 'Shortcut [MISSING]'
        HcProfileLine             = '{0}{1} -> {2} | {3}'
        HcNoProfiles              = 'There are no profiles configured right now.'
        HcOrphans                 = 'Orphan profiles (they exist on disk but not in config.json):'
        PairArrow                 = '{0} -> {1}'
        HcOrphanHint1             = 'Run the setup again including them in -Profiles'
        HcOrphanHint2             = 'to re-adopt them, or delete the folder by hand if you no longer use them.'
        HcSharedTitle             = 'Shared memory across instances:'
        HcSharedOn                = 'Enabled -> {0} ({1} KB of memory, {2} .md document(s))'
        HcSharedNoDir             = 'Enabled in config.json but the folder does not exist: {0}'
        HcSharedConnected         = '  {0} -> connected'
        HcSharedMissing           = '  {0} -> WITHOUT the shared servers'
        HcNoNpx                   = '  npx is not on PATH: the shared servers will not start.'
        HcSharedOff               = 'Disabled. Enable it with -SharedMemory or from the interface.'
        HcRunningProcs            = 'Claude processes running: {0}'
        MsgOldBinaryDeleted       = 'Old binary deleted: {0}\claude-code\{1}'
        CacheTitle                = '--- Cache and Temporary File Cleaner ---'
        MsgProcsRunning           = 'There are {0} Claude process(es) running.'
        MsgCloseBeforeClean       = 'Close all Claude windows before cleaning the cache.'
        MsgNoProfilesToClean      = 'No profile folders were found to clean.'
        MsgCleanDone              = 'Cleanup complete. Disk space freed: {0} MB'
        MsgHeavyPending           = 'There are also {0} MB in the Cowork VM image ({1}).'
        MsgHeavyHint              = 'It can be deleted, but the app downloads it again in full the next time you use Cowork.'
        BackupTitle               = '--- Back Up Profiles (.zip) ---'
        MsgCloseBeforeBackup      = 'Close all Claude windows before backing up:'
        MsgCloseBeforeBackup2     = 'with the app open the session is locked and does not get copied.'
        MsgBackupHasTokens        = 'The backup includes the session tokens of every account.'
        MsgBackupKeepSafe         = 'Keep the .zip somewhere safe: it is equivalent to your credentials.'
        MsgFilesInUse             = 'Some files in "{0}" were in use and were skipped.'
        MsgIncluded               = 'Included: {0}'
        MsgBackupOk               = 'Backup created successfully:'
        MsgBackupPath             = '{0} ({1} MB)'
        MsgBackupIncomplete       = '{0} profile(s) were left incomplete because of files in use.'
        MsgBackupError            = 'Error creating the backup: {0}'
        MsgFileNotFound           = 'File not found: {0}'
        MsgCloseBeforeRestore     = 'Close all Claude windows before restoring.'
        MsgLauncherRestored       = 'Launcher configuration restored.'
        MsgProfileRestored        = 'Profile restored: {0}'
        MsgRestoreOk              = 'Restore completed successfully.'
        MsgRestoreHint            = 'It is recommended to run the setup to refresh the shortcuts.'
        MsgRestoreError           = 'Error restoring the backup: {0}'
        StepSearchingInstall      = 'Searching for the Claude Desktop installation...'
        MsgNotFound               = 'Claude Desktop was not found on this computer.'
        MsgPathsChecked           = 'Paths checked: %LOCALAPPDATA%\AnthropicClaude, %ProgramFiles%\Claude and MSIX packages.'
        MsgInstallClaude          = 'Install Claude Desktop and run this script again.'
        MsgFolder                 = 'Folder: {0}'
        StepMsixDetected          = 'MSIX installation detected (Microsoft Store).'
        MsgMsixNote1              = 'Windows does not allow launching the .exe from WindowsApps with parameters,'
        MsgMsixNote2              = 'so a portable copy has to be made in a normal folder.'
        MsgPortableUpToDate       = 'Portable copy up to date (version {0}). There is nothing to update.'
        MsgNoPortableYet          = 'There is no portable copy yet.'
        MsgForceRecopy            = '-Force was requested: the copy is remade.'
        MsgClaudeUpdated          = 'Claude was updated: {0} -> {1}. Updating the copy...'
        MsgPortableIncomplete     = 'The portable copy is incomplete or moved: it will be remade.'
        MsgPortableNoStamp        = 'There is a portable copy with no version stamp: it will be remade so it can be tracked.'
        MsgPortableBusy           = 'There are {0} Claude process(es) running from {1}.'
        MsgCannotReplace          = 'The copy cannot be replaced while they are open.'
        MsgCloseAndRetry          = 'Close those Claude windows and try again.'
        MsgKeepUsingCurrent       = 'For now the current copy keeps being used.'
        MsgUpdateFailedBusy       = 'The update failed: Claude is open from the portable copy.'
        MsgCloseAllAndRetry       = 'Close all Claude windows and try again.'
        MsgCopyFailedPerms        = 'The copy failed because of the restrictive WindowsApps permissions.'
        MsgPermsFix1              = 'The fix is to grant read permission to the Administrators group'
        MsgPermsFix2              = 'on that folder.'
        MsgPermsAsk               = 'Grant read to the Administrators group on {0}?'
        MsgPermsCaption           = 'WindowsApps permissions'
        MsgNonInteractive         = 'Non-interactive run: use -GrantWindowsAppsRead to authorize it.'
        MsgCancelled              = 'Cancelled.'
        MsgNeedsAdmin             = 'This step needs Administrator permissions.'
        MsgRunAsAdmin             = 'Close this window and run with "Run as administrator".'
        MsgTakingOwnership        = 'Taking ownership of the package folder...'
        MsgGrantingRead           = 'Granting read to Administrators...'
        MsgPortableReady          = 'Portable copy ready (version {0}): {1}'
        MsgNoPortableNeeded       = 'No portable copy is needed: the executable can be launched directly.'
        MsgVersionedFolder        = 'The executable is inside a folder with a version number.'
        StepPreparingShared       = 'Preparing the shared memory across instances...'
        MsgNoNpxSetup             = 'npx was not found on PATH: the shared MCP servers need Node.js.'
        MsgNodeOutsidePath        = 'Node seems to be at {0} but it is not on PATH.'
        MsgAddToPath              = 'Add that folder to PATH and run again with -SharedMemory.'
        MsgInstallNode            = 'Install Node.js (https://nodejs.org) and run again with -SharedMemory.'
        MsgRestContinues          = 'The rest of the setup continues normally.'
        MsgSharedFolder           = 'Shared folder: {0}'
        MsgNpxAt                  = 'npx: {0}'
        StepGeneratingIcons       = 'Generating per-profile colored icons...'
        MsgIconFailed             = 'Could not generate the icon for ''{0}'': {1}'
        StepInstallingLauncher    = 'Installing launcher (checks for updates before opening)...'
        StepCreatingShortcuts     = 'Creating desktop shortcuts...'
        MsgWhatIfRemoveOld        = 'Whatif: the previous shortcut would be deleted: {0}'
        MsgRemovedOldLnk          = 'Previous shortcut removed: {0}'
        MsgSharedInProfile        = 'Shared memory in "{0}" ({1}).'
        MsgProfileDone            = '{0}  [{1}]'
        MsgNonInteractiveDefaults = 'Non-interactive host: the default profiles are used.'
        DescStore                 = 'Claude Desktop - profile "{0}"{1} (Store package)'
        DescExe                   = 'Claude Desktop - profile "{0}"{1} at {2}'
        DescLauncher              = 'Claude Desktop - profile "{0}"{1} (checks for updates when opening)'
        ErrEmptyProfiles          = 'The profile list is empty.'
        ErrEmptyName              = 'There is an empty profile name in -Profiles.'
        ErrBadChars               = 'The profile name ''{0}'' contains characters that are not valid for a file or folder.'
        ErrBadEdges               = 'The profile name ''{0}'' cannot start/end with a space or end with a dot.'
        ErrDupNames               = 'There are duplicate profile names: {0}'
        ErrRobocopy               = 'robocopy failed (code {0}). Probably because of WindowsApps permissions.'
        ErrRobocopyProfile        = 'robocopy failed copying {0} (code {1}).'
        ErrNoClaudeExe            = 'claude.exe was not found inside {0}'
        ErrNoTargetExe            = 'Could not determine the Claude Desktop executable.'
        MenuProfileLine           = '  [{0}] {1}{2}'
        GuiDeepCleanMsg           = '{0} MB remain in the Cowork VM image.`n`nIt can be deleted, but the app will download it again in full the next time you use Cowork.`n`nDelete it anyway?'
        YesShort                  = 'YES'
        ColorAzul                 = 'blue'
        ColorVerde                = 'green'
        ColorMorado               = 'purple'
        ColorCian                 = 'cyan'
        ColorRosa                 = 'pink'
        ColorAzabache             = 'jet'
        ColorOliva                = 'olive'
        ViaStore                  = 'Store'
        ViaExe                    = 'Exe'
        ViaLauncher               = 'Launcher'
    }
}
function Get-I18nStr {
    param(
        [Parameter(Mandatory)][string]$Key,
        [object[]]$FormatArgs
    )
    $lang = $script:Lang
    if (-not $script:I18n.ContainsKey($lang)) { $lang = 'en' }
    $str = $script:I18n[$lang][$Key]
    if (-not $str) { $str = $script:I18n['en'][$Key] }
    # La tabla usa comillas simples (asi el texto no se interpola por accidente),
    # y ahi `n es backtick+n literal. Se convierte aqui a salto de linea real
    # para los mensajes de varias lineas de los MessageBox.
    if ($str -like '*`n*') { $str = $str.Replace('`n', [Environment]::NewLine) }
    if ($FormatArgs -and $FormatArgs.Count -gt 0) {
        return [string]($str -f $FormatArgs)
    }
    return [string]$str
}

# ---------------------------------------------------------------- helpers ---

$script:GuiLogger = $null

function Write-Step { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan; if ($script:GuiLogger) { & $script:GuiLogger "`r`n==> $m" } }
function Write-Ok   { param([string]$m) Write-Host "    [ok]   $m" -ForegroundColor Green; if ($script:GuiLogger) { & $script:GuiLogger "    [ok]   $m" } }
function Write-Note { param([string]$m) Write-Host "    ->     $m" -ForegroundColor Gray; if ($script:GuiLogger) { & $script:GuiLogger "    ->     $m" } }
function Write-Warn { param([string]$m) Write-Host "    [!]    $m" -ForegroundColor Yellow; if ($script:GuiLogger) { & $script:GuiLogger "    [!]    $m" } }
function Write-Err  { param([string]$m) Write-Host "    [X]    $m" -ForegroundColor Red; if ($script:GuiLogger) { & $script:GuiLogger "    [X]    $m" } }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Convierte "1.10.0", "app-1.9.0-beta", "1.26832.0.0" a [version] comparable.
# Evita el orden lexicografico, que pone 1.9.0 por encima de 1.10.0.
function ConvertTo-SafeVersion {
    param([string]$Text)

    $zero  = [version]'0.0.0.0'
    if ([string]::IsNullOrWhiteSpace($Text)) { return $zero }

    $clean = ($Text -replace '^[^0-9]*', '') -replace '[^0-9\.].*$', ''
    $clean = $clean.Trim('.')
    if ([string]::IsNullOrWhiteSpace($clean) -or $clean -notmatch '\.') { $clean = "$clean.0" }

    $parsed = $zero
    if ([version]::TryParse($clean, [ref]$parsed)) { return $parsed }
    return $zero
}

# --- Iconos de color por perfil ---------------------------------------------
# Se toma el icono real de Claude y se le pega una insignia de color con la
# inicial del perfil, para distinguir los accesos directos de un vistazo.

$script:HomeDir = Join-Path $env:APPDATA 'ClaudeMulti'

# Ojo: nada de coral/naranja. El icono de Claude ya es coral y la insignia
# se volveria invisible sobre el.
$script:Palette = @(
    @{ Clave = 'ColorAzul';     Rgb = @( 37, 118, 208) },
    @{ Clave = 'ColorVerde';    Rgb = @( 34, 150,  94) },
    @{ Clave = 'ColorMorado';   Rgb = @(126,  78, 214) },
    @{ Clave = 'ColorCian';     Rgb = @( 20, 150, 176) },
    @{ Clave = 'ColorRosa';     Rgb = @(209,  56, 130) },
    @{ Clave = 'ColorAzabache'; Rgb = @( 45,  55,  72) },
    @{ Clave = 'ColorOliva';    Rgb = @(107, 142,  35) }
)

function Get-ProfileColor {
    param([int]$Index)
    $script:Palette[$Index % $script:Palette.Count]
}

function Initialize-IconApi {
    if (-not ('ClaudeMulti.IconApi' -as [type])) {
        Add-Type -Namespace 'ClaudeMulti' -Name 'IconApi' -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern int PrivateExtractIcons(string lpszFile, int nIconIndex,
    int cxDesired, int cyDesired, IntPtr[] phicon, int[] piconid, int nIcons, int flags);
[DllImport("user32.dll")]
public static extern bool DestroyIcon(IntPtr hIcon);
'@
    }
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
}

# Extrae el icono grande del .exe (256px). Devuelve $null si no se puede.
function Get-AppIconBitmap {
    param([Parameter(Mandatory)][string]$ExePath, [int]$Size = 256)

    $handles = New-Object IntPtr[] 1
    $ids     = New-Object int[] 1
    $bmp     = $null
    try {
        $n = [ClaudeMulti.IconApi]::PrivateExtractIcons($ExePath, 0, $Size, $Size, $handles, $ids, 1, 0)
        if ($n -gt 0 -and $handles[0] -ne [IntPtr]::Zero) {
            $ico = [System.Drawing.Icon]::FromHandle($handles[0])
            $bmp = New-Object System.Drawing.Bitmap($Size, $Size,
                     [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = 'HighQualityBicubic'
            $g.DrawIcon($ico, (New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)))
            $g.Dispose()
            $ico.Dispose()
        }
    }
    catch { $bmp = $null }
    finally {
        if ($handles[0] -ne [IntPtr]::Zero) { [void][ClaudeMulti.IconApi]::DestroyIcon($handles[0]) }
    }
    return $bmp
}

function New-BadgedBitmap {
    param(
        [System.Drawing.Bitmap]$Base,
        [Parameter(Mandatory)][string]$Letter,
        [Parameter(Mandatory)][int[]]$Rgb,
        [Parameter(Mandatory)][int]$Size
    )

    $color = [System.Drawing.Color]::FromArgb(255, $Rgb[0], $Rgb[1], $Rgb[2])
    $bmp   = New-Object System.Drawing.Bitmap($Size, $Size,
               [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g     = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode   = 'HighQuality'
    $g.TextRenderingHint = 'AntiAliasGridFit'

    if ($Base) {
        $g.DrawImage($Base, (New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)))
    }
    else {
        # Sin icono de origen: cuadrado redondeado del color del perfil.
        $pad  = [int]($Size * 0.06)
        $r    = [int]($Size * 0.22)
        $rect = New-Object System.Drawing.Rectangle($pad, $pad, ($Size - 2 * $pad), ($Size - 2 * $pad))
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc($rect.X, $rect.Y, $r, $r, 180, 90)
        $path.AddArc(($rect.Right - $r), $rect.Y, $r, $r, 270, 90)
        $path.AddArc(($rect.Right - $r), ($rect.Bottom - $r), $r, $r, 0, 90)
        $path.AddArc($rect.X, ($rect.Bottom - $r), $r, $r, 90, 90)
        $path.CloseFigure()
        $fill = New-Object System.Drawing.SolidBrush($color)
        $g.FillPath($fill, $path)
        $fill.Dispose(); $path.Dispose()
    }

    # Insignia circular abajo a la derecha. Grande a proposito: a 32px es lo
    # unico que distingue un acceso directo de otro.
    $d    = [int]($Size * 0.54)
    $x    = $Size - $d
    $y    = $Size - $d
    $ring = [Math]::Max(1, [int]($Size * 0.03))

    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.FillEllipse($white, ($x - $ring), ($y - $ring), ($d + 2 * $ring), ($d + 2 * $ring))
    $brush = New-Object System.Drawing.SolidBrush($color)
    $g.FillEllipse($brush, $x, $y, $d, $d)

    # La letra solo se lee a partir de cierto tamano.
    if ($Size -ge 48) {
        $fontSize = [single]($d * 0.60)
        $font = New-Object System.Drawing.Font('Segoe UI', $fontSize,
                  [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment     = 'Center'
        $fmt.LineAlignment = 'Center'
        $box = New-Object System.Drawing.RectangleF($x, $y, $d, $d)
        $g.DrawString($Letter.ToUpperInvariant(), $font, $white, $box, $fmt)
        $font.Dispose(); $fmt.Dispose()
    }

    $white.Dispose(); $brush.Dispose(); $g.Dispose()
    return $bmp
}

# Escribe un .ico multi-resolucion con frames PNG (soportado desde Vista).
function Save-IcoFile {
    param(
        [Parameter(Mandatory)][System.Drawing.Bitmap[]]$Bitmaps,
        [Parameter(Mandatory)][string]$Path
    )

    $pngs = @()
    foreach ($b in $Bitmaps) {
        $ms = New-Object IO.MemoryStream
        $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngs += , $ms.ToArray()
        $ms.Dispose()
    }

    $fs = [IO.File]::Open($Path, [IO.FileMode]::Create)
    $bw = New-Object IO.BinaryWriter($fs)
    try {
        $bw.Write([uint16]0)             # reservado
        $bw.Write([uint16]1)             # tipo: 1 = icono
        $bw.Write([uint16]$pngs.Count)

        $offset = 6 + (16 * $pngs.Count)
        for ($i = 0; $i -lt $pngs.Count; $i++) {
            $w = $Bitmaps[$i].Width
            $dim = [byte]$(if ($w -ge 256) { 0 } else { $w })   # 0 significa 256
            $bw.Write($dim)              # ancho
            $bw.Write($dim)              # alto
            $bw.Write([byte]0)           # colores de paleta
            $bw.Write([byte]0)           # reservado
            $bw.Write([uint16]1)         # planos
            $bw.Write([uint16]32)        # bits por pixel
            $bw.Write([uint32]$pngs[$i].Length)
            $bw.Write([uint32]$offset)
            $offset += $pngs[$i].Length
        }
        foreach ($p in $pngs) { $bw.Write($p) }
        $bw.Flush()
    }
    finally { $bw.Dispose(); $fs.Dispose() }
}

function New-ProfileIcon {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Index,
        [string]$SourceExe,
        [Parameter(Mandatory)][string]$OutDir
    )

    Initialize-IconApi
    if (-not (Test-Path -LiteralPath $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }

    $color  = Get-ProfileColor -Index $Index
    $letter = $Name.Substring(0, 1)
    $out    = Join-Path $OutDir "$Name.ico"

    $base = $null
    if ($SourceExe -and (Test-Path -LiteralPath $SourceExe)) {
        $base = Get-AppIconBitmap -ExePath $SourceExe -Size 256
    }

    $frames = @()
    foreach ($s in 256, 128, 64, 48, 32, 16) {
        $frames += New-BadgedBitmap -Base $base -Letter $letter -Rgb $color.Rgb -Size $s
    }
    Save-IcoFile -Bitmaps $frames -Path $out
    foreach ($f in $frames) { $f.Dispose() }
    if ($base) { $base.Dispose() }

    return [pscustomobject]@{ Path = $out; Color = (Get-I18nStr $color.Clave) }
}

function Get-ExeVersion {
    param([string]$Path)
    try {
        $fi = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        if ($fi.FileVersion) { return $fi.FileVersion.Trim() }
    } catch { }
    return $null
}

# --- Sello de version de la copia portable -----------------------------------
# Se deja un archivo dentro de PortableDir con la version que se copio. En cada
# ejecucion se compara con la instalada; si cambia, la copia se rehace sola.

$script:StampFile = '.claude-multi.json'

function Get-PortableStamp {
    param([Parameter(Mandatory)][string]$PortablePath)

    $file = Join-Path $PortablePath $script:StampFile
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try {
        $s = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        if (-not $s.version -or -not $s.exe) { return $null }
        return $s
    }
    catch { return $null }
}

# Procesos corriendo desde la copia portable: bloquearian el borrado al actualizar.
function Get-PortableProcess {
    param([Parameter(Mandatory)][string]$PortablePath)

    $base = $PortablePath.TrimEnd('\') + '\'
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) }
        catch { $false }
    }
}

function Set-PortableStamp {
    param(
        [Parameter(Mandatory)][string]$PortablePath,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Exe,
        [string]$Source
    )
    $stamp = [pscustomobject]@{
        version = $Version
        exe     = $Exe
        source  = $Source
        stamped = (Get-Date).ToString('s')
    }
    $file = Join-Path $PortablePath $script:StampFile
    [IO.File]::WriteAllText($file, ($stamp | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}

# Valida nombres de perfil: se usan como nombre de archivo (.lnk) y de carpeta.
function Assert-ProfileNames {
    param([string[]]$Names)

    if (-not $Names -or $Names.Count -eq 0) {
        throw (Get-I18nStr 'ErrEmptyProfiles')
    }

    $bad = [IO.Path]::GetInvalidFileNameChars()
    foreach ($n in $Names) {
        if ([string]::IsNullOrWhiteSpace($n)) {
            throw (Get-I18nStr 'ErrEmptyName')
        }
        if ($n.IndexOfAny($bad) -ge 0) {
            throw (Get-I18nStr 'ErrBadChars' @($n))
        }
        if ($n -ne $n.Trim() -or $n.EndsWith('.')) {
            throw (Get-I18nStr 'ErrBadEdges' @($n))
        }
    }

    $dupes = $Names | Group-Object -Property { $_.ToLowerInvariant() } |
             Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Group[0] }
    if ($dupes) {
        throw (Get-I18nStr 'ErrDupNames' @($dupes -join ', '))
    }

    if ($Names.Count -lt 2 -and -not $Revert) {
        Write-Warn (Get-I18nStr 'MsgOneProfileOnly')
    }
}

function Get-ClaudeInstall {
    # --- 1. Instalacion clasica (installer .exe, tipo Squirrel) --------------
    $bases = @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}) |
             Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $roots = @()
    foreach ($b in $bases) {
        $roots += (Join-Path $b 'AnthropicClaude')
        $roots += (Join-Path $b 'Claude')
    }
    $roots = $roots | Where-Object { Test-Path $_ } | Select-Object -Unique

    foreach ($root in $roots) {
        $direct = Join-Path $root 'claude.exe'
        if (Test-Path $direct) {
            return [pscustomobject]@{
                Exe = $direct; Dir = $root; Mode = 'Direct'; Aumid = $null
                Version = (Get-ExeVersion $direct)
            }
        }
        # Ordenar por version real, no por nombre: app-1.10.0 > app-1.9.0
        $appDirs = Get-ChildItem -LiteralPath $root -Directory -Filter 'app-*' `
                     -ErrorAction SilentlyContinue |
                   Sort-Object -Property @{ Expression = { ConvertTo-SafeVersion $_.Name } } -Descending
        foreach ($d in $appDirs) {
            $exe = Join-Path $d.FullName 'claude.exe'
            if (Test-Path $exe) {
                $v = Get-ExeVersion $exe
                if (-not $v) { $v = ($d.Name -replace '^app-', '') }
                return [pscustomobject]@{
                    Exe = $exe; Dir = $d.FullName; Mode = 'Direct'; Aumid = $null; Version = $v
                }
            }
        }
    }

    # --- 2. Instalacion MSIX (Microsoft Store) ------------------------------
    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        Write-Warn (Get-I18nStr 'MsgNoAppx')
        Write-Note (Get-I18nStr 'MsgNoAppx2')
        Write-Note (Get-I18nStr 'MsgNoAppx3')
        Write-Note (Get-I18nStr 'MsgNoAppx4')
        return $null
    }

    $pkg = Get-AppxPackage -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -match 'Claude' -or $_.Publisher -match 'Anthropic' } |
           Sort-Object -Property @{ Expression = { ConvertTo-SafeVersion $_.Version } } -Descending |
           Select-Object -First 1

    if ($pkg -and $pkg.InstallLocation) {
        $aumid = $null
        try {
            $appId = (Get-AppxPackageManifest $pkg).Package.Applications.Application.Id |
                     Select-Object -First 1
            if ($appId) { $aumid = "$($pkg.PackageFamilyName)!$appId" }
        } catch { }

        $exe = Get-ChildItem -LiteralPath $pkg.InstallLocation -Filter 'claude.exe' `
                 -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1

        return [pscustomobject]@{
            Exe     = $(if ($exe) { $exe.FullName } else { $null })
            Dir     = $pkg.InstallLocation
            Mode    = 'Msix'
            Aumid   = $aumid
            Version = [string]$pkg.Version
        }
    }

    return $null
}

function New-ClaudeShortcut {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Target,
        [string]$Arguments   = '',
        [string]$IconPath,
        [string]$Description = 'Claude Desktop'
    )
    $desktop = [Environment]::GetFolderPath('Desktop')
    $path    = Join-Path $desktop "$Name.lnk"

    if (Test-Path -LiteralPath $path) {
        Write-Warn (Get-I18nStr 'MsgShortcutExists' @($Name))
    }

    if (-not $PSCmdlet.ShouldProcess($path, 'Crear acceso directo')) { return $path }

    $shell = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $lnk   = $shell.CreateShortcut($path)
        $lnk.TargetPath       = $Target
        $lnk.WorkingDirectory = Split-Path -Parent $Target
        $lnk.Arguments        = $Arguments
        $lnk.Description      = $Description
        if ($IconPath) { $lnk.IconLocation = "$IconPath,0" }
        $lnk.Save()
    }
    finally {
        if ($shell) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }
    }
    return $path
}

function Copy-ToPortable {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [switch]$Overwrite
    )

    if ((Test-Path $Destination) -and -not $Overwrite) {
        Write-Note (Get-I18nStr 'MsgReuseCopy')
        return
    }
    if (Test-Path $Destination) {
        if ($PSCmdlet.ShouldProcess($Destination, 'Borrar copia portable anterior')) {
            Write-Note (Get-I18nStr 'MsgDeletingOldCopy')
            Remove-Item -LiteralPath $Destination -Recurse -Force
        }
    }

    if (-not $PSCmdlet.ShouldProcess($Destination, "Copiar Claude Desktop desde $Source")) { return }

    Write-Note (Get-I18nStr 'MsgCopying' @($Source))
    Write-Note (Get-I18nStr 'MsgCopyingTo' @($Destination))
    # /XJ: no seguir junctions ni enlaces duros, que los paquetes MSIX si usan.
    $null = robocopy $Source $Destination /E /XJ /COPY:DAT /DCOPY:DA /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
    $rc = $LASTEXITCODE
    # robocopy usa 0-7 como exito (1 = se copiaron archivos). Se normaliza para
    # que el codigo de salida del script no herede un "1" que parece error.
    $global:LASTEXITCODE = 0
    if ($rc -ge 8) {
        throw (Get-I18nStr 'ErrRobocopy' @($rc))
    }
}

# Escribe servidores MCP en el claude_desktop_config.json de un perfil.
#
# Fusiona por clave en vez de reemplazar el nodo entero: cada cuenta puede
# tener sus propios MCP servers y no hay por que pisarselos para sembrar uno.
# El resto del archivo (preferences, coworkUserFilesPath...) queda intacto.
function Merge-McpServers {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$DestinationDir,
        [Parameter(Mandatory)][hashtable]$Servers,
        [switch]$Overwrite
    )

    if ($Servers.Count -eq 0) { return @() }

    $dst = Join-Path $DestinationDir 'claude_desktop_config.json'
    $out = [pscustomobject]@{}
    if (Test-Path -LiteralPath $dst) {
        try { $out = Get-Content -LiteralPath $dst -Raw | ConvertFrom-Json }
        catch {
            Write-Warn (Get-I18nStr 'MsgBadJsonKeep' @($dst))
            return @()
        }
    }

    $merged  = [ordered]@{}
    $existing = @()
    if ($out.PSObject.Properties.Name -contains 'mcpServers' -and $out.mcpServers) {
        foreach ($prop in $out.mcpServers.PSObject.Properties) {
            $merged[$prop.Name] = $prop.Value
            $existing += $prop.Name
        }
    }

    $written = @()
    foreach ($key in $Servers.Keys) {
        if (($existing -contains $key) -and -not $Overwrite) {
            Write-Note (Get-I18nStr 'MsgServerKept' @($key, $DestinationDir))
            continue
        }
        $merged[$key] = $Servers[$key]
        $written += $key
    }
    if ($written.Count -eq 0) { return @() }

    if (-not $PSCmdlet.ShouldProcess($dst, "Escribir $($written.Count) MCP server(s): $($written -join ', ')")) {
        return $written
    }

    if ($out.PSObject.Properties.Name -contains 'mcpServers') { $out.mcpServers = $merged }
    else { $out | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue $merged }

    if (-not (Test-Path -LiteralPath $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }
    # Sin BOM: el parser JSON de la app no lo tolera.
    $json = $out | ConvertTo-Json -Depth 32
    [IO.File]::WriteAllText($dst, $json, (New-Object Text.UTF8Encoding($false)))
    return $written
}

function Remove-McpServers {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$DestinationDir,
        [Parameter(Mandatory)][string[]]$Names
    )

    $dst = Join-Path $DestinationDir 'claude_desktop_config.json'
    if (-not (Test-Path -LiteralPath $dst)) { return @() }
    try { $out = Get-Content -LiteralPath $dst -Raw | ConvertFrom-Json } catch { return @() }
    if (-not ($out.PSObject.Properties.Name -contains 'mcpServers') -or -not $out.mcpServers) { return @() }

    $kept    = [ordered]@{}
    $removed = @()
    foreach ($prop in $out.mcpServers.PSObject.Properties) {
        if ($Names -contains $prop.Name) { $removed += $prop.Name }
        else { $kept[$prop.Name] = $prop.Value }
    }
    if ($removed.Count -eq 0) { return @() }
    if (-not $PSCmdlet.ShouldProcess($dst, "Quitar MCP server(s): $($removed -join ', ')")) { return $removed }

    $out.mcpServers = $kept
    $json = $out | ConvertTo-Json -Depth 32
    [IO.File]::WriteAllText($dst, $json, (New-Object Text.UTF8Encoding($false)))
    return $removed
}

function Copy-McpConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$DestinationDir,
        [switch]$Overwrite
    )

    $srcDir = Join-Path $env:APPDATA 'Claude'
    $src    = Join-Path $srcDir 'claude_desktop_config.json'
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Warn (Get-I18nStr 'MsgNoSrcConfig' @($srcDir))
        return
    }

    # claude_desktop_config.json mezcla los MCP servers con preferencias de UI
    # ligadas a la cuenta. Se extrae SOLO el nodo mcpServers para no arrastrar
    # ajustes de una cuenta a otra.
    try {
        $srcJson = Get-Content -LiteralPath $src -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warn (Get-I18nStr 'MsgBadSrcJson' @($src))
        return
    }

    $servers = @{}
    if ($srcJson.PSObject.Properties.Name -contains 'mcpServers' -and $srcJson.mcpServers) {
        foreach ($prop in $srcJson.mcpServers.PSObject.Properties) { $servers[$prop.Name] = $prop.Value }
    }

    if ($servers.Count -eq 0) {
        Write-Note (Get-I18nStr 'MsgNoMcpsToCopy')
        return
    }

    $written = @(Merge-McpServers -DestinationDir $DestinationDir -Servers $servers -Overwrite:$Overwrite)
    if ($written.Count -gt 0) {
        Write-Note (Get-I18nStr 'MsgMcpsCopied' @($($written -join ', '), $DestinationDir))
    }
}

# --- Memoria compartida entre instancias -------------------------------------
#
# La memoria del CHAT de Claude Desktop vive en el servidor, atada a la cuenta:
# no hay archivo local que copiar y no se puede compartir entre perfiles.
#
# Lo que si se puede es darle a las tres cuentas los MISMOS servidores MCP
# apuntando a una carpeta comun. Cada instancia lee y escribe ahi, asi que el
# contexto viaja entre cuentas aunque las conversaciones sigan separadas.
#
# (Aparte de esto, %USERPROFILE%\.claude ya es comun a todas las instancias:
# --user-data-dir solo redirige la carpeta de Electron, no el HOME. La memoria
# de Claude Code, CLAUDE.md y las skills ya se comparten sin hacer nada.)

# Lanzar los servidores en Windows tiene exactamente una forma que funciona.
# Probadas las cinco candidatas contra un handshake MCP real:
#
#   cmd.exe /c npx -y <pkg>            OK
#   cmd.exe /c "<ruta>\npx.cmd" ...    falla: cmd se come las comillas de una
#                                      ruta con espacios ("C:Program" ...)
#   <ruta>\npx.cmd  (sin shell)        EINVAL: desde el parche de
#                                      CVE-2024-27980 Node no lanza .cmd
#   <ruta>\npx.cmd  (con shell)        falla igual que la segunda
#   npx  (sin shell)                   ENOENT
#
# Por eso la config se escribe como "cmd.exe /c npx ...", que es ademas la
# forma que documenta MCP para Windows. Depende del PATH, no de una ruta.
function Resolve-NpxCommand {
    foreach ($n in @('npx.cmd', 'npx')) {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c -and $c.Source) { return $c.Source }
    }
    return $null
}

# Solo para dar un error util: Node instalado pero fuera del PATH.
function Find-NpxOutsidePath {
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:APPDATA, $env:LOCALAPPDATA)) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        foreach ($rel in @('nodejs\npx.cmd', 'npm\npx.cmd')) {
            $try = Join-Path $base $rel
            if (Test-Path -LiteralPath $try) { return $try }
        }
    }
    return $null
}

$script:SharedReadme = @'
# Memoria compartida entre las instancias de Claude Desktop

Esta carpeta la leen y escriben TODAS las cuentas configuradas con
Setup-ClaudeMulti. Es el unico contexto que viaja de una instancia a otra.

- `memory.json` lo gestiona el servidor MCP `shared-memory`. No lo edites a
  mano mientras haya ventanas de Claude abiertas.
- El resto de archivos de esta carpeta los ve el servidor `shared-files`:
  cualquier `.md` que dejes aqui queda disponible para las tres cuentas.

Para darle contexto de un proyecto a todas tus cuentas, deja aqui un `.md`
y pideselo por su nombre en el chat.

Lo que NO se comparte: la memoria propia del chat de Claude (vive en el
servidor, atada a cada cuenta), el historial de conversaciones y los
proyectos. Eso es por diseno: son cuentas distintas.
'@

function Get-SharedMemoryServers {
    param([Parameter(Mandatory)][string]$SharedDir)

    $cmdExe = Join-Path $env:WINDIR 'System32\cmd.exe'
    return @{
        'shared-memory' = [ordered]@{
            command = $cmdExe
            args    = @('/c', 'npx', '-y', '@modelcontextprotocol/server-memory')
            env     = [ordered]@{ MEMORY_FILE_PATH = (Join-Path $SharedDir 'memory.json') }
        }
        'shared-files' = [ordered]@{
            command = $cmdExe
            args    = @('/c', 'npx', '-y', '@modelcontextprotocol/server-filesystem', $SharedDir)
        }
    }
}

function Initialize-SharedMemory {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][string]$SharedDir)

    if (-not (Test-Path -LiteralPath $SharedDir)) {
        if ($PSCmdlet.ShouldProcess($SharedDir, 'Crear carpeta de memoria compartida')) {
            New-Item -ItemType Directory -Path $SharedDir -Force | Out-Null
        }
    }
    # Solo se siembra si no existe: es un archivo que el usuario puede editar.
    $readme = Join-Path $SharedDir 'LEEME.md'
    if (-not (Test-Path -LiteralPath $readme)) {
        if ($PSCmdlet.ShouldProcess($readme, 'Escribir nota de la carpeta compartida')) {
            [IO.File]::WriteAllText($readme, $script:SharedReadme, (New-Object Text.UTF8Encoding($false)))
        }
    }
}

# --- Lanzador por perfil -----------------------------------------------------
# Los accesos directos no apuntan al .exe: apuntan a un lanzador que primero
# comprueba si Claude se actualizo y, si hace falta, refresca la copia portable.

$script:LauncherPs1 = @'
# Lanzador de un perfil de Claude Desktop.
# Comprueba si hay una version nueva de Claude antes de abrir la ventana.
# Lo genera Setup-ClaudeMulti.ps1: no lo edites a mano, se sobrescribe.
param([Parameter(Mandatory)][string]$ProfileName)

$ErrorActionPreference = 'Stop'
$base    = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgFile = Join-Path $base 'config.json'

function Show-Error {
    param([string]$Message)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show($Message, 'Claude Multi Instancia',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    } catch { Write-Host $Message }
    exit 1
}

if (-not (Test-Path -LiteralPath $cfgFile)) {
    Show-Error "No se encontro config.json en $base.`n`nVuelve a ejecutar Setup-ClaudeMulti.bat."
}
$cfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
$prof = $cfg.profiles | Where-Object { $_.name -eq $ProfileName } | Select-Object -First 1
if (-not $prof) {
    Show-Error "El perfil '$ProfileName' ya no esta configurado.`n`nVuelve a ejecutar Setup-ClaudeMulti.bat."
}

# Perfil por defecto sobre el paquete de la Store: Windows lo actualiza solo.
if ($prof.useStore -and $cfg.aumid) {
    Start-Process 'explorer.exe' "shell:AppsFolder\$($cfg.aumid)"
    exit 0
}

function Get-InstalledVersion {
    if ($cfg.mode -eq 'Msix') {
        $pkg = Get-AppxPackage -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -match 'Claude' -or $_.Publisher -match 'Anthropic' } |
               Select-Object -First 1
        if ($pkg) { return [string]$pkg.Version }
        return $null
    }
    try {
        $fi = [Diagnostics.FileVersionInfo]::GetVersionInfo($cfg.sourceExe)
        if ($fi.FileVersion) { return $fi.FileVersion.Trim() }
    } catch { }
    return $null
}

function Test-PortableBusy {
    if (-not $cfg.portableDir) { return $false }
    $prefix = $cfg.portableDir.TrimEnd('\') + '\'
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }
        catch { $false }
    }
    return (@($procs).Count -gt 0)
}

# --- Comprobar si hay version nueva -----------------------------------------
$exe    = $prof.exe
$update = $false

if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
    $update = $true
}
elseif ($cfg.mode -eq 'Msix') {
    $stampFile = Join-Path $cfg.portableDir '.claude-multi.json'
    $stampVer  = $null
    if (Test-Path -LiteralPath $stampFile) {
        try { $stampVer = (Get-Content -LiteralPath $stampFile -Raw | ConvertFrom-Json).version } catch { }
    }
    $installed = Get-InstalledVersion
    if ($installed -and $stampVer -and $installed -ne $stampVer) { $update = $true }
}

if ($update -and (Test-PortableBusy)) {
    # No se puede reemplazar la copia con Claude abierto desde ella.
    $update = $false
}

if ($update) {
    $setup = Join-Path $base 'Setup-ClaudeMulti.ps1'
    if (Test-Path -LiteralPath $setup) {
        # Start-Process une los argumentos con espacios y NO los entrecomilla:
        # hay que citar a mano o una ruta como "C:\Users\A Nombre\..." se parte.
        $names = @($cfg.profiles | ForEach-Object { '"' + $_.name + '"' })
        $argv  = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$setup`"", '-Profiles') + $names
        # Sin esto la actualizacion recopiaria al PortableDir por defecto y
        # dejaria dos copias, con el config apuntando a la equivocada.
        if ($cfg.portableDir) { $argv += @('-PortableDir', "`"$($cfg.portableDir)`"") }
        if ($cfg.copyMcp)     { $argv += '-CopyMcpConfig' }
        if ($cfg.sharedMemory) {
            $argv += '-SharedMemory'
            if ($cfg.sharedDir) { $argv += @('-SharedDir', "`"$($cfg.sharedDir)`"") }
        }
        # Ventana visible: la copia tarda y el usuario debe ver que pasa algo.
        Start-Process 'powershell.exe' -ArgumentList $argv -Wait
        try {
            $cfg  = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
            $prof = $cfg.profiles | Where-Object { $_.name -eq $ProfileName } | Select-Object -First 1
            if ($prof) { $exe = $prof.exe }
        } catch { }
    }
}

if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
    Show-Error "No se encontro el ejecutable de Claude:`n$exe`n`nEjecuta Setup-ClaudeMulti.bat para repararlo."
}

Start-Process -FilePath $exe -ArgumentList "--user-data-dir=`"$($prof.dataDir)`""
'@

# wscript lanza PowerShell oculto: sin parpadeo de consola negra al abrir.
$script:LauncherVbs = @'
Option Explicit
Dim sh, fso, base, ps1, prof, cmd
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)
ps1  = base & "\Launch-ClaudeProfile.ps1"
If WScript.Arguments.Count > 0 Then
    prof = WScript.Arguments(0)
Else
    prof = ""
End If
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """ -ProfileName """ & prof & """"
sh.Run cmd, 0, False
'@

function Install-Launcher {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][string]$HomePath)

    if (-not (Test-Path -LiteralPath $HomePath)) {
        New-Item -ItemType Directory -Path $HomePath -Force | Out-Null
    }
    if (-not $PSCmdlet.ShouldProcess($HomePath, 'Instalar lanzador de perfiles')) { return }

    $enc = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $HomePath 'Launch-ClaudeProfile.ps1'), $script:LauncherPs1, $enc)
    [IO.File]::WriteAllText((Join-Path $HomePath 'launch.vbs'), $script:LauncherVbs, $enc)

    # Copia del propio setup, para que el lanzador pueda actualizar aunque
    # muevas o borres la carpeta del repositorio.
    $self = $PSCommandPath
    $dest = Join-Path $HomePath 'Setup-ClaudeMulti.ps1'
    if ($self -and (Test-Path -LiteralPath $self)) {
        if ([IO.Path]::GetFullPath($self) -ne [IO.Path]::GetFullPath($dest)) {
            Copy-Item -LiteralPath $self -Destination $dest -Force
        }
    }
}

function Write-LauncherConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$HomePath,
        [Parameter(Mandatory)]$Config
    )
    if (-not $PSCmdlet.ShouldProcess((Join-Path $HomePath 'config.json'), 'Escribir configuracion')) { return }
    $json = $Config | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText((Join-Path $HomePath 'config.json'), $json, (New-Object Text.UTF8Encoding($false)))
}

function Get-ProfileLabel {
    param([string]$Name, [int]$Index)
    $note = Get-ProfileNote -Name $Name
    if ($Index -eq 0) {
        if ($note) { return (Get-I18nStr 'ProfileLabelOriginalNote' @($Name, $note)) }
        return (Get-I18nStr 'ProfileLabelOriginal' @($Name))
    }
    if ($note) { return (Get-I18nStr 'ProfileLabelExtraNote' @($Name, $note)) }
    return (Get-I18nStr 'ProfileLabelExtra' @($Name))
}

# Accesos directos que pertenecen a un perfil.
#
# NO se puede filtrar con el comodin "Claude - $n*.lnk": tambien engancha a los
# hermanos con prefijo comun (Cuenta1 se llevaria a Cuenta10; Trabajo, a
# Trabajo2). Pero tampoco basta comparar contra etiquetas fijas, porque la nota
# pudo cambiar y hay que reconocer el acceso viejo para reemplazarlo.
#
# Se listan todos los "Claude - *.lnk", se descompone el nombre en perfil+nota
# y se compara el PERFIL de forma exacta.
# El sufijo va en los DOS idiomas a proposito: si alguien cambia -Language,
# los accesos directos creados antes tienen que seguir reconociendose para
# poder reemplazarlos, o el Escritorio se llena de huerfanos.
$script:CurrentProfileSuffixes = @('perfil actual', 'current profile')
$script:ShortcutRegex = '^Claude - (?<name>.+?)(?: \((?<note>[^)]*)\))?(?: \((?:' +
                        (($script:CurrentProfileSuffixes | ForEach-Object { [regex]::Escape($_) }) -join '|') +
                        ')\))?$'

function Get-ProfileShortcutPaths {
    param([Parameter(Mandatory)][string]$Name)

    $desktop = [Environment]::GetFolderPath('Desktop')
    Get-ChildItem -LiteralPath $desktop -Filter 'Claude - *.lnk' -ErrorAction SilentlyContinue |
        Where-Object {
            $m = [regex]::Match($_.BaseName, $script:ShortcutRegex)
            $m.Success -and $m.Groups['name'].Value -eq $Name
        } |
        ForEach-Object { $_.FullName }
}

function Invoke-Revert {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string[]]$Names,
        [Parameter(Mandatory)][string]$PortablePath,
        [switch]$SkipConfirm
    )

    Write-Step (Get-I18nStr 'StepDeletingShortcuts')
    foreach ($n in $Names) {
        foreach ($lnk in (Get-ProfileShortcutPaths -Name $n)) {
            if (Test-Path -LiteralPath $lnk) {
                if ($PSCmdlet.ShouldProcess($lnk, 'Eliminar acceso directo')) {
                    Remove-Item -LiteralPath $lnk -Force
                    Write-Ok (Get-I18nStr 'MsgDeleted' @($(Split-Path -Leaf $lnk)))
                }
            }
        }
    }

    # El primer perfil usa %APPDATA%\Claude, que NUNCA se toca.
    Write-Step (Get-I18nStr 'StepDeletingProfileData')
    $dataDirs = @()
    foreach ($n in ($Names | Select-Object -Skip 1)) {
        $d = Join-Path $env:APPDATA "Claude-$n"
        if (Test-Path -LiteralPath $d) { $dataDirs += $d }
    }

    if ($dataDirs.Count -eq 0) {
        Write-Note (Get-I18nStr 'MsgNoExtraData')
    }
    else {
        $go = $SkipConfirm
        if (-not $go) {
            $list = ($dataDirs -join "`n      ")
            try {
                $go = $PSCmdlet.ShouldContinue(
                    "Se van a borrar estas carpetas y con ellas la sesion y los MCPs de esos perfiles:`n      $list`n`nContinuar?",
                    'Borrar datos de perfiles')
            }
            catch {
                # Host no interactivo: no se puede confirmar un borrado de datos.
                Write-Warn (Get-I18nStr 'MsgNoConfirmHost')
                Write-Note (Get-I18nStr 'MsgAddForce')
                $go = $false
            }
        }
        if ($go) {
            foreach ($d in $dataDirs) {
                if ($PSCmdlet.ShouldProcess($d, 'Eliminar carpeta de datos del perfil')) {
                    Remove-Item -LiteralPath $d -Recurse -Force
                    Write-Ok (Get-I18nStr 'MsgDeleted' @($d))
                }
            }
        }
        else {
            Write-Note (Get-I18nStr 'MsgDataKept')
        }
    }

    # Las carpetas de los perfiles extra ya se fueron con su config dentro,
    # pero el primero vive en %APPDATA%\Claude y ese no se borra nunca: hay
    # que sacarle a mano los servidores que le sembro -SharedMemory.
    $sharedDirSaved = $null
    $cfgFile = Join-Path $script:HomeDir 'config.json'
    if (Test-Path -LiteralPath $cfgFile) {
        try {
            $cfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
            if ($cfg.sharedMemory) { $sharedDirSaved = $cfg.sharedDir }
        } catch { }
    }
    if ($sharedDirSaved) {
        Write-Step (Get-I18nStr 'StepRemovingShared')
        $gone = @(Remove-McpServers -DestinationDir (Join-Path $env:APPDATA 'Claude') `
                    -Names @('shared-memory', 'shared-files'))
        if ($gone.Count -gt 0) { Write-Ok (Get-I18nStr 'MsgRemoved' @($gone -join ', ')) }
        else { Write-Note (Get-I18nStr 'MsgNoSharedToRemove') }
    }

    Write-Step (Get-I18nStr 'StepDeletingLauncher')
    if (Test-Path -LiteralPath $script:HomeDir) {
        if ($PSCmdlet.ShouldProcess($script:HomeDir, 'Eliminar lanzador, iconos y configuracion')) {
            Remove-Item -LiteralPath $script:HomeDir -Recurse -Force
            Write-Ok (Get-I18nStr 'MsgDeleted' @($script:HomeDir))
        }
    }
    else {
        Write-Note (Get-I18nStr 'MsgDoesNotExist' @($script:HomeDir))
    }

    Write-Step (Get-I18nStr 'StepDeletingPortable')
    if (Test-Path -LiteralPath $PortablePath) {
        if ($PSCmdlet.ShouldProcess($PortablePath, 'Eliminar copia portable')) {
            Remove-Item -LiteralPath $PortablePath -Recurse -Force
            Write-Ok (Get-I18nStr 'MsgDeleted' @($PortablePath))
        }
    }
    else {
        Write-Note (Get-I18nStr 'MsgDoesNotExist' @($PortablePath))
    }

    Write-Host ''
    Write-Ok (Get-I18nStr 'MsgUntouchedMain' @($(Join-Path $env:APPDATA 'Claude')))
    if ($sharedDirSaved -and (Test-Path -LiteralPath $sharedDirSaved)) {
        Write-Ok (Get-I18nStr 'MsgUntouchedShared' @($sharedDirSaved))
    }
}

function Get-ConfiguredProfiles {
    $cfgFile = Join-Path $script:HomeDir 'config.json'
    if (Test-Path -LiteralPath $cfgFile) {
        try {
            $cfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
            if ($cfg.profiles) {
                $names = @($cfg.profiles | ForEach-Object { $_.name })
                if ($names.Count -gt 0) { return $names }
            }
        } catch { }
    }
    return @()
}

function Get-ConfiguredProfileObjects {
    $cfgFile = Join-Path $script:HomeDir 'config.json'
    if (Test-Path -LiteralPath $cfgFile) {
        try {
            $cfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
            if ($cfg.profiles) {
                return @($cfg.profiles)
            }
        } catch { }
    }
    return @()
}

function Get-ProfileNote {
    param([string]$Name)
    $profs = Get-ConfiguredProfileObjects
    $found = $profs | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if ($found -and $found.note) { return $found.note }

    # Respaldo: leer la nota del nombre del acceso directo. Cubre el caso de un
    # config.json regenerado sin notas (por ejemplo una ejecucion con menos
    # -Profiles), para no perder los correos al reconstruir los accesos.
    foreach ($lnk in (Get-ProfileShortcutPaths -Name $Name)) {
        $m = [regex]::Match([IO.Path]::GetFileNameWithoutExtension($lnk), $script:ShortcutRegex)
        if ($m.Success -and $m.Groups['note'].Success) {
            $note = $m.Groups['note'].Value
            if ($note -and ($script:CurrentProfileSuffixes -notcontains $note)) { return $note }
        }
    }
    return $null
}

function Edit-ProfileNotes {
    $profs = Get-ConfiguredProfileObjects
    if ($profs.Count -eq 0) {
        Write-Warn (Get-I18nStr 'HcNoProfiles')
        return
    }

    Write-Host ''
    Write-Host (Get-I18nStr 'EditNotesTitle') -ForegroundColor Cyan
    for ($i = 0; $i -lt $profs.Count; $i++) {
        $noteStr = $(if ($profs[$i].note) { " ($($profs[$i].note))" } else { '' })
        Write-Host (Get-I18nStr 'MenuProfileLine' @(($i+1), $profs[$i].name, $noteStr))
    }
    Write-Host ''
    $sel = Read-Host (Get-I18nStr 'AskProfileToEdit')
    [int]$idx = 0
    if ([int]::TryParse($sel, [ref]$idx) -and $idx -ge 1 -and $idx -le $profs.Count) {
        $targetProf = $profs[$idx - 1]
        $newNote = Read-Host (Get-I18nStr 'AskNoteFor' @($targetProf.name))
        if ($targetProf.PSObject.Properties.Name -contains 'note') {
            $targetProf.note = $newNote.Trim()
        } else {
            $targetProf | Add-Member -NotePropertyName 'note' -NotePropertyValue $newNote.Trim()
        }

        $cfgFile = Join-Path $script:HomeDir 'config.json'
        if (Test-Path -LiteralPath $cfgFile) {
            try {
                $cfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
                $cfg.profiles = $profs
                $json = $cfg | ConvertTo-Json -Depth 8
                [IO.File]::WriteAllText($cfgFile, $json, (New-Object Text.UTF8Encoding($false)))
                Write-Ok (Get-I18nStr 'MsgNoteUpdated' @($($targetProf.name)))
            } catch {
                Write-Warn (Get-I18nStr 'MsgCfgUpdateFailed' @($($_.Exception.Message)))
            }
        }
    }
}

function Invoke-HealthCheck {
    Write-Host ''
    Write-Host '=============================================================' -ForegroundColor White
    Write-Host (Get-I18nStr 'HcTitle') -ForegroundColor White
    Write-Host '=============================================================' -ForegroundColor White

    $install = Get-ClaudeInstall
    if ($install) {
        Write-Ok (Get-I18nStr 'HcMainExe' @($($install.Exe)))
        Write-Ok (Get-I18nStr 'MsgInstallMode' @($($install.Mode)))
        if ($install.Version) { Write-Ok (Get-I18nStr 'MsgInstalledVer' @($install.Version)) }
    } else {
        Write-Err (Get-I18nStr 'HcNoInstall')
    }

    if (Test-Path -LiteralPath $script:HomeDir) {
        Write-Ok (Get-I18nStr 'HcLauncherDir' @($script:HomeDir))
    } else {
        Write-Warn (Get-I18nStr 'HcNoLauncherDir' @($script:HomeDir))
    }

    $profs = Get-ConfiguredProfileObjects
    if ($profs.Count -gt 0) {
        Write-Host "`n$(Get-I18nStr 'HcProfileStates')" -ForegroundColor Cyan
        foreach ($p in $profs) {
            $n = $p.name
            $dataDir = $p.dataDir
            $exists = Test-Path -LiteralPath $dataDir
            $sizeMB = 0
            if ($exists) {
                try {
                    $bytes = (Get-ChildItem -LiteralPath $dataDir -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    $sizeMB = [math]::Round(($bytes / 1MB), 1)
                } catch { }
            }
            # No se puede componer el nombre a mano: el acceso real lleva la
            # nota dentro ("Claude - Cuenta1 (correo@x.com) (perfil actual)").
            $hasLnk = @(Get-ProfileShortcutPaths -Name $n).Count -gt 0

            $noteStr = $(if ($p.note) { " ($($p.note))" } else { '' })
            $statusStr = $(if ($exists) { "$sizeMB MB" } else { Get-I18nStr 'HcNotCreated' })
            $lnkStr    = $(if ($hasLnk) { Get-I18nStr 'HcLnkOk' } else { Get-I18nStr 'HcLnkMissing' })

            if ($exists -and $hasLnk) {
                Write-Ok (Get-I18nStr 'HcProfileLine' @($n, $noteStr, $statusStr, $lnkStr))
            } else {
                Write-Warn (Get-I18nStr 'HcProfileLine' @($n, $noteStr, $statusStr, $lnkStr))
            }
        }
    } else {
        Write-Note (Get-I18nStr 'HcNoProfiles')
    }

    # config.json es la unica lista de perfiles, pero una ejecucion con menos
    # -Profiles la reescribe y deja carpetas de datos sin dueno: no aparecen en
    # la GUI ni en el menu, y -Revert no las limpia.
    $known   = @($profs | ForEach-Object { "Claude-$($_.name)" })
    $orphans = @(Get-ChildItem -LiteralPath $env:APPDATA -Filter 'Claude-*' -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $known -notcontains $_.Name })
    if ($orphans.Count -gt 0) {
        Write-Host "`n$(Get-I18nStr 'HcOrphans')" -ForegroundColor Yellow
        foreach ($o in $orphans) {
            $n = $o.Name -replace '^Claude-', ''
            Write-Warn (Get-I18nStr 'PairArrow' @($n, $o.FullName))
        }
        Write-Note (Get-I18nStr 'HcOrphanHint1')
        Write-Note (Get-I18nStr 'HcOrphanHint2')
    }

    Write-Host "`n$(Get-I18nStr 'HcSharedTitle')" -ForegroundColor Cyan
    $cfgFile   = Join-Path $script:HomeDir 'config.json'
    $sharedCfg = $null
    if (Test-Path -LiteralPath $cfgFile) {
        try { $sharedCfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json } catch { }
    }
    if ($sharedCfg -and $sharedCfg.sharedMemory) {
        $sd = $sharedCfg.sharedDir
        if (Test-Path -LiteralPath $sd) {
            $memFile = Join-Path $sd 'memory.json'
            $memKB   = $(if (Test-Path -LiteralPath $memFile) { [math]::Round((Get-Item -LiteralPath $memFile).Length / 1KB, 1) } else { 0 })
            $docs    = @(Get-ChildItem -LiteralPath $sd -Filter '*.md' -File -ErrorAction SilentlyContinue).Count
            Write-Ok (Get-I18nStr 'HcSharedOn' @($sd, $memKB, $docs))
        }
        else {
            Write-Warn (Get-I18nStr 'HcSharedNoDir' @($sd))
        }
        # Se comprueba perfil por perfil: alguien pudo quitar el server a mano.
        foreach ($p in $profs) {
            $cfgMcp = Join-Path $p.dataDir 'claude_desktop_config.json'
            $has    = $false
            if (Test-Path -LiteralPath $cfgMcp) {
                try {
                    $j = Get-Content -LiteralPath $cfgMcp -Raw | ConvertFrom-Json
                    $has = ($j.mcpServers -and (@($j.mcpServers.PSObject.Properties.Name) -contains 'shared-memory'))
                } catch { }
            }
            if ($has) { Write-Ok (Get-I18nStr 'HcSharedConnected' @($p.name)) }
            else       { Write-Warn (Get-I18nStr 'HcSharedMissing' @($p.name)) }
        }
        if (-not (Resolve-NpxCommand)) {
            Write-Err (Get-I18nStr 'HcNoNpx')
        }
    }
    else {
        Write-Note (Get-I18nStr 'HcSharedOff')
    }

    $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'claude' })
    Write-Host "`n$(Get-I18nStr 'HcRunningProcs' @($procs.Count))" -ForegroundColor Gray
    Write-Host ''
}

# Carpetas regenerables dentro de una carpeta de datos de perfil. Sirven para
# dos cosas: son lo que borra el limpiador y lo que NO entra en el backup.
#
# vm_bundles (la imagen de la VM de Cowork) puede pasar de 9 GB, y claude-code
# guarda un claude.exe de ~300 MB por cada version que haya pasado por ahi.
# Ninguna de las dos aporta nada a un respaldo: la app las vuelve a bajar.
$script:DisposableDirs = @(
    'Cache', 'Code Cache', 'GPUCache',
    'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache',
    'blob_storage', 'Crashpad', 'logs', 'fcache',
    'Shared Dictionary', 'pending-uploads', 'sentry'
)

# Tambien regenerables, pero volver a bajarlas cuesta GB de descarga. Fuera
# del backup siempre; el limpiador solo las toca si se lo piden con -Deep.
$script:HeavyRegenerableDirs = @('vm_bundles', 'claude-code-vm')

# Versiones viejas del binario embebido de Claude Code: se conserva la mas
# reciente de cada perfil (la que la app esta usando) y se borran las demas.
function Remove-StaleClaudeCodeBinaries {
    param([Parameter(Mandatory)][string]$ProfileDir)

    $ccDir = Join-Path $ProfileDir 'claude-code'
    if (-not (Test-Path -LiteralPath $ccDir)) { return 0 }

    $versions = @(Get-ChildItem -LiteralPath $ccDir -Directory -ErrorAction SilentlyContinue |
                  Sort-Object { ConvertTo-SafeVersion $_.Name })
    if ($versions.Count -le 1) { return 0 }

    [long]$freed = 0
    foreach ($v in $versions[0..($versions.Count - 2)]) {
        try {
            $bytes = (Get-ChildItem -LiteralPath $v.FullName -Recurse -ErrorAction SilentlyContinue |
                      Measure-Object -Property Length -Sum).Sum
            Remove-Item -LiteralPath $v.FullName -Recurse -Force -ErrorAction Stop
            $freed += $bytes
            Write-Note (Get-I18nStr 'MsgOldBinaryDeleted' @($(Split-Path -Leaf $ProfileDir), $($v.Name)))
        } catch { }
    }
    return $freed
}

function Get-DirectorySize {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [long]0 }
    try {
        $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        if ($sum) { return [long]$sum }
    } catch { }
    return [long]0
}

function Clear-ProfileCache {
    param([switch]$Deep)
    Write-Host ''
    Write-Host (Get-I18nStr 'CacheTitle') -ForegroundColor Cyan

    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'claude' }
    if ($procs.Count -gt 0) {
        Write-Warn (Get-I18nStr 'MsgProcsRunning' @($($procs.Count)))
        Write-Warn (Get-I18nStr 'MsgCloseBeforeClean')
        return
    }

    $targets = @()
    $mainDir = Join-Path $env:APPDATA 'Claude'
    if (Test-Path -LiteralPath $mainDir) { $targets += $mainDir }
    Get-ChildItem -LiteralPath $env:APPDATA -Filter 'Claude-*' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $targets += $_.FullName
    }

    if ($targets.Count -eq 0) {
        Write-Note (Get-I18nStr 'MsgNoProfilesToClean')
        return
    }

    $toClear = @($script:DisposableDirs)
    if ($Deep) { $toClear += $script:HeavyRegenerableDirs }

    [long]$totalFreedBytes = 0
    [long]$heavyPending    = 0

    foreach ($dir in $targets) {
        foreach ($sub in $toClear) {
            $path = Join-Path $dir $sub
            if (Test-Path -LiteralPath $path) {
                try {
                    $bytes = Get-DirectorySize -Path $path
                    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
                    $totalFreedBytes += $bytes
                } catch { }
            }
        }
        $totalFreedBytes += Remove-StaleClaudeCodeBinaries -ProfileDir $dir

        if (-not $Deep) {
            foreach ($sub in $script:HeavyRegenerableDirs) {
                $heavyPending += Get-DirectorySize -Path (Join-Path $dir $sub)
            }
        }
    }

    $freedMB = [math]::Round(($totalFreedBytes / 1MB), 2)
    Write-Ok (Get-I18nStr 'MsgCleanDone' @($freedMB))

    if ($heavyPending -gt 0) {
        $heavyMB = [math]::Round(($heavyPending / 1MB), 0)
        Write-Note (Get-I18nStr 'MsgHeavyPending' @($heavyMB, $($script:HeavyRegenerableDirs -join ', ')))
        Write-Note (Get-I18nStr 'MsgHeavyHint')
    }
    Write-Host ''
    return $heavyPending
}

function Export-ProfileBackup {
    param([string]$DestinationZip)

    Write-Host ''
    Write-Host (Get-I18nStr 'BackupTitle') -ForegroundColor Cyan

    $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    if ([string]::IsNullOrWhiteSpace($DestinationZip)) {
        $DestinationZip = Join-Path ([Environment]::GetFolderPath('Desktop')) "ClaudeMulti_Backup_$timestamp.zip"
    }
    $DestinationZip = $DestinationZip.Trim('"').Trim("'")

    # Con Claude abierto, Cookies y Local Storage estan bloqueados y la copia
    # saldria incompleta justo en lo que importa (la sesion).
    $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'claude' })
    if ($procs.Count -gt 0) {
        Write-Warn (Get-I18nStr 'MsgProcsRunning' @($($procs.Count)))
        Write-Warn (Get-I18nStr 'MsgCloseBeforeBackup')
        Write-Warn (Get-I18nStr 'MsgCloseBeforeBackup2')
        return
    }

    Write-Warn (Get-I18nStr 'MsgBackupHasTokens')
    Write-Warn (Get-I18nStr 'MsgBackupKeepSafe')

    $tempDir = Join-Path $env:TEMP "ClaudeMulti_Backup_$timestamp"
    if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        if (Test-Path -LiteralPath $script:HomeDir) {
            Copy-Item -LiteralPath $script:HomeDir -Destination (Join-Path $tempDir 'ClaudeMulti') -Recurse -Force
        }

        $profDir = Join-Path $tempDir 'Profiles'
        New-Item -ItemType Directory -Path $profDir -Force | Out-Null

        # robocopy en vez de Copy-Item: excluye la cache de entrada (en vez de
        # copiarla para borrarla despues) y no aborta si un archivo esta en uso.
        $skipped  = 0
        $sources  = @()
        $mainDir  = Join-Path $env:APPDATA 'Claude'
        if (Test-Path -LiteralPath $mainDir) { $sources += (Get-Item -LiteralPath $mainDir) }
        $sources += @(Get-ChildItem -LiteralPath $env:APPDATA -Filter 'Claude-*' -Directory -ErrorAction SilentlyContinue)

        foreach ($src in $sources) {
            $dst = Join-Path $profDir $src.Name
            # /XD acepta la lista tal cual: robocopy trata cada nombre suelto
            # como carpeta a excluir en cualquier nivel del arbol.
            $xd = @('/XD') + $script:DisposableDirs + $script:HeavyRegenerableDirs + @('claude-code')
            $null = robocopy $src.FullName $dst /E /XJ /R:0 /W:0 @xd /NFL /NDL /NJH /NJS /NP
            $rc = $LASTEXITCODE
            $global:LASTEXITCODE = 0
            if ($rc -ge 16) { throw (Get-I18nStr 'ErrRobocopyProfile' @($src.Name, $rc)) }
            if ($rc -ge 8)  { $skipped++ ; Write-Warn (Get-I18nStr 'MsgFilesInUse' @($src.Name)) }
            Write-Note (Get-I18nStr 'MsgIncluded' @($($src.Name)))
        }

        if (Test-Path -LiteralPath $DestinationZip) { Remove-Item -LiteralPath $DestinationZip -Force }
        Compress-Archive -Path (Join-Path $tempDir '*') -DestinationPath $DestinationZip -Force
        $zipMB = [math]::Round(((Get-Item -LiteralPath $DestinationZip).Length / 1MB), 2)

        Write-Ok (Get-I18nStr 'MsgBackupOk')
        Write-Note (Get-I18nStr 'MsgBackupPath' @($DestinationZip, $zipMB))
        if ($skipped -gt 0) {
            Write-Warn (Get-I18nStr 'MsgBackupIncomplete' @($skipped))
        }
    }
    catch {
        Write-Err (Get-I18nStr 'MsgBackupError' @($($_.Exception.Message)))
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Host ''
}

function Import-ProfileBackup {
    param([string]$SourceZip)
    if ([string]::IsNullOrWhiteSpace($SourceZip) -and -not $script:GuiLogger) {
        $SourceZip = Read-Host (Get-I18nStr 'AskBackupPath')
    }
    if ([string]::IsNullOrWhiteSpace($SourceZip)) { return }
    $SourceZip = $SourceZip.Trim('"').Trim("'")

    if (-not (Test-Path -LiteralPath $SourceZip)) {
        Write-Warn (Get-I18nStr 'MsgFileNotFound' @($SourceZip))
        return
    }

    # Restaurar sobre un perfil abierto deja la sesion en estado inconsistente.
    $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'claude' })
    if ($procs.Count -gt 0) {
        Write-Warn (Get-I18nStr 'MsgProcsRunning' @($($procs.Count)))
        Write-Warn (Get-I18nStr 'MsgCloseBeforeRestore')
        return
    }

    $tempDir = Join-Path $env:TEMP "ClaudeMulti_Restore_$(Get-Random)"
    if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        Expand-Archive -Path $SourceZip -DestinationPath $tempDir -Force

        # OJO: Copy-Item -Recurse sobre un destino que YA existe crea una
        # subcarpeta (destino\origen\...) en vez de fusionar. Hay que copiar
        # el CONTENIDO (ruta\*), no la carpeta.
        $homeBackup = Join-Path $tempDir 'ClaudeMulti'
        if (Test-Path -LiteralPath $homeBackup) {
            if (-not (Test-Path -LiteralPath $script:HomeDir)) {
                New-Item -ItemType Directory -Path $script:HomeDir -Force | Out-Null
            }
            Copy-Item -Path (Join-Path $homeBackup '*') -Destination $script:HomeDir -Recurse -Force
            Write-Ok (Get-I18nStr 'MsgLauncherRestored')
        }

        $profBackup = Join-Path $tempDir 'Profiles'
        if (Test-Path -LiteralPath $profBackup) {
            Get-ChildItem -LiteralPath $profBackup -Directory | ForEach-Object {
                $targetAppData = Join-Path $env:APPDATA $_.Name
                if (-not (Test-Path -LiteralPath $targetAppData)) {
                    New-Item -ItemType Directory -Path $targetAppData -Force | Out-Null
                }
                Copy-Item -Path (Join-Path $_.FullName '*') -Destination $targetAppData -Recurse -Force
                Write-Ok (Get-I18nStr 'MsgProfileRestored' @($($_.Name)))
            }
        }

        Write-Ok (Get-I18nStr 'MsgRestoreOk')
        Write-Note (Get-I18nStr 'MsgRestoreHint')
    }
    catch {
        Write-Err (Get-I18nStr 'MsgRestoreError' @($($_.Exception.Message)))
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Host ''
}

function Show-InteractiveMenu {
    $configuredObjs = Get-ConfiguredProfileObjects
    $configured = @($configuredObjs | ForEach-Object { $_.name })
    $current = $(if ($configured.Count -gt 0) { $configured } else { @('Cuenta1', 'Cuenta2', 'Cuenta3') })

    while ($true) {
        $displayList = @()
        foreach ($c in $current) {
            $note = Get-ProfileNote -Name $c
            if ($note) { $displayList += "$c ($note)" }
            else { $displayList += $c }
        }
        $currStr = $displayList -join ', '

        Write-Host ''
        Write-Host '=============================================================' -ForegroundColor White
        Write-Host ("  " + (Get-I18nStr 'MenuTitle')) -ForegroundColor White
        Write-Host '=============================================================' -ForegroundColor White
        Write-Host ("  " + (Get-I18nStr 'CurrentInstances') + ": [ $currStr ]") -ForegroundColor Cyan
        $mcpState = $(if ($script:CopyMcpConfig) { Get-I18nStr 'YesShort' } else { Get-I18nStr 'NoShort' })
        Write-Host ("  " + (Get-I18nStr 'CopyMcpsLabel') + ": $mcpState") -ForegroundColor Gray
        $sharedState = $(if ($script:SharedMemoryOn) { Get-I18nStr 'SharedMemOnAt' @($SharedDir) } else { Get-I18nStr 'NoShort' })
        Write-Host ("  " + (Get-I18nStr 'SharedMemLabel') + ": $sharedState") -ForegroundColor Gray
        Write-Host ''
        Write-Host ("  " + (Get-I18nStr 'MenuOpt1' @($currStr))) -ForegroundColor Yellow
        Write-Host ("  " + (Get-I18nStr 'MenuOpt2'))
        Write-Host ("  " + (Get-I18nStr 'MenuOpt3'))
        Write-Host ("  " + (Get-I18nStr 'MenuOpt4')) -ForegroundColor Green
        Write-Host ("  " + (Get-I18nStr 'MenuOpt5')) -ForegroundColor Green
        Write-Host ("  " + (Get-I18nStr 'MenuOpt6')) -ForegroundColor Green
        Write-Host ("  " + (Get-I18nStr 'MenuOpt7')) -ForegroundColor Green
        Write-Host ("  " + (Get-I18nStr 'MenuOpt8')) -ForegroundColor Green
        Write-Host ("  " + (Get-I18nStr 'MenuOpt9'))
        Write-Host ("  " + (Get-I18nStr 'MenuOpt10'))
        Write-Host ("  " + (Get-I18nStr 'MenuOpt11'))
        Write-Host ("  " + (Get-I18nStr 'MenuOpt0'))
        Write-Host ''
        $opt = Read-Host (Get-I18nStr 'SelectOpt')

        switch ($opt.Trim()) {
            '1' {
                return @{ Profiles = $current }
            }
            '2' {
                Write-Host ''
                $numStr = Read-Host (Get-I18nStr 'EnterTotalNum')
                [int]$num = 0
                if ([int]::TryParse($numStr, [ref]$num) -and $num -ge 1) {
                    $newList = @()
                    for ($i = 1; $i -le $num; $i++) {
                        if ($i -le $current.Count -and $current[$i-1]) {
                            $newList += $current[$i-1]
                        } else {
                            $newList += "Cuenta$i"
                        }
                    }
                    return @{ Profiles = $newList }
                } else {
                    Write-Warn (Get-I18nStr 'InvalidNum')
                }
            }
            '3' {
                Write-Host ''
                $newName = Read-Host (Get-I18nStr 'EnterNewName')
                if ($newName) { $newName = $newName.Trim() }
                if (-not [string]::IsNullOrWhiteSpace($newName)) {
                    if ($current -contains $newName) {
                        Write-Warn (Get-I18nStr 'ProfileExists' @($newName))
                    } else {
                        $newList = @($current) + $newName
                        return @{ Profiles = $newList }
                    }
                } else {
                    Write-Warn (Get-I18nStr 'NameCannotBeEmpty')
                }
            }
            '4' {
                Edit-ProfileNotes
            }
            '5' {
                Invoke-HealthCheck
            }
            '6' {
                $heavy = Clear-ProfileCache
                if ($heavy -gt 0) {
                    $ans = Read-Host (Get-I18nStr 'AskDeepClean')
                    if ($ans -match '^[SsYy]') { [void](Clear-ProfileCache -Deep) }
                }
            }
            '7' {
                Export-ProfileBackup
            }
            '8' {
                Import-ProfileBackup
            }
            '9' {
                $script:CopyMcpConfig = -not $script:CopyMcpConfig
                Write-Ok $(if ($script:CopyMcpConfig) { Get-I18nStr 'CopyMcpsActive' } else { Get-I18nStr 'CopyMcpsInactive' })
            }
            '10' {
                $script:SharedMemoryOn = -not $script:SharedMemoryOn
                if ($script:SharedMemoryOn) {
                    Write-Ok (Get-I18nStr 'SharedMemOn' @($SharedDir))
                    if (-not (Resolve-NpxCommand)) {
                        Write-Warn (Get-I18nStr 'NoNpxWarnMenu')
                    }
                    Write-Note (Get-I18nStr 'SharedMemApplyHint')
                }
                else {
                    Write-Ok (Get-I18nStr 'SharedMemOff')
                }
            }
            '11' {
                Write-Host ''
                Write-Warn (Get-I18nStr 'WarnDeleteData')
                $ans = Read-Host (Get-I18nStr 'ConfirmRevert')
                if ($ans -eq 'S' -or $ans -eq 's' -or $ans -eq 'Y' -or $ans -eq 'y') {
                    return @{ Profiles = $current; Revert = $true }
                }
            }
            '0' {
                Write-Host (Get-I18nStr 'OpCancelled')
                exit 0
            }
            default {
                Write-Warn (Get-I18nStr 'InvalidOpt')
            }
        }
    }
}

function Show-InputDialog {
    param([string]$Prompt, [string]$Title, [string]$DefaultValue = '')
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $Title
    $dlg.Size = New-Object System.Drawing.Size(380, 170)
    $dlg.StartPosition = 'CenterScreen'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(15, 15)
    $lbl.Size = New-Object System.Drawing.Size(335, 20)
    $lbl.Text = $Prompt
    [void]$dlg.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(15, 40)
    $txt.Size = New-Object System.Drawing.Size(335, 24)
    $txt.Text = $DefaultValue
    [void]$dlg.Controls.Add($txt)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Location = New-Object System.Drawing.Point(165, 80)
    $btnOk.Size = New-Object System.Drawing.Size(85, 28)
    $btnOk.Text = 'OK'
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    [void]$dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Location = New-Object System.Drawing.Point(260, 80)
    $btnCancel.Size = New-Object System.Drawing.Size(85, 28)
    $btnCancel.Text = 'Cancelar'
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    [void]$dlg.Controls.Add($btnCancel)

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel

    $result = $dlg.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $txt.Text
    }
    return $null
}

function Invoke-MultiSetup {
    param(
        [string[]]$TargetProfiles,
        [string]$TargetPortableDir = $PortableDir,
        [switch]$CopyMcp,
        [switch]$SharedMem,
        [string]$TargetSharedDir = $SharedDir,
        [switch]$NoLaunch,
        [switch]$GrantRead,
        [switch]$ForceRecopy
    )
    Assert-ProfileNames -Names $TargetProfiles

    Write-Step (Get-I18nStr 'StepSearchingInstall')
    $install = Get-ClaudeInstall

    if (-not $install) {
        Write-Err (Get-I18nStr 'MsgNotFound')
        Write-Note (Get-I18nStr 'MsgPathsChecked')
        Write-Note (Get-I18nStr 'MsgInstallClaude')
        return $false
    }

    Write-Ok (Get-I18nStr 'MsgInstallMode' @($($install.Mode)))
    Write-Note (Get-I18nStr 'MsgFolder' @($($install.Dir)))
    if ($install.Version) { Write-Note (Get-I18nStr 'MsgInstalledVer' @($install.Version)) }

    $targetExe   = $install.Exe
    $portableNew = $false

    if ($install.Mode -eq 'Msix') {
        Write-Step (Get-I18nStr 'StepMsixDetected')
        Write-Note (Get-I18nStr 'MsgMsixNote1')
        Write-Note (Get-I18nStr 'MsgMsixNote2')

        $stamp      = Get-PortableStamp -PortablePath $TargetPortableDir
        $needsCopy  = $true
        $copyReason = (Get-I18nStr 'MsgNoPortableYet')

        if ($ForceRecopy) {
            $copyReason = (Get-I18nStr 'MsgForceRecopy')
        }
        elseif ($stamp -and (Test-Path -LiteralPath $stamp.exe)) {
            if ($stamp.version -eq $install.Version) {
                $needsCopy  = $false
                $targetExe  = $stamp.exe
                Write-Ok (Get-I18nStr 'MsgPortableUpToDate' @($($stamp.version)))
            }
            else {
                $copyReason = (Get-I18nStr 'MsgClaudeUpdated' @($stamp.version, $install.Version))
            }
        }
        elseif ($stamp) {
            $copyReason = (Get-I18nStr 'MsgPortableIncomplete')
        }
        elseif (Test-Path -LiteralPath $TargetPortableDir) {
            $copyReason = (Get-I18nStr 'MsgPortableNoStamp')
        }

        if ($needsCopy) {
            Write-Note $copyReason

            $running = @(Get-PortableProcess -PortablePath $TargetPortableDir)
            if ($running.Count -gt 0) {
                Write-Warn (Get-I18nStr 'MsgPortableBusy' @($($running.Count), $TargetPortableDir))
                Write-Warn (Get-I18nStr 'MsgCannotReplace')
                Write-Note (Get-I18nStr 'MsgCloseAndRetry')
                Write-Note (Get-I18nStr 'MsgKeepUsingCurrent')
                $needsCopy = $false
                if ($stamp -and (Test-Path -LiteralPath $stamp.exe)) {
                    $targetExe = $stamp.exe
                }
                else {
                    $found = Get-ChildItem -LiteralPath $TargetPortableDir -Filter 'claude.exe' -Recurse `
                               -ErrorAction SilentlyContinue | Select-Object -First 1
                    if (-not $found) { throw (Get-I18nStr 'ErrNoClaudeExe' @($TargetPortableDir)) }
                    $targetExe = $found.FullName
                }
            }
        }

        $copied = -not $needsCopy
        if ($needsCopy) {
            $portableNew = $true
            try {
                Copy-ToPortable -Source $install.Dir -Destination $TargetPortableDir -Overwrite
                $copied = $true
            }
            catch {
                Write-Warn $_.Exception.Message
            }
        }

        if (-not $copied) {
            if (@(Get-PortableProcess -PortablePath $TargetPortableDir).Count -gt 0) {
                Write-Host ''
                Write-Err (Get-I18nStr 'MsgUpdateFailedBusy')
                Write-Note (Get-I18nStr 'MsgCloseAllAndRetry')
                return $false
            }

            Write-Host ''
            Write-Warn (Get-I18nStr 'MsgCopyFailedPerms')
            Write-Warn (Get-I18nStr 'MsgPermsFix1')
            Write-Warn (Get-I18nStr 'MsgPermsFix2')

            $allowed = [bool]$GrantRead
            if (-not $allowed) {
                try {
                    $allowed = $PSCmdlet.ShouldContinue(
                        (Get-I18nStr 'MsgPermsAsk' @($install.Dir)),
                        (Get-I18nStr 'MsgPermsCaption'))
                }
                catch {
                    if ($script:GuiLogger) {
                        $res = [System.Windows.Forms.MessageBox]::Show(
                            (Get-I18nStr 'GuiPermAsk' @($install.Dir)),
                            (Get-I18nStr 'GuiPermTitle'), 'YesNo', 'Question')
                        $allowed = ($res -eq 'Yes')
                    } else {
                        Write-Err (Get-I18nStr 'MsgNonInteractive')
                        $allowed = $false
                    }
                }
            }

            if (-not $allowed) {
                Write-Note (Get-I18nStr 'MsgCancelled')
                return $false
            }

            if (-not (Test-Admin)) {
                Write-Err (Get-I18nStr 'MsgNeedsAdmin')
                Write-Note (Get-I18nStr 'MsgRunAsAdmin')
                return $false
            }

            if ($PSCmdlet.ShouldProcess($install.Dir, 'takeown + icacls (lectura para Administradores)')) {
                Write-Note (Get-I18nStr 'MsgTakingOwnership')
                & takeown.exe /F "$($install.Dir)" /R /D S | Out-Null
                Write-Note (Get-I18nStr 'MsgGrantingRead')
                & icacls.exe "$($install.Dir)" /grant '*S-1-5-32-544:(OI)(CI)(RX)' /T /C /Q | Out-Null

                Copy-ToPortable -Source $install.Dir -Destination $TargetPortableDir -Overwrite
            }
        }

        if ($portableNew) {
            $portableExe = $null
            if ($install.Exe) {
                $baseDir = $install.Dir.TrimEnd('\')
                if ($install.Exe.StartsWith($baseDir, [StringComparison]::OrdinalIgnoreCase)) {
                    $rel         = $install.Exe.Substring($baseDir.Length).TrimStart('\')
                    $portableExe = Join-Path $TargetPortableDir $rel
                }
            }
            if (-not $portableExe -or -not (Test-Path -LiteralPath $portableExe)) {
                $found = Get-ChildItem -LiteralPath $TargetPortableDir -Filter 'claude.exe' -Recurse `
                           -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    $portableExe = $found.FullName
                }
                elseif (-not $WhatIfPreference) {
                    throw (Get-I18nStr 'ErrNoClaudeExe' @($TargetPortableDir))
                }
                elseif (-not $portableExe) {
                    $portableExe = Join-Path $TargetPortableDir 'claude.exe'
                }
            }
            $targetExe = $portableExe

            if (-not $WhatIfPreference) {
                Set-PortableStamp -PortablePath $TargetPortableDir -Version $install.Version `
                                  -Exe $targetExe -Source $install.Dir
            }
            Write-Ok (Get-I18nStr 'MsgPortableReady' @($($install.Version), $targetExe))
        }
    }
    else {
        Write-Ok (Get-I18nStr 'MsgNoPortableNeeded')
        if ($install.Exe -match '\\app-[0-9]') {
            Write-Warn (Get-I18nStr 'MsgVersionedFolder')
        }
    }

    if (-not $targetExe -or (-not (Test-Path -LiteralPath $targetExe) -and -not $WhatIfPreference)) {
        throw (Get-I18nStr 'ErrNoTargetExe')
    }

    # Se resuelve una sola vez, antes del bucle: si falta Node no tiene sentido
    # escribir la config en tres perfiles para que los tres fallen al arrancar.
    $sharedServers = $null
    if ($SharedMem) {
        Write-Step (Get-I18nStr 'StepPreparingShared')
        $npx = Resolve-NpxCommand
        if (-not $npx) {
            Write-Warn (Get-I18nStr 'MsgNoNpxSetup')
            $stray = Find-NpxOutsidePath
            if ($stray) {
                Write-Note (Get-I18nStr 'MsgNodeOutsidePath' @($stray))
                Write-Note (Get-I18nStr 'MsgAddToPath')
            }
            else {
                Write-Note (Get-I18nStr 'MsgInstallNode')
            }
            Write-Note (Get-I18nStr 'MsgRestContinues')
        }
        else {
            Initialize-SharedMemory -SharedDir $TargetSharedDir
            $sharedServers = Get-SharedMemoryServers -SharedDir $TargetSharedDir
            Write-Ok (Get-I18nStr 'MsgSharedFolder' @($TargetSharedDir))
            Write-Note (Get-I18nStr 'MsgNpxAt' @($npx))
        }
    }

    $iconDir = Join-Path $script:HomeDir 'icons'
    Write-Step (Get-I18nStr 'StepGeneratingIcons')
    $icons = @{}
    for ($i = 0; $i -lt $TargetProfiles.Count; $i++) {
        $n = $TargetProfiles[$i]
        try {
            $ic = New-ProfileIcon -Name $n -Index $i -SourceExe $targetExe -OutDir $iconDir
            $icons[$n] = $ic
            Write-Ok (Get-I18nStr 'PairArrow' @($n, $ic.Color))
        }
        catch {
            Write-Warn (Get-I18nStr 'MsgIconFailed' @($n, $($_.Exception.Message)))
            $icons[$n] = $null
        }
    }

    if (-not $NoLaunch) {
        Write-Step (Get-I18nStr 'StepInstallingLauncher')
        Install-Launcher -HomePath $script:HomeDir
        Write-Ok $script:HomeDir
    }

    Write-Step (Get-I18nStr 'StepCreatingShortcuts')
    $wscript  = Join-Path $env:WINDIR 'System32\wscript.exe'
    $vbs      = Join-Path $script:HomeDir 'launch.vbs'
    $created  = @()
    $cfgProfs = @()

    for ($i = 0; $i -lt $TargetProfiles.Count; $i++) {
        $name     = $TargetProfiles[$i]
        $label    = Get-ProfileLabel -Name $name -Index $i
        $iconPath = $(if ($icons[$name]) { $icons[$name].Path } else { $targetExe })
        $color    = $(if ($icons[$name]) { $icons[$name].Color } else { '-' })
        $useStore = ($i -eq 0 -and $install.Mode -eq 'Msix' -and $install.Aumid)
        $note     = Get-ProfileNote -Name $name
        $noteStr  = $(if ($note) { " ($note)" } else { '' })

        # Borrar accesos directos anteriores de esta misma cuenta si cambio su
        # nota o etiqueta. Se comparan rutas exactas, no un comodin por prefijo.
        foreach ($old in (Get-ProfileShortcutPaths -Name $name)) {
            if ((Test-Path -LiteralPath $old) -and ((Split-Path -Leaf $old) -ne "$label.lnk")) {
                if ($WhatIfPreference) {
                    Write-Note (Get-I18nStr 'MsgWhatIfRemoveOld' @($(Split-Path -Leaf $old)))
                }
                else {
                    Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
                    Write-Note (Get-I18nStr 'MsgRemovedOldLnk' @($(Split-Path -Leaf $old)))
                }
            }
        }

        if ($i -eq 0) {
            $dataDir = Join-Path $env:APPDATA 'Claude'
        }
        else {
            $dataDir = Join-Path $env:APPDATA "Claude-$name"
            if (-not (Test-Path -LiteralPath $dataDir)) {
                New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            }
            if ($CopyMcp) {
                Copy-McpConfig -DestinationDir $dataDir -Overwrite:$ForceRecopy
            }
        }

        # A diferencia de -CopyMcpConfig, esto SI aplica al primer perfil: la
        # gracia es que las tres cuentas vean la misma carpeta.
        if ($sharedServers) {
            $w = @(Merge-McpServers -DestinationDir $dataDir -Servers $sharedServers -Overwrite:$ForceRecopy)
            if ($w.Count -gt 0) { Write-Note (Get-I18nStr 'MsgSharedInProfile' @($name, ($w -join ', '))) }
        }

        if ($useStore) {
            $lnk = New-ClaudeShortcut -Name $label `
                     -Target      (Join-Path $env:WINDIR 'explorer.exe') `
                     -Arguments   "shell:AppsFolder\$($install.Aumid)" `
                     -IconPath    $iconPath `
                     -Description (Get-I18nStr 'DescStore' @($name, $noteStr))
            $via = (Get-I18nStr 'ViaStore')
        }
        elseif ($NoLaunch) {
            $arg = $(if ($i -eq 0) { '' } else { "--user-data-dir=`"$dataDir`"" })
            $lnk = New-ClaudeShortcut -Name $label -Target $targetExe -Arguments $arg `
                     -IconPath $iconPath -Description (Get-I18nStr 'DescExe' @($name, $noteStr, $dataDir))
            $via = (Get-I18nStr 'ViaExe')
        }
        else {
            $lnk = New-ClaudeShortcut -Name $label `
                     -Target      $wscript `
                     -Arguments   "`"$vbs`" `"$name`"" `
                     -IconPath    $iconPath `
                     -Description (Get-I18nStr 'DescLauncher' @($name, $noteStr))
            $via = (Get-I18nStr 'ViaLauncher')
        }

        $cfgProfs += [pscustomobject]@{
            name     = $name
            note     = $note
            dataDir  = $dataDir
            useStore = [bool]$useStore
            exe      = $targetExe
            icon     = $iconPath
        }
        $created += [pscustomobject]([ordered]@{
            (Get-I18nStr 'HeaderPerfil') = $name
            (Get-I18nStr 'HeaderColor')  = $color
            (Get-I18nStr 'HeaderLanza')  = $via
            (Get-I18nStr 'HeaderAcceso') = Split-Path -Leaf $lnk
        })
        Write-Ok (Get-I18nStr 'MsgProfileDone' @($label, $color))
    }

    # config.json se escribe SIEMPRE: ya no es solo del lanzador, es la lista
    # de perfiles y sus notas que leen el menu, la GUI y Get-ProfileShortcutPaths.
    if (-not (Test-Path -LiteralPath $script:HomeDir)) {
        New-Item -ItemType Directory -Path $script:HomeDir -Force | Out-Null
    }
    Write-LauncherConfig -HomePath $script:HomeDir -Config ([pscustomobject]@{
        mode        = $install.Mode
        aumid       = $install.Aumid
        portableDir = $TargetPortableDir
        sourceExe   = $install.Exe
        version     = $install.Version
        copyMcp     = [bool]$CopyMcp
        noLauncher  = [bool]$NoLaunch
        sharedMemory = [bool]$SharedMem
        sharedDir    = $TargetSharedDir
        profiles    = $cfgProfs
    })

    Write-Host ''
    Write-Host '=============================================================' -ForegroundColor White
    Write-Host "  $(Get-I18nStr 'ReadyTitle')" -ForegroundColor Green
    Write-Host '=============================================================' -ForegroundColor White
    $tableStr = $created | Format-Table -AutoSize | Out-String
    Write-Host $tableStr
    if ($script:GuiLogger) { & $script:GuiLogger $tableStr }

    return $true
}

function Show-GuiWindow {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = (Get-I18nStr 'GuiTitle')
    $form.Size = New-Object System.Drawing.Size(760, 648)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $form.ForeColor = [System.Drawing.Color]::White

    $fontTitle = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $fontBtn   = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $fontNorm  = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
    $fontLog   = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Regular)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Location = New-Object System.Drawing.Point(15, 12)
    $lblTitle.Size = New-Object System.Drawing.Size(720, 28)
    $lblTitle.Text = (Get-I18nStr 'HeaderTitle')
    $lblTitle.Font = $fontTitle
    $lblTitle.ForeColor = [System.Drawing.Color]::Cyan
    [void]$form.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Location = New-Object System.Drawing.Point(15, 42)
    $lblSub.Size = New-Object System.Drawing.Size(720, 20)
    $lblSub.Text = (Get-I18nStr 'CurrentInstances') + ":"
    $lblSub.Font = $fontNorm
    $lblSub.ForeColor = [System.Drawing.Color]::LightGray
    [void]$form.Controls.Add($lblSub)

    $lstProfiles = New-Object System.Windows.Forms.ListBox
    $lstProfiles.Location = New-Object System.Drawing.Point(15, 65)
    $lstProfiles.Size = New-Object System.Drawing.Size(320, 140)
    $lstProfiles.Font = $fontNorm
    $lstProfiles.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
    $lstProfiles.ForeColor = [System.Drawing.Color]::White
    [void]$form.Controls.Add($lstProfiles)

    function Refresh-ProfileList {
        $lstProfiles.Items.Clear()
        $profs = Get-ConfiguredProfileObjects
        if ($profs.Count -eq 0) {
            foreach ($p in @('Cuenta1', 'Cuenta2', 'Cuenta3')) {
                [void]$lstProfiles.Items.Add($p)
            }
        } else {
            foreach ($p in $profs) {
                $noteStr = $(if ($p.note) { " ($($p.note))" } else { '' })
                [void]$lstProfiles.Items.Add("$($p.name)$noteStr")
            }
        }
    }
    Refresh-ProfileList

    $chkCopyMcp = New-Object System.Windows.Forms.CheckBox
    $chkCopyMcp.Location = New-Object System.Drawing.Point(15, 212)
    $chkCopyMcp.Size = New-Object System.Drawing.Size(320, 24)
    $chkCopyMcp.Text = (Get-I18nStr 'CopyMcpsLabel')
    $chkCopyMcp.Font = $fontNorm
    $chkCopyMcp.Checked = [bool]$script:CopyMcpConfig
    [void]$form.Controls.Add($chkCopyMcp)

    $chkShared = New-Object System.Windows.Forms.CheckBox
    $chkShared.Location = New-Object System.Drawing.Point(15, 236)
    $chkShared.Size = New-Object System.Drawing.Size(320, 24)
    $chkShared.Text = (Get-I18nStr 'SharedMemLabel')
    $chkShared.Font = $fontNorm
    $chkShared.Checked = [bool]$script:SharedMemoryOn
    [void]$form.Controls.Add($chkShared)

    [int]$btnX = 350
    [int]$btnW = 380

    $btnRun = New-Object System.Windows.Forms.Button
    $btnRun.Location = New-Object System.Drawing.Point($btnX, 65)
    $btnRun.Size = New-Object System.Drawing.Size($btnW, 32)
    $btnRun.Text = (Get-I18nStr 'GuiBtnRun')
    $btnRun.Font = $fontBtn
    $btnRun.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
    $btnRun.ForeColor = [System.Drawing.Color]::White
    $btnRun.FlatStyle = 'Flat'
    [void]$form.Controls.Add($btnRun)

    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Location = New-Object System.Drawing.Point($btnX, 102)
    $btnAdd.Size = New-Object System.Drawing.Size(185, 30)
    $btnAdd.Text = (Get-I18nStr 'GuiBtnAdd')
    $btnAdd.Font = $fontNorm
    $btnAdd.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 65)
    $btnAdd.FlatStyle = 'Flat'
    [void]$form.Controls.Add($btnAdd)

    $btnNote = New-Object System.Windows.Forms.Button
    $btnNote.Location = New-Object System.Drawing.Point(($btnX + 195), 102)
    $btnNote.Size = New-Object System.Drawing.Size(185, 30)
    $btnNote.Text = (Get-I18nStr 'GuiBtnNote')
    $btnNote.Font = $fontNorm
    $btnNote.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 65)
    $btnNote.FlatStyle = 'Flat'
    [void]$form.Controls.Add($btnNote)

    $btnHealth = New-Object System.Windows.Forms.Button
    $btnHealth.Location = New-Object System.Drawing.Point($btnX, 137)
    $btnHealth.Size = New-Object System.Drawing.Size(185, 30)
    $btnHealth.Text = (Get-I18nStr 'GuiBtnHealth')
    $btnHealth.Font = $fontNorm
    $btnHealth.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 65)
    $btnHealth.FlatStyle = 'Flat'
    [void]$form.Controls.Add($btnHealth)

    $btnCache = New-Object System.Windows.Forms.Button
    $btnCache.Location = New-Object System.Drawing.Point(($btnX + 195), 137)
    $btnCache.Size = New-Object System.Drawing.Size(185, 30)
    $btnCache.Text = (Get-I18nStr 'GuiBtnCache')
    $btnCache.Font = $fontNorm
    $btnCache.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 65)
    $btnCache.FlatStyle = 'Flat'
    [void]$form.Controls.Add($btnCache)

    $btnBackup = New-Object System.Windows.Forms.Button
    $btnBackup.Location = New-Object System.Drawing.Point($btnX, 172)
    $btnBackup.Size = New-Object System.Drawing.Size(185, 30)
    $btnBackup.Text = (Get-I18nStr 'GuiBtnBackup')
    $btnBackup.Font = $fontNorm
    $btnBackup.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 65)
    $btnBackup.FlatStyle = 'Flat'
    [void]$form.Controls.Add($btnBackup)

    $btnRestore = New-Object System.Windows.Forms.Button
    $btnRestore.Location = New-Object System.Drawing.Point(($btnX + 195), 172)
    $btnRestore.Size = New-Object System.Drawing.Size(185, 30)
    $btnRestore.Text = (Get-I18nStr 'GuiBtnRestore')
    $btnRestore.Font = $fontNorm
    $btnRestore.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 65)
    $btnRestore.FlatStyle = 'Flat'
    [void]$form.Controls.Add($btnRestore)

    $btnRevert = New-Object System.Windows.Forms.Button
    $btnRevert.Location = New-Object System.Drawing.Point($btnX, 207)
    $btnRevert.Size = New-Object System.Drawing.Size($btnW, 48)
    $btnRevert.Text = (Get-I18nStr 'GuiBtnRevert')
    $btnRevert.Font = $fontNorm
    $btnRevert.BackColor = [System.Drawing.Color]::FromArgb(150, 40, 40)
    $btnRevert.ForeColor = [System.Drawing.Color]::White
    $btnRevert.FlatStyle = 'Flat'
    [void]$form.Controls.Add($btnRevert)

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Location = New-Object System.Drawing.Point(15, 268)
    $txtLog.Size = New-Object System.Drawing.Size(715, 320)
    $txtLog.Multiline = $true
    $txtLog.ReadOnly = $true
    $txtLog.ScrollBars = 'Vertical'
    $txtLog.Font = $fontLog
    $txtLog.BackColor = [System.Drawing.Color]::FromArgb(12, 12, 12)
    $txtLog.ForeColor = [System.Drawing.Color]::FromArgb(0, 255, 100)
    [void]$form.Controls.Add($txtLog)

    function Append-GuiLog {
        param([string]$Message)
        $txtLog.AppendText("$Message`r`n")
        $txtLog.SelectionStart = $txtLog.Text.Length
        $txtLog.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }

    $script:GuiLogger = { param($msg) Append-GuiLog $msg }

    # La copia portable corre en el hilo de UI y puede tardar minutos. No se
    # puede evitar el bloqueo sin runspaces, pero al menos se ve que trabaja
    # y no se aceptan clics que reentrarian en la misma operacion.
    $allButtons = @($btnRun, $btnAdd, $btnNote, $btnHealth, $btnCache, $btnBackup, $btnRestore, $btnRevert)
    function Set-GuiBusy {
        param([bool]$Busy)
        foreach ($b in $allButtons) { $b.Enabled = -not $Busy }
        $form.Cursor = $(if ($Busy) { [System.Windows.Forms.Cursors]::WaitCursor }
                         else       { [System.Windows.Forms.Cursors]::Default })
        [System.Windows.Forms.Application]::DoEvents()
    }

    $btnRun.Add_Click({
        $txtLog.Clear()
        $script:CopyMcpConfig = $chkCopyMcp.Checked
        $script:SharedMemoryOn = $chkShared.Checked
        $profs = Get-ConfiguredProfiles
        if ($profs.Count -eq 0) { $profs = @('Cuenta1', 'Cuenta2', 'Cuenta3') }
        Append-GuiLog (Get-I18nStr 'GuiRunning' @($profs -join ', '))
        Append-GuiLog (Get-I18nStr 'GuiRunningHint')
        Set-GuiBusy $true
        try {
            [void](Invoke-MultiSetup -TargetProfiles $profs -CopyMcp:$script:CopyMcpConfig -SharedMem:$script:SharedMemoryOn -TargetSharedDir $SharedDir -NoLaunch:$NoLauncher -GrantRead:$GrantWindowsAppsRead -ForceRecopy:$Force)
        }
        catch { Append-GuiLog "    [X]    $($_.Exception.Message)" }
        finally { Set-GuiBusy $false }
        Refresh-ProfileList
    })

    $btnAdd.Add_Click({
        $newName = Show-InputDialog -Prompt (Get-I18nStr 'GuiAddPrompt') -Title (Get-I18nStr 'GuiAddTitle') -DefaultValue (Get-I18nStr 'GuiAddDefault')
        if (-not [string]::IsNullOrWhiteSpace($newName)) {
            $newName = $newName.Trim()
            $profs = Get-ConfiguredProfiles
            if ($profs.Count -eq 0) { $profs = @('Cuenta1', 'Cuenta2', 'Cuenta3') }
            if ($profs -contains $newName) {
                [System.Windows.Forms.MessageBox]::Show((Get-I18nStr 'ProfileExists' @($newName)), (Get-I18nStr 'GuiTitle'), 'OK', 'Warning')
            } else {
                $newList = @($profs) + $newName
                $script:SharedMemoryOn = $chkShared.Checked
                $txtLog.Clear()
                Append-GuiLog (Get-I18nStr 'GuiAdding' @($newName))
                Set-GuiBusy $true
                try {
                    [void](Invoke-MultiSetup -TargetProfiles $newList -CopyMcp:$script:CopyMcpConfig -SharedMem:$script:SharedMemoryOn -TargetSharedDir $SharedDir -NoLaunch:$NoLauncher -GrantRead:$GrantWindowsAppsRead -ForceRecopy:$Force)
                }
                catch { Append-GuiLog "    [X]    $($_.Exception.Message)" }
                finally { Set-GuiBusy $false }
                Refresh-ProfileList
            }
        }
    })

    $btnNote.Add_Click({
        $selItem = $lstProfiles.SelectedItem
        if (-not $selItem) {
            [System.Windows.Forms.MessageBox]::Show((Get-I18nStr 'GuiPickProfile'), (Get-I18nStr 'GuiNoteTitle'), 'OK', 'Information')
            return
        }
        $profName = ($selItem -replace '\s*\(.*\)$', '').Trim()
        $currentNote = Get-ProfileNote -Name $profName
        $newNote = Show-InputDialog -Prompt (Get-I18nStr 'GuiNotePrompt' @($profName)) -Title (Get-I18nStr 'GuiNoteTitle') -DefaultValue $currentNote
        if ($newNote -ne $null) {
            $profs = Get-ConfiguredProfileObjects
            $found = $profs | Where-Object { $_.name -eq $profName } | Select-Object -First 1
            if ($found) {
                if ($found.PSObject.Properties.Name -contains 'note') { $found.note = $newNote.Trim() }
                else { $found | Add-Member -NotePropertyName 'note' -NotePropertyValue $newNote.Trim() }
            } else {
                $profs += [pscustomobject]@{ name = $profName; note = $newNote.Trim() }
            }
            $cfgFile = Join-Path $script:HomeDir 'config.json'
            if (Test-Path -LiteralPath $cfgFile) {
                try {
                    $cfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
                    $cfg.profiles = $profs
                    $json = $cfg | ConvertTo-Json -Depth 8
                    [IO.File]::WriteAllText($cfgFile, $json, (New-Object Text.UTF8Encoding($false)))
                    Append-GuiLog (Get-I18nStr 'GuiNoteUpdated' @($profName, $newNote.Trim()))
                } catch { }
            }
            $txtLog.Clear()
            Append-GuiLog (Get-I18nStr 'GuiRebuilding')
            $profsToUpdate = Get-ConfiguredProfiles
            if ($profsToUpdate.Count -eq 0) { $profsToUpdate = @('Cuenta1', 'Cuenta2', 'Cuenta3') }
            Set-GuiBusy $true
            try {
                [void](Invoke-MultiSetup -TargetProfiles $profsToUpdate -CopyMcp:$script:CopyMcpConfig -SharedMem:$script:SharedMemoryOn -TargetSharedDir $SharedDir -NoLaunch:$NoLauncher -GrantRead:$GrantWindowsAppsRead -ForceRecopy:$Force)
            }
            catch { Append-GuiLog "    [X]    $($_.Exception.Message)" }
            finally { Set-GuiBusy $false }
            Refresh-ProfileList
        }
    })

    $btnHealth.Add_Click({
        $txtLog.Clear()
        Append-GuiLog (Get-I18nStr 'GuiStartHealth')
        Invoke-HealthCheck
        Refresh-ProfileList
    })

    $btnCache.Add_Click({
        $txtLog.Clear()
        Append-GuiLog (Get-I18nStr 'GuiStartCache')
        $heavy = Clear-ProfileCache
        if ($heavy -gt 0) {
            $heavyMB = [math]::Round(($heavy / 1MB), 0)
            $res = [System.Windows.Forms.MessageBox]::Show(
                (Get-I18nStr 'GuiDeepCleanMsg' @($heavyMB)),
                (Get-I18nStr 'GuiDeepCleanTitle'), 'YesNo', 'Question')
            if ($res -eq 'Yes') {
                Set-GuiBusy $true
                try { [void](Clear-ProfileCache -Deep) } finally { Set-GuiBusy $false }
            }
        }
    })

    $btnBackup.Add_Click({
        $txtLog.Clear()
        $dlgSave = New-Object System.Windows.Forms.SaveFileDialog
        $dlgSave.Filter = (Get-I18nStr 'GuiZipFilter')
        $dlgSave.Title = (Get-I18nStr 'GuiSaveBackupTitle')
        $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
        $dlgSave.FileName = "ClaudeMulti_Backup_$timestamp.zip"
        $dlgSave.InitialDirectory = [Environment]::GetFolderPath('Desktop')

        if ($dlgSave.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            Export-ProfileBackup -DestinationZip $dlgSave.FileName
        }
    })

    $btnRestore.Add_Click({
        $txtLog.Clear()
        $dlgOpen = New-Object System.Windows.Forms.OpenFileDialog
        $dlgOpen.Filter = (Get-I18nStr 'GuiZipFilter')
        $dlgOpen.Title = (Get-I18nStr 'GuiOpenBackupTitle')
        $dlgOpen.InitialDirectory = [Environment]::GetFolderPath('Desktop')

        if ($dlgOpen.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            Import-ProfileBackup -SourceZip $dlgOpen.FileName
            Refresh-ProfileList
        }
    })

    $btnRevert.Add_Click({
        $res = [System.Windows.Forms.MessageBox]::Show((Get-I18nStr 'GuiConfirmRevert'), (Get-I18nStr 'GuiConfirmRevertTitle'), 'YesNo', 'Warning')
        if ($res -eq 'Yes') {
            $txtLog.Clear()
            $profs = Get-ConfiguredProfiles
            if ($profs.Count -eq 0) { $profs = @('Cuenta1', 'Cuenta2', 'Cuenta3') }
            Append-GuiLog (Get-I18nStr 'GuiReverting')
            Invoke-Revert -Names $profs -PortablePath $PortableDir -SkipConfirm:$true
            Refresh-ProfileList
        }
    })

    [void]$form.ShowDialog()
    $script:GuiLogger = $null
}

# ------------------------------------------------------------------- main ---

Write-Host ''
Write-Host '=============================================================' -ForegroundColor White
Write-Host ("  " + (Get-I18nStr 'HeaderTitle')) -ForegroundColor White
Write-Host '=============================================================' -ForegroundColor White

# El checkbox de la interfaz y el menu arrancan con lo que quedo guardado la
# ultima vez, no en blanco. Lo que venga por linea de comandos manda.
$script:SharedMemoryOn = [bool]$SharedMemory
$savedCfg = $null
$savedCfgFile = Join-Path $script:HomeDir 'config.json'
if (Test-Path -LiteralPath $savedCfgFile) {
    try { $savedCfg = Get-Content -LiteralPath $savedCfgFile -Raw | ConvertFrom-Json } catch { }
}
if ($savedCfg) {
    if ($savedCfg.sharedMemory -and -not $PSBoundParameters.ContainsKey('SharedMemory')) {
        $script:SharedMemoryOn = $true
    }
    if ($savedCfg.sharedDir -and -not $PSBoundParameters.ContainsKey('SharedDir')) {
        $SharedDir = $savedCfg.sharedDir
    }
    if ($savedCfg.copyMcp -and -not $PSBoundParameters.ContainsKey('CopyMcpConfig')) {
        $CopyMcpConfig = $true
    }
}

# -GUI abre la interfaz aunque se hayan pasado -Profiles; sin argumentos, la
# interfaz es el modo por defecto y -CLI fuerza el menu de texto.
$wantsInteractive = $GUI -or $CLI -or (-not $PSBoundParameters.ContainsKey('Profiles') -and -not $Revert)

if ($wantsInteractive -and [Environment]::UserInteractive) {
    if ($CLI) {
        $menuRes = Show-InteractiveMenu
        if ($menuRes) {
            if ($menuRes.Profiles) { $Profiles = $menuRes.Profiles }
            if ($menuRes.Revert)   { $Revert = $true }
        }
    }
    else {
        Show-GuiWindow
        exit 0
    }
}
elseif ($wantsInteractive -and -not $PSBoundParameters.ContainsKey('Profiles')) {
    Write-Note (Get-I18nStr 'MsgNonInteractiveDefaults')
}

$Profiles = @(
    $Profiles |
    ForEach-Object { $_ -split ',' } |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ }
)

if ($Revert) {
    Invoke-Revert -Names $Profiles -PortablePath $PortableDir -SkipConfirm:$Force
    Write-Host ''
    exit 0
}

[void](Invoke-MultiSetup -TargetProfiles $Profiles -TargetPortableDir $PortableDir -CopyMcp:$CopyMcpConfig -SharedMem:$script:SharedMemoryOn -TargetSharedDir $SharedDir -NoLaunch:$NoLauncher -GrantRead:$GrantWindowsAppsRead -ForceRecopy:$Force)
exit 0
