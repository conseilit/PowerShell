<#
.SYNOPSIS
    Configure une instance SQL Server pour la production, à l'aide de dbatools.

.DESCRIPTION
    Applique un socle d'exploitation à une instance SQL Server : réglages moteur,
    sessions Extended Events, audit DDL, base d'administration, outillage communautaire,
    solution de maintenance Ola Hallengren, jobs de sauvegarde et de supervision.

    Le script est idempotent : relancé sur une instance déjà configurée, il ne recrée pas
    les objets existants et se contente de réappliquer les réglages. Il est prévu pour être
    appelé par un orchestrateur (SQLFleet) : en cas d'échec fatal, il lève une erreur, ce qui
    produit un code de sortie non nul — un job ne peut donc pas le déclarer réussi à tort.

    Éditions : sur Express, les blocs qui dépendent de l'Agent SQL et de l'audit serveur sont
    ignorés avec un avertissement (ces fonctions n'y existent pas).

.PARAMETER SqlInstance
    Instance cible, au format HOST ou HOST\INSTANCE. Obligatoire.

.PARAMETER SqlCredential
    Identifiants SQL pour la connexion. Omis, la connexion utilise l'identité courante
    (Windows). À fournir pour une authentification SQL.

.PARAMETER DbaDatabase
    Nom de la base d'administration qui accueille les procédures et les tables de suivi.

.PARAMETER BackupStrategy
    FullDiffLog : sauvegarde complète hebdomadaire (dimanche) + différentielles en semaine + journaux.
    FullLog     : sauvegarde complète quotidienne + journaux (le job différentiel est désactivé).

.PARAMETER BackupCleanupHours
    Rétention des sauvegardes, en heures. 360 = 15 jours.

.PARAMETER IndexTimeLimitSeconds
    Temps maximal alloué aux opérations d'index et de statistiques, en secondes.

.PARAMETER MonitoringCleanupDays
    Rétention des tables de supervision, en jours.

.PARAMETER MonitoringIntervalMinutes
    Intervalle de collecte de la supervision, en minutes.

.PARAMETER SkipMonitoring
    N'installe pas les tables et le job de supervision.

.PARAMETER SkipMaxMemoryAdjustment
    Ne touche pas au réglage « max server memory ».

.PARAMETER BackupDirectory
    Emplacement des sauvegardes. Vide : répertoire de sauvegarde par défaut de l'instance.

.PARAMETER ErrorLogCount
    Nombre de fichiers de log d'erreurs conservés.

.PARAMETER SpConfigure
    Réglages supplémentaires de sp_configure, en table de hachage. Ils s'ajoutent aux valeurs
    par défaut du socle et les remplacent en cas de conflit.
    Exemple : @{ 'Max Degree of Parallelism' = 4 ; 'Cost Threshold for Parallelism' = 80 }

.PARAMETER LogPath
    Fichier de journal. Omis, la sortie reste sur le flux standard (récupérée par le job).

.PARAMETER SkipAudit
    N'installe pas l'audit DDL.

.PARAMETER SkipEventSessions
    Ne crée pas les sessions Extended Events de diagnostic.

.PARAMETER SkipCommunityTools
    N'installe pas sp_whoisactive ni le First Responder Kit.

.PARAMETER SkipMaintenanceSolution
    N'installe pas la solution Ola Hallengren ni les jobs associés.

.PARAMETER SkipBackupJobs
    Ne crée pas les jobs de sauvegarde.

.PARAMETER SkipHousekeepingJob
    Ne crée pas le job de maintenance courante (rotation des logs, purge d'historique, etc.).

.PARAMETER SkipFinalChecks
    N'exécute pas les contrôles de fin (latence réseau, planification, Kerberos).

.EXAMPLE
    .\SQL-ConfigureWithDBATools.ps1 -SqlInstance 'SQLBAG1'

    Applique le socle complet avec les valeurs par défaut.

.EXAMPLE
    .\SQL-ConfigureWithDBATools.ps1 -SqlInstance 'SQLBAG1\PROD' -BackupStrategy FullLog `
        -BackupDirectory '\\NAS01\SQLBackups' -LogPath 'C:\Temp\configure-sqlbag1.log'

    Sauvegarde complète quotidienne vers un partage, journalisation dans un fichier.

.EXAMPLE
    .\SQL-ConfigureWithDBATools.ps1 -SqlInstance 'SQLBAG1' -WhatIf

    Affiche les actions qui seraient réalisées, sans rien modifier.

.NOTES
    Auteur d'origine : Christophe LAPORTE — http://conseilit.wordpress.com — @ConseilIT
    Socle dbatools : Chrissy LeMaire, Rob Sewell et la communauté SQL Server (dbatools.io).
    Licence d'origine : code réutilisable et republiable avec attribution.

    Métadonnées lisibles par l'orchestrateur :
        #@version  : version du script, comparée par le bouton de rafraîchissement
        #@updated  : date de dernière modification
#>
#@version 2.0.0
#@updated 2026-11-03

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$SqlInstance,

    [pscredential]$SqlCredential,

    [ValidatePattern('^[A-Za-z0-9_\-]+$')]
    [string]$DbaDatabase = '_DBA',

    [ValidateSet('FullDiffLog', 'FullLog')]
    [string]$BackupStrategy = 'FullDiffLog',

    [ValidateRange(1, 8760)]
    [int]$BackupCleanupHours = 360,

    [ValidateRange(60, 86400)]
    [int]$IndexTimeLimitSeconds = 7200,

    [ValidateRange(1, 3650)]
    [int]$MonitoringCleanupDays = 90,

    [ValidateRange(1, 1440)]
    [int]$MonitoringIntervalMinutes = 5,

    [switch]$SkipMonitoring,

    [switch]$SkipMaxMemoryAdjustment,

    [string]$BackupDirectory = '',

    [ValidateRange(1, 999)]
    [int]$ErrorLogCount = 99,

    [hashtable]$SpConfigure = @{},

    [string]$LogPath,

    [switch]$SkipAudit,

    [switch]$SkipEventSessions,

    [switch]$SkipCommunityTools,

    [switch]$SkipMaintenanceSolution,

    [switch]$SkipBackupJobs,

    [switch]$SkipHousekeepingJob,

    [switch]$SkipFinalChecks
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --------------------------------------------------------------------------
# Journalisation
# --------------------------------------------------------------------------

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    $ligne = '{0} [{1}] {2}' -f [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message

    # Write-Output plutôt que Write-Host : le flux est ainsi récupéré par l'orchestrateur
    # (job SQLFleet), alors que Write-Host écrit directement dans la console de l'hôte.
    if ($Level -eq 'DEBUG') { Write-Verbose $ligne } else { Write-Output $ligne }

    if ($LogPath) {
        $dossier = Split-Path -Path $LogPath -Parent
        if ($dossier -and -not (Test-Path -LiteralPath $dossier)) {
            New-Item -ItemType Directory -Path $dossier -Force | Out-Null
        }
        Add-Content -LiteralPath $LogPath -Value $ligne -Encoding utf8
    }
}

function Invoke-ConfigurationStep {
    <#
        Exécute un bloc de configuration en isolant les erreurs : une étape qui échoue est
        journalisée et n'interrompt pas le reste du socle. Le bloc de connexion, lui, est
        fatal et n'utilise pas ce garde-fou.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [scriptblock]$Action
    )

    try {
        & $Action
    }
    catch {
        Write-Log "Étape « $Name » en échec : $($_.Exception.Message)" -Level ERROR
    }
}

# --------------------------------------------------------------------------
# Préparation : module dbatools, connexion, inventaire de l'instance
# --------------------------------------------------------------------------

function Initialize-DbaToolsModule {
    $module = Get-Module -ListAvailable -Name dbatools |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1

    if (-not $module) {
        Write-Log "Le module dbatools est absent. Installez-le : Install-Module dbatools -Scope CurrentUser" -Level ERROR
        throw 'Module dbatools introuvable.'
    }

    Write-Log "dbatools $($module.Version) disponible."
    Import-Module dbatools -ErrorAction Stop

    # dbatools 2 bascule sur un chiffrement strict : les instances sans certificat valide
    # refusent alors la connexion. On l'assouplit pour la session, comme le faisait l'original.
    # Le test porte sur le module réellement chargé : Get-InstalledModule échoue quand dbatools
    # a été déployé hors PowerShellGet (copie de dossier, module du runner), ce qui laissait
    # passer la connexion stricte et faisait échouer le socle sur un certificat auto-signé.
    if ($module.Version.Major -ge 2) {
        Set-DbatoolsInsecureConnection -SessionOnly | Out-Null
        Write-Log "Connexions dbatools assouplies pour la session (module v$($module.Version.Major))."
    }
}

function Connect-SqlTarget {
    [CmdletBinding()]
    param()

    Write-Log "Connexion à $SqlInstance."
    try {
        $params = @{ SqlInstance = $SqlInstance }
        if ($SqlCredential) { $params.SqlCredential = $SqlCredential }
        $serveur = Connect-DbaInstance @params

        Write-Log ("Instance : {0} — version {1} — édition {2} — compte de service {3}" -f `
                $serveur.DomainInstanceName, $serveur.VersionMajor, $serveur.Edition, $serveur.ServiceAccount)
        return $serveur
    }
    catch {
        Write-Log "Connexion impossible à $SqlInstance : $($_.Exception.Message)" -Level ERROR
        throw
    }
}

# --------------------------------------------------------------------------
# Réglages du moteur
# --------------------------------------------------------------------------

function Set-SqlInstanceConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Server)

    Write-Log 'Application des réglages du moteur.'

    Set-DbaErrorLogConfig -SqlInstance $Server -LogCount $ErrorLogCount | Out-Null

    # Socle de réglages, surchargeable par -SpConfigure.
    # Noms internes de sys.configurations, tels qu'utilisés en production.
    $reglages = [ordered]@{
        ShowAdvancedOptions          = 1
        RemoteDacConnectionsEnabled  = 1
        OptimizeAdhocWorkloads       = 1
        CostThresholdForParallelism  = 50
        DefaultBackupCompression     = 1
        BlockedProcessThreshold      = 1
        ContainmentEnabled           = 1
    }
    foreach ($cle in $SpConfigure.Keys) { $reglages[$cle] = $SpConfigure[$cle] }

    foreach ($cle in $reglages.Keys) {
        Set-DbaSpConfigure -SqlInstance $Server -Name $cle -Value $reglages[$cle] | Out-Null
        Write-Log "  sp_configure [$cle] = $($reglages[$cle])"
    }

    if (-not $SkipMaxMemoryAdjustment) {
        Write-Log 'Vérification de la mémoire maximale.'
        $memoire = Test-DbaMaxMemory -SqlInstance $Server
        if ($memoire.MaxValue -gt $memoire.Total) {
            Write-Log ("Mémoire maximale ({0} Mo) supérieure à la mémoire totale ({1} Mo) : ajustement." -f `
                    $memoire.MaxValue, $memoire.Total)
            Set-DbaMaxMemory -SqlInstance $Server | Out-Null
        }
        else {
            Write-Log ("Mémoire maximale laissée telle quelle : {0} Mo pour {1} Mo de RAM." -f `
                    $memoire.MaxValue, $memoire.Total)
        }
    }

    # Croissance en Mo plutôt qu'en pourcentage sur les bases système.
    Set-DbaDbFileGrowth -SqlInstance $Server -Database master, msdb -GrowthType MB -Growth 256 | Out-Null

    $versionMajeure = $Server.VersionMajor
    if ($versionMajeure -le 12) {
        Write-Log 'Activation des indicateurs de trace 1117, 1118 et 2371.'
        Enable-DbaTraceFlag -SqlInstance $Server -TraceFlag 1117, 1118, 2371 | Out-Null
    }
}

# --------------------------------------------------------------------------
# Sessions Extended Events
# --------------------------------------------------------------------------

function Set-SqlEventSessions {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Server)

    Write-Log 'Configuration des sessions Extended Events.'
    $versionMajeure = $Server.VersionMajor

    # Rétention des sessions système, sur les versions où elle n'est pas déjà correcte.
    if ($versionMajeure -le 14) {
        Invoke-ConfigurationStep -Name 'Rétention system_health' -Action {
            $session = Get-DbaXESession -SqlInstance $Server -Session 'system_health' -ErrorAction SilentlyContinue
            $etaitDemarree = $session -and $session.Status -eq 'Started'
            if ($etaitDemarree) {
                Stop-DbaXESession -SqlInstance $Server -Session 'system_health' | Out-Null
            }
            # Deux ALTER distincts : un seul lot ne peut pas déposer puis recréer la même cible.
            Invoke-DbaQuery -SqlInstance $Server -Database master -Query @'
ALTER EVENT SESSION [system_health] ON SERVER DROP TARGET package0.event_file;
'@ | Out-Null
            Invoke-DbaQuery -SqlInstance $Server -Database master -Query @'
ALTER EVENT SESSION [system_health] ON SERVER
ADD TARGET package0.event_file
    (SET filename = N'system_health.xel', max_file_size = (100), max_rollover_files = (10));
'@ | Out-Null
            if ($etaitDemarree) {
                Start-DbaXESession -SqlInstance $Server -Session 'system_health' | Out-Null
            }
        }

        # La session AlwaysOn_health n'existe pas sur une instance sans le rôle Availability Groups.
        Invoke-ConfigurationStep -Name 'Rétention AlwaysOn_health' -Action {
            $session = Get-DbaXESession -SqlInstance $Server -Session 'AlwaysOn_health' -ErrorAction SilentlyContinue
            if (-not $session) {
                Write-Log '  Session AlwaysOn_health absente : rien à faire.'
                return
            }

            $etaitDemarree = $session.Status -eq 'Started'
            if ($etaitDemarree) {
                Stop-DbaXESession -SqlInstance $Server -Session 'AlwaysOn_health' | Out-Null
            }
            Invoke-DbaQuery -SqlInstance $Server -Database master -Query @'
ALTER EVENT SESSION [AlwaysOn_health] ON SERVER DROP TARGET package0.event_file;
'@ | Out-Null
            Invoke-DbaQuery -SqlInstance $Server -Database master -Query @'
ALTER EVENT SESSION [AlwaysOn_health] ON SERVER
ADD TARGET package0.event_file
    (SET filename = N'AlwaysOn_health.xel', max_file_size = (100), max_rollover_files = (10));
'@ | Out-Null
            if ($etaitDemarree) {
                Start-DbaXESession -SqlInstance $Server -Session 'AlwaysOn_health' | Out-Null
            }
        }
    }

    if ($versionMajeure -lt 11) { return }

    # Le bruit security_error_ring_buffer_recorded encombre system_health sans valeur d'exploitation.
    Invoke-ConfigurationStep -Name 'Allègement system_health' -Action {
        Invoke-DbaQuery -SqlInstance $Server -Database master -Query @'
IF EXISTS (SELECT 1 FROM sys.server_event_sessions s
           JOIN sys.server_event_session_events e ON e.event_session_id = s.event_session_id
           WHERE s.name = N'system_health' AND e.name = N'sqlserver.security_error_ring_buffer_recorded')
    ALTER EVENT SESSION [system_health] ON SERVER DROP EVENT sqlserver.security_error_ring_buffer_recorded;
'@ | Out-Null
    }

    Invoke-ConfigurationStep -Name 'Session PerformanceIssues' -Action {
        Invoke-DbaQuery -SqlInstance $Server -Database master -Query @'
IF NOT EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'PerformanceIssues')
    CREATE EVENT SESSION [PerformanceIssues] ON SERVER
        ADD EVENT sqlserver.rpc_completed(SET collect_statement = (1)
            ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.database_id, sqlserver.database_name,
                sqlserver.query_hash, sqlserver.session_id, sqlserver.sql_text, sqlserver.username, sqlserver.transaction_id)
            WHERE ([package0].[greater_than_equal_uint64]([duration], (250000)))),
        ADD EVENT sqlserver.sql_batch_completed(
            ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.database_id, sqlserver.database_name,
                sqlserver.query_hash, sqlserver.session_id, sqlserver.sql_text, sqlserver.username, sqlserver.transaction_id)
            WHERE ([package0].[greater_than_equal_uint64]([duration], (250000)))),
        ADD EVENT sqlserver.blocked_process_report(
            ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.database_id, sqlserver.database_name,
                sqlserver.query_hash, sqlserver.session_id, sqlserver.sql_text, sqlserver.username, sqlserver.transaction_id)),
        ADD EVENT sqlserver.xml_deadlock_report(
            ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.database_id, sqlserver.database_name,
                sqlserver.query_hash, sqlserver.session_id, sqlserver.sql_text, sqlserver.username, sqlserver.transaction_id))
        ADD TARGET package0.event_file(SET filename = N'PerformanceIssues', max_file_size = (100), max_rollover_files = (10))
        WITH (MAX_MEMORY = 4096 KB, EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS, MAX_DISPATCH_LATENCY = 30 SECONDS,
              MAX_EVENT_SIZE = 0 KB, MEMORY_PARTITION_MODE = NONE, TRACK_CAUSALITY = ON, STARTUP_STATE = ON);
'@ | Out-Null

        $session = Get-DbaXESession -SqlInstance $Server -Session 'PerformanceIssues' -ErrorAction SilentlyContinue
        if ($session -and $session.Status -ne 'Started') {
            Start-DbaXESession -SqlInstance $Server -Session 'PerformanceIssues' | Out-Null
        }
    }

    # Croissance des fichiers de TempDB.
    Invoke-ConfigurationStep -Name 'Session TempDBAutogrowth' -Action {
        Invoke-DbaQuery -SqlInstance $Server -Database master -Query @'
IF NOT EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'TempDBAutogrowth')
    CREATE EVENT SESSION [TempDBAutogrowth] ON SERVER
        ADD EVENT sqlserver.database_file_size_change(
            ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.database_id,
                   sqlserver.database_name, sqlserver.session_id, sqlserver.sql_text, sqlserver.transaction_id)
            WHERE ([database_id] = (2))),
        ADD EVENT sqlserver.databases_log_file_size_changed(
            ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.database_id,
                   sqlserver.database_name, sqlserver.session_id, sqlserver.sql_text, sqlserver.transaction_id)
            WHERE ([database_id] = (2))),
        ADD EVENT sqlserver.error_reported(
            ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.database_id, sqlserver.plan_handle,
                   sqlserver.session_id, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)
            WHERE ([database_id] = (2) AND ([error_number] = (1101) OR [error_number] = (1105))))
        ADD TARGET package0.event_file(SET filename = N'TempDBAutogrowth', max_file_size = (10), max_rollover_files = (5))
        WITH (MAX_MEMORY = 4096 KB, EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS, MAX_DISPATCH_LATENCY = 30 SECONDS,
              MAX_EVENT_SIZE = 0 KB, MEMORY_PARTITION_MODE = NONE, TRACK_CAUSALITY = ON, STARTUP_STATE = ON);
'@ | Out-Null

        $session = Get-DbaXESession -SqlInstance $Server -Session 'TempDBAutogrowth' -ErrorAction SilentlyContinue
        if ($session -and $session.Status -ne 'Started') {
            Start-DbaXESession -SqlInstance $Server -Session 'TempDBAutogrowth' | Out-Null
        }
    }

    # Croissance des journaux de base utilisateur.
    Invoke-ConfigurationStep -Name 'Session UserDBLogAutogrowth' -Action {
        Invoke-DbaQuery -SqlInstance $Server -Database master -Query @'
IF NOT EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'UserDBLogAutogrowth')
    CREATE EVENT SESSION [UserDBLogAutogrowth] ON SERVER
        ADD EVENT sqlserver.databases_log_file_size_changed(
            ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.database_id,
                   sqlserver.database_name, sqlserver.session_id, sqlserver.sql_text, sqlserver.transaction_id)
            WHERE ([database_id] > (4)))
        ADD TARGET package0.event_file(SET filename = N'UserDBLogAutogrowth', max_file_size = (10), max_rollover_files = (5))
        WITH (MAX_MEMORY = 4096 KB, EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS, MAX_DISPATCH_LATENCY = 30 SECONDS,
              MAX_EVENT_SIZE = 0 KB, MEMORY_PARTITION_MODE = NONE, TRACK_CAUSALITY = ON, STARTUP_STATE = ON);
'@ | Out-Null

        $session = Get-DbaXESession -SqlInstance $Server -Session 'UserDBLogAutogrowth' -ErrorAction SilentlyContinue
        if ($session -and $session.Status -ne 'Started') {
            Start-DbaXESession -SqlInstance $Server -Session 'UserDBLogAutogrowth' | Out-Null
        }
    }

    # Traçage des connexions du compte sa.
    Invoke-ConfigurationStep -Name 'Session AuditLoginSA' -Action {
        Invoke-DbaQuery -SqlInstance $Server -Database master -Query @'
IF NOT EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'AuditLoginSA')
    CREATE EVENT SESSION [AuditLoginSA] ON SERVER
        ADD EVENT sqlserver.login(
            ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid,
                sqlserver.database_id, sqlserver.database_name,
                sqlserver.session_id, sqlserver.sql_text, sqlserver.username)
            WHERE ([sqlserver].[username] = N'sa'))
        ADD TARGET package0.event_file(SET filename = N'AuditLoginSA', max_file_size = (20))
        WITH (STARTUP_STATE = ON);
'@ | Out-Null

        $session = Get-DbaXESession -SqlInstance $Server -Session 'AuditLoginSA' -ErrorAction SilentlyContinue
        if ($session -and $session.Status -ne 'Started') {
            Start-DbaXESession -SqlInstance $Server -Session 'AuditLoginSA' | Out-Null
        }
    }
}

# --------------------------------------------------------------------------
# Audit DDL
# --------------------------------------------------------------------------

function Set-SqlAuditing {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Server)

    Write-Log 'Configuration de l''audit DDL.'

    $auditExiste = (Invoke-DbaQuery -SqlInstance $Server -Database master -Query @'
SELECT COUNT(*) AS [Existe] FROM sys.server_audits WHERE name = N'Audit-DDL';
'@).Existe

    if ($auditExiste -eq 0) {
        # Le fichier d'audit suit le répertoire des journaux d'erreurs de l'instance.
        $cmd = @"
CREATE SERVER AUDIT [Audit-DDL]
TO FILE (
    FILEPATH = N'$($Server.ErrorLogPath)',
    MAXSIZE = 100 MB,
    MAX_ROLLOVER_FILES = 10,
    RESERVE_DISK_SPACE = OFF
)
WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE)
WHERE ([Object_Name] <> 'telemetry_xevents' AND [server_principal_name] NOT LIKE '%SQLTELEMETRY%')
  AND NOT (class_type = 19267 AND action_id = 8278);
ALTER SERVER AUDIT [Audit-DDL] WITH (STATE = ON);
"@
        Invoke-DbaQuery -SqlInstance $Server -Query $cmd | Out-Null
        Write-Log '  Audit [Audit-DDL] créé et activé.'
    }
    else {
        Write-Log '  Audit [Audit-DDL] déjà présent : conservé.'
    }

    $specExiste = (Invoke-DbaQuery -SqlInstance $Server -Database master -Query @'
SELECT COUNT(*) AS [Existe] FROM sys.server_audit_specifications WHERE name = N'AuditSpecification-DDL';
'@).Existe

    if ($specExiste -eq 0) {
        $cmd = @"
CREATE SERVER AUDIT SPECIFICATION [AuditSpecification-DDL]
FOR SERVER AUDIT [Audit-DDL]
    ADD (DATABASE_OBJECT_CHANGE_GROUP),
    ADD (DATABASE_OBJECT_OWNERSHIP_CHANGE_GROUP),
    ADD (DATABASE_OBJECT_PERMISSION_CHANGE_GROUP),
    ADD (DATABASE_OWNERSHIP_CHANGE_GROUP),
    ADD (DATABASE_PERMISSION_CHANGE_GROUP),
    ADD (DATABASE_PRINCIPAL_CHANGE_GROUP),
    ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),
    ADD (LOGIN_CHANGE_PASSWORD_GROUP),
    ADD (SERVER_OBJECT_CHANGE_GROUP),
    ADD (SERVER_OBJECT_OWNERSHIP_CHANGE_GROUP),
    ADD (SERVER_OBJECT_PERMISSION_CHANGE_GROUP),
    ADD (SERVER_PERMISSION_CHANGE_GROUP),
    ADD (SERVER_PRINCIPAL_CHANGE_GROUP),
    ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP)
WITH (STATE = ON);
"@
        Invoke-DbaQuery -SqlInstance $Server -Query $cmd | Out-Null
        Write-Log '  Spécification [AuditSpecification-DDL] créée et activée.'
    }
    else {
        Write-Log '  Spécification [AuditSpecification-DDL] déjà présente : conservée.'
    }
}

# --------------------------------------------------------------------------
# Agent SQL
# --------------------------------------------------------------------------

function Set-SqlAgentConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Server)

    Write-Log 'Réglages de l''Agent SQL.'

    # Rétention étendue de l'historique : les incidents se diagnostiquent après coup.
    Set-DbaAgentServer -SqlInstance $Server -MaximumHistoryRows 999999 -MaximumJobHistoryRows 999999 | Out-Null

    # Le job de purge de la stratégie système rejoint la catégorie de maintenance,
    # ce qui le fait apparaître dans les mêmes vues que les jobs Ola.
    Invoke-ConfigurationStep -Name 'Catégorie syspolicy_purge_history' -Action {
        Set-DbaAgentJob -SqlInstance $Server -Job 'syspolicy_purge_history' -Category 'Database Maintenance' | Out-Null
    }
}

# --------------------------------------------------------------------------
# Base d'administration, outillage, solution de maintenance
# --------------------------------------------------------------------------

function Initialize-DbaDatabase {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Server)

    $base = Get-DbaDatabase -SqlInstance $Server -Database $DbaDatabase -ErrorAction SilentlyContinue
    if ($base) {
        Write-Log "Base [$DbaDatabase] déjà présente."
        return
    }

    New-DbaDatabase -SqlInstance $Server -Name $DbaDatabase -Owner sa -RecoveryModel Simple | Out-Null
    Write-Log "Base [$DbaDatabase] créée."
}

function Install-CommunityToolkit {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Server)

    Write-Log 'Installation de l''outillage communautaire.'

    Invoke-ConfigurationStep -Name 'sp_WhoIsActive' -Action {
        Install-DbaWhoIsActive -SqlInstance $Server -Database $DbaDatabase | Out-Null
    }

    Invoke-ConfigurationStep -Name 'First Responder Kit' -Action {
        Install-DbaFirstResponderKit -SqlInstance $Server -Database $DbaDatabase | Out-Null
    }
}

function Install-MaintenanceSolution {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Server)

    Write-Log 'Déploiement de la solution Ola Hallengren.'

    $emplacement = if ([string]::IsNullOrWhiteSpace($BackupDirectory)) { $Server.BackupDirectory } else { $BackupDirectory }
    Write-Log "  Répertoire de sauvegarde retenu : $emplacement"

    Install-DbaMaintenanceSolution -SqlInstance $Server -Database $DbaDatabase `
        -CleanupTime $BackupCleanupHours -BackupLocation $emplacement `
        -InstallJobs -LogToTable -ReplaceExisting -Force | Out-Null

    # Procédure d'attente de fin de job, utilisée par les jobs de séquencement.
    Invoke-ConfigurationStep -Name 'Procédure sp_sp_start_job_wait' -Action {
        $tSql = @'
CREATE OR ALTER PROCEDURE dbo.sp_sp_start_job_wait
(
    @job_name SYSNAME,
    @WaitTime DATETIME = '00:00:30',
    @JobCompletionStatus INT = NULL OUTPUT
)
AS
BEGIN
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    SET NOCOUNT ON;

    DECLARE @job_id UNIQUEIDENTIFIER;
    DECLARE @job_owner SYSNAME;

    CREATE TABLE #xp_results (
        job_id UNIQUEIDENTIFIER NOT NULL,
        last_run_date INT NOT NULL,
        last_run_time INT NOT NULL,
        next_run_date INT NOT NULL,
        next_run_time INT NOT NULL,
        next_run_schedule_id INT NOT NULL,
        requested_to_run INT NOT NULL,
        request_source INT NOT NULL,
        request_source_id SYSNAME COLLATE database_default NULL,
        running INT NOT NULL,
        current_step INT NOT NULL,
        current_retry_attempt INT NOT NULL,
        job_state INT NOT NULL
    );

    SELECT @job_id = job_id FROM msdb.dbo.sysjobs WHERE name = @job_name;
    SELECT @job_owner = SUSER_SNAME();

    INSERT INTO #xp_results
    EXECUTE master.dbo.xp_sqlagent_enum_jobs 1, @job_owner, @job_id;

    IF NOT EXISTS (SELECT TOP 1 * FROM #xp_results WHERE running = 1)
        EXEC msdb.dbo.sp_start_job @job_name = @job_name;

    WAITFOR DELAY '00:00:05';

    DELETE FROM #xp_results;
    INSERT INTO #xp_results
    EXECUTE master.dbo.xp_sqlagent_enum_jobs 1, @job_owner, @job_id;

    WHILE EXISTS (SELECT TOP 1 * FROM #xp_results WHERE running = 1)
    BEGIN
        WAITFOR DELAY @WaitTime;
        DELETE FROM #xp_results;
        INSERT INTO #xp_results
        EXECUTE master.dbo.xp_sqlagent_enum_jobs 1, @job_owner, @job_id;
    END

    SELECT TOP 1 @JobCompletionStatus = run_status
    FROM msdb.dbo.sysjobhistory
    WHERE job_id = @job_id AND step_id = 0
    ORDER BY run_date DESC, run_time DESC;

    IF @JobCompletionStatus <> 1
        RAISERROR ('[ERROR]:%s job is either failed, cancelled or not in good state. Please check', 16, 1, @job_name) WITH LOG;

    RETURN @JobCompletionStatus;
END
'@
        Invoke-DbaQuery -SqlInstance $Server -Database $DbaDatabase -Query $tSql | Out-Null
    }

    # IndexOptimize : verrouillage court, journalisation, messages non bloquants.
    Invoke-ConfigurationStep -Name 'Réglages IndexOptimize' -Action {
        $tSql = Get-DbaDbStoredProcedure -SqlInstance $Server -Database $DbaDatabase -Name 'IndexOptimize' |
            Export-DbaScript -Passthru
        $tSql = $tSql.Replace('CREATE PROCEDURE', 'ALTER PROCEDURE')
        $tSql = $tSql.Replace('@LockTimeout int = NULL', '@LockTimeout int = 1')
        $tSql = $tSql.Replace('@LockMessageSeverity int = 16', '@LockMessageSeverity int = 10')
        $tSql = $tSql.Replace("@LogToTable nvarchar(max) = 'N'", "@LogToTable nvarchar(max) = 'Y'")
        Invoke-DbaQuery -SqlInstance $Server -Database $DbaDatabase -Query (-join $tSql) | Out-Null
    }
}

# --------------------------------------------------------------------------
# Jobs d'exploitation
# --------------------------------------------------------------------------

function New-HousekeepingJob {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Server)

    Write-Log 'Création du job de maintenance courante.'

    $job = New-DbaAgentJob -SqlInstance $Server -Job '_DBA - HouseKeeping' `
        -Category 'Database Maintenance' -OwnerLogin sa -Force

    New-DbaAgentSchedule -SqlInstance $Server -Schedule $job.Name -Job $job.Name `
        -FrequencyType Daily -FrequencyInterval Everyday `
        -FrequencySubdayType Time -FrequencySubDayinterval 0 `
        -StartTime '000001' -EndTime '235959' -Force | Out-Null

    $etapes = @(
        @{ Name = 'Cycle Errorlog'; Command = 'EXEC msdb.dbo.sp_cycle_errorlog'; Action = 'GoToNextStep' }
        @{ Name = 'DatabaseIntegrityCheck - SYSTEM_DATABASES'; Command = "EXEC [$DbaDatabase].[dbo].sp_sp_start_job_wait @job_name = 'DatabaseIntegrityCheck - SYSTEM_DATABASES', @WaitTime = '00:01:00'"; Action = 'GoToNextStep' }
        @{ Name = 'DatabaseBackup - SYSTEM_DATABASES - FULL'; Command = "EXEC [$DbaDatabase].[dbo].sp_sp_start_job_wait @job_name = 'DatabaseBackup - SYSTEM_DATABASES - FULL', @WaitTime = '00:01:00'"; Action = 'GoToNextStep' }
        @{ Name = 'CommandLog Cleanup'; Command = "EXEC msdb.dbo.sp_start_job 'CommandLog Cleanup'"; Action = 'GoToNextStep' }
        @{ Name = 'Output File Cleanup'; Command = "EXEC msdb.dbo.sp_start_job 'Output File Cleanup'"; Action = 'GoToNextStep' }
        @{ Name = 'sp_delete_backuphistory'; Command = "EXEC [$DbaDatabase].[dbo].sp_sp_start_job_wait @job_name = 'sp_delete_backuphistory', @WaitTime = '00:01:00'"; Action = 'GoToNextStep' }
        @{ Name = 'sp_purge_jobhistory'; Command = "EXEC [$DbaDatabase].[dbo].sp_sp_start_job_wait @job_name = 'sp_purge_jobhistory', @WaitTime = '00:01:00'"; Action = 'GoToNextStep' }
    )

    $numero = 1
    foreach ($etape in $etapes) {
        New-DbaAgentJobStep -SqlInstance $Server -Job $job.Name -StepName $etape.Name -StepId $numero `
            -Database master -Subsystem 'TransactSql' -Command $etape.Command `
            -OnSuccessAction $etape.Action -OnFailAction 'GoToNextStep' -Force | Out-Null
        $numero++
    }

    # Purge des courriels et du journal Database Mail au-delà de 30 jours.
    New-DbaAgentJobStep -SqlInstance $Server -Job $job.Name -StepName 'DatabaseMail - Database Mail cleanup' -StepId $numero `
        -Database master -Subsystem 'TransactSql' `
        -Command "DECLARE @DeleteBeforeDate DATETIME = (SELECT DATEADD(d, -30, GETDATE()));
                  EXEC msdb.dbo.sysmail_delete_mailitems_sp @sent_before = @DeleteBeforeDate;
                  EXEC msdb.dbo.sysmail_delete_log_sp @logged_before = @DeleteBeforeDate" `
        -OnSuccessAction 'QuitWithSuccess' -OnFailAction 'QuitWithFailure' -Force | Out-Null
}

function New-BackupJobs {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Server)

    Write-Log 'Création des jobs de sauvegarde.'

    # --- Complète ---
    $complet = New-DbaAgentJob -SqlInstance $Server -Job '_DBA - USER_DATABASES - FULL' `
        -Category 'Database Maintenance' -OwnerLogin sa -Force

    if ($BackupStrategy -eq 'FullDiffLog') {
        New-DbaAgentSchedule -SqlInstance $Server -Schedule $complet.Name -Job $complet.Name `
            -FrequencyType Weekly -FrequencyInterval Sunday `
            -FrequencySubdayType Time -FrequencySubDayinterval 0 -FrequencyRecurrenceFactor 1 `
            -StartTime '010000' -EndTime '235959' -Force | Out-Null
    }
    else {
        New-DbaAgentSchedule -SqlInstance $Server -Schedule $complet.Name -Job $complet.Name `
            -FrequencyType Daily -FrequencyInterval EveryDay `
            -FrequencySubdayType Time -FrequencySubDayinterval 0 -FrequencyRecurrenceFactor 1 `
            -StartTime '010000' -EndTime '235959' -Force | Out-Null
    }

    New-DbaAgentJobStep -SqlInstance $Server -Job $complet.Name -StepName 'DatabaseIntegrityCheck - USER_DATABASES' -StepId 1 `
        -Database master -Subsystem 'TransactSql' `
        -Command "EXEC [$DbaDatabase].[dbo].sp_sp_start_job_wait @job_name = 'DatabaseIntegrityCheck - USER_DATABASES', @WaitTime = '00:01:00'" `
        -OnSuccessAction 'GoToNextStep' -OnFailAction 'GoToNextStep' -Force | Out-Null

    New-DbaAgentJobStep -SqlInstance $Server -Job $complet.Name -StepName 'IndexOptimize - USER_DATABASES' -StepId 2 `
        -Database master -Subsystem 'TransactSql' `
        -Command "EXEC [$DbaDatabase].[dbo].sp_sp_start_job_wait @job_name = 'IndexOptimize - USER_DATABASES', @WaitTime = '00:01:00'" `
        -OnSuccessAction 'GoToNextStep' -OnFailAction 'GoToNextStep' -Force | Out-Null

    New-DbaAgentJobStep -SqlInstance $Server -Job $complet.Name -StepName 'DatabaseBackup - USER_DATABASES - FULL' -StepId 3 `
        -Database master -Subsystem 'TransactSql' `
        -Command "EXEC [$DbaDatabase].[dbo].sp_sp_start_job_wait @job_name = 'DatabaseBackup - USER_DATABASES - FULL', @WaitTime = '00:01:00'" `
        -OnSuccessAction 'QuitWithSuccess' -OnFailAction 'QuitWithFailure' -Force | Out-Null

    # --- Différentielle (désactivée en stratégie FullLog) ---
    $differentielle = New-DbaAgentJob -SqlInstance $Server -Job '_DBA - USER_DATABASES - DIFF' `
        -Category 'Database Maintenance' -OwnerLogin sa -Force

    if ($BackupStrategy -eq 'FullLog') {
        Set-DbaAgentJob -SqlInstance $Server -Job $differentielle.Name -Disabled | Out-Null
    }

    New-DbaAgentSchedule -SqlInstance $Server -Schedule $differentielle.Name -Job $differentielle.Name `
        -FrequencyType Weekly -FrequencyInterval Monday, Tuesday, Wednesday, Thursday, Friday, Saturday `
        -FrequencySubdayType Time -FrequencySubDayinterval 0 -FrequencyRecurrenceFactor 1 `
        -StartTime '010000' -EndTime '235959' -Force | Out-Null

    New-DbaAgentJobStep -SqlInstance $Server -Job $differentielle.Name -StepName 'DatabaseIntegrityCheck - USER_DATABASES' -StepId 1 `
        -Database master -Subsystem 'TransactSql' `
        -Command "EXEC [$DbaDatabase].[dbo].sp_sp_start_job_wait @job_name = 'DatabaseIntegrityCheck - USER_DATABASES', @WaitTime = '00:01:00'" `
        -OnSuccessAction 'GoToNextStep' -OnFailAction 'GoToNextStep' -Force | Out-Null

    New-DbaAgentJobStep -SqlInstance $Server -Job $differentielle.Name -StepName 'IndexOptimize - USER_DATABASES' -StepId 2 `
        -Database master -Subsystem 'TransactSql' `
        -Command "EXEC [$DbaDatabase].[dbo].sp_sp_start_job_wait @job_name = 'IndexOptimize - USER_DATABASES', @WaitTime = '00:01:00'" `
        -OnSuccessAction 'GoToNextStep' -OnFailAction 'GoToNextStep' -Force | Out-Null

    New-DbaAgentJobStep -SqlInstance $Server -Job $differentielle.Name -StepName 'DatabaseBackup - USER_DATABASES - DIFF' -StepId 3 `
        -Database master -Subsystem 'TransactSql' `
        -Command "EXEC [$DbaDatabase].[dbo].sp_sp_start_job_wait @job_name = 'DatabaseBackup - USER_DATABASES - DIFF', @WaitTime = '00:01:00'" `
        -OnSuccessAction 'QuitWithSuccess' -OnFailAction 'QuitWithFailure' -Force | Out-Null

    # --- Journaux de transactions ---
    $journal = New-DbaAgentJob -SqlInstance $Server -Job '_DBA - USER_DATABASES - LOG' `
        -Category 'Database Maintenance' -OwnerLogin sa -Force

    New-DbaAgentSchedule -SqlInstance $Server -Schedule $journal.Name -Job $journal.Name `
        -FrequencyType Daily -FrequencyInterval EveryDay `
        -FrequencySubdayType Minutes -FrequencySubDayinterval 30 `
        -StartTime '001500' -EndTime '235959' -Force | Out-Null

    New-DbaAgentJobStep -SqlInstance $Server -Job $journal.Name -StepName 'DatabaseBackup - USER_DATABASES - LOG' -StepId 1 `
        -Database master -Subsystem 'TransactSql' `
        -Command "EXEC msdb.dbo.sp_start_job 'DatabaseBackup - USER_DATABASES - LOG'" `
        -OnSuccessAction 'QuitWithSuccess' -OnFailAction 'QuitWithFailure' -Force | Out-Null
}

function Enable-InstanceMonitoring {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Server)

    Write-Log 'Installation de la supervision d''instance.'

    $tSql = @"
IF OBJECT_ID(N'$DbaDatabase.dbo.TlogUsage') IS NULL
    CREATE TABLE [dbo].[TlogUsage] (
        [CollectTime] [datetime] NOT NULL,
        [Instance] [nvarchar](128) NULL,
        [Database Name] [sysname] NOT NULL,
        [Recovery Model] [nvarchar](60) NULL,
        [LogReuseWaitDescription] [nvarchar](60) NULL,
        [LogSize(MB)] [decimal](18, 2) NULL,
        [LogUsed(MB)] [decimal](18, 2) NULL,
        [LogUsed%] [decimal](22, 2) NULL,
        INDEX [CI_TlogUsage_CollectTime] CLUSTERED ([CollectTime])
    );

IF OBJECT_ID(N'$DbaDatabase.dbo.TempDBUsage') IS NULL
    CREATE TABLE [dbo].[TempDBUsage] (
        [CollectTime] [datetime] NOT NULL,
        [usr_obj_kb] INT NULL,
        [internal_obj_kb] INT NULL,
        [version_store_kb] INT NULL,
        [freespace_kb] INT NULL,
        [mixedextent_kb] INT NULL,
        INDEX [CI_TempDBUsage_CollectTime] CLUSTERED ([CollectTime])
    );

IF OBJECT_ID(N'$DbaDatabase.dbo.CpuUtilizationHistory') IS NULL
    CREATE TABLE [dbo].[CpuUtilizationHistory] (
        [Event Time] [datetime] NOT NULL,
        [Instance] [nvarchar](128) NULL,
        [SQL Server Process CPU Utilization] [tinyint] NOT NULL,
        [System Idle Process] [tinyint] NULL,
        [Other Process CPU Utilization] [tinyint] NULL,
        INDEX [CI_CpuUtilizationHistory_EventTime] CLUSTERED ([Event Time])
    );
"@
    Invoke-DbaQuery -SqlInstance $Server -Database $DbaDatabase -Query $tSql | Out-Null

    $job = New-DbaAgentJob -SqlInstance $Server -Job '_DBA - Instance Monitoring' `
        -Category 'Database Maintenance' -OwnerLogin sa -Force

    New-DbaAgentSchedule -SqlInstance $Server -Schedule $job.Name -Job $job.Name `
        -FrequencyType Daily -FrequencyInterval Everyday `
        -FrequencySubdayType Minutes -FrequencySubDayinterval $MonitoringIntervalMinutes `
        -StartTime '000100' -EndTime '235959' -Force | Out-Null

    New-DbaAgentJobStep -SqlInstance $Server -Job $job.Name -StepName '_DBA - TempDBUsage' -StepId 1 `
        -Database master -Subsystem 'TransactSql' `
        -Command @"
INSERT INTO $DbaDatabase.dbo.TempDBUsage
SELECT GETDATE() AS CollectTime,
       SUM(user_object_reserved_page_count) * 8 AS usr_obj_kb,
       SUM(internal_object_reserved_page_count) * 8 AS internal_obj_kb,
       SUM(version_store_reserved_page_count) * 8 AS version_store_kb,
       SUM(unallocated_extent_page_count) * 8 AS freespace_kb,
       SUM(mixed_extent_page_count) * 8 AS mixedextent_kb
FROM tempdb.sys.dm_db_file_space_usage;

DELETE FROM $DbaDatabase.dbo.TempDBUsage
WHERE CollectTime < DATEADD(DAY, -$MonitoringCleanupDays, GETDATE());
"@ -OnSuccessAction 'GoToNextStep' -OnFailAction 'QuitWithFailure' -Force | Out-Null

    New-DbaAgentJobStep -SqlInstance $Server -Job $job.Name -StepName '_DBA - Log TLog Reuse Wait' -StepId 2 `
        -Database master -Subsystem 'TransactSql' `
        -Command @"
INSERT INTO $DbaDatabase.dbo.TlogUsage
SELECT GETDATE() AS CollectTime, @@SERVERNAME AS Instance, db.[name] AS [Database Name],
       db.recovery_model_desc AS [Recovery Model], db.log_reuse_wait_desc AS [LogReuseWaitDescription],
       CONVERT(DECIMAL(18, 2), ls.cntr_value / 1024.0) AS [Log Size (MB)],
       CONVERT(DECIMAL(18, 2), lu.cntr_value / 1024.0) AS [Log Used (MB)],
       CAST(CAST(lu.cntr_value AS FLOAT) / CAST(ls.cntr_value AS FLOAT) AS DECIMAL(18, 2)) * 100 AS [LogUsed%]
FROM sys.databases AS db WITH (NOLOCK)
INNER JOIN sys.dm_os_performance_counters AS lu WITH (NOLOCK) ON db.name = lu.instance_name
INNER JOIN sys.dm_os_performance_counters AS ls WITH (NOLOCK) ON db.name = ls.instance_name
WHERE lu.counter_name LIKE N'Log File(s) Used Size (KB)%'
  AND ls.counter_name LIKE N'Log File(s) Size (KB)%'
  AND ls.cntr_value > 0
  AND db.database_id > 4;

DELETE FROM $DbaDatabase.dbo.TlogUsage
WHERE CollectTime < DATEADD(DAY, -$MonitoringCleanupDays, GETDATE());
"@ -OnSuccessAction 'GoToNextStep' -OnFailAction 'QuitWithFailure' -Force | Out-Null

    New-DbaAgentJobStep -SqlInstance $Server -Job $job.Name -StepName '_DBA - Log CPU Utilization' -StepId 3 `
        -Database master -Subsystem 'TransactSql' `
        -Command @"
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @ts_now BIGINT = (SELECT cpu_ticks / (cpu_ticks / ms_ticks) FROM sys.dm_os_sys_info WITH (NOLOCK));
WITH RawData AS (
    SELECT SQLProcessUtilization AS [SQLServerProcessCPUUtilization],
           SystemIdle AS [SystemIdleProcess],
           100 - SystemIdle - SQLProcessUtilization AS [OtherProcessCPUUtilization],
           DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) AS [EventTime]
    FROM (SELECT record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS [SystemIdle],
                 record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS [SQLProcessUtilization],
                 [timestamp]
          FROM (SELECT TOP ($($MonitoringIntervalMinutes + 1)) [timestamp], CONVERT(XML, record) AS [record]
                FROM sys.dm_os_ring_buffers WITH (NOLOCK)
                WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
                  AND record LIKE N'%<SystemHealth>%'
                ORDER BY [timestamp] DESC) AS x) AS y
)
MERGE $DbaDatabase.dbo.CpuUtilizationHistory AS t
USING (SELECT [EventTime], @@SERVERNAME AS Instance, [SQLServerProcessCPUUtilization],
              [SystemIdleProcess], [OtherProcessCPUUtilization]
       FROM RawData) AS s
    ON t.[Event Time] = s.[EventTime]
WHEN NOT MATCHED THEN
    INSERT VALUES ([EventTime], [Instance], [SQLServerProcessCPUUtilization], [SystemIdleProcess], [OtherProcessCPUUtilization]);

DELETE FROM $DbaDatabase.dbo.CpuUtilizationHistory
WHERE [Event Time] < DATEADD(DAY, -$MonitoringCleanupDays, GETDATE());
"@ -OnSuccessAction 'GoToNextStep' -OnFailAction 'QuitWithFailure' -Force | Out-Null

    New-DbaAgentJobStep -SqlInstance $Server -Job $job.Name -StepName '_DBA - Purge job history' -StepId 4 `
        -Database master -Subsystem 'TransactSql' `
        -Command @"
DECLARE @oldest DATETIME = DATEADD(MINUTE, -60, GETDATE());
DECLARE @name SYSNAME;
SELECT @name = (SELECT name FROM msdb.dbo.sysjobs WHERE job_id = CONVERT(UNIQUEIDENTIFIER, `$(ESCAPE_NONE(JOBID))));
EXEC msdb.dbo.sp_purge_jobhistory @job_name = @name, @oldest_date = @oldest;
"@ -OnSuccessAction 'QuitWithSuccess' -OnFailAction 'QuitWithFailure' -Force | Out-Null
}

# --------------------------------------------------------------------------
# Contrôles de fin
# --------------------------------------------------------------------------

function Test-ConfiguredInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Server)

    Write-Log 'Contrôles de fin.'

    Write-Log 'Latence réseau vers l''instance.'
    try {
        Test-DbaNetworkLatency -SqlInstance $Server -Count 10 -Query 'SELECT @@SERVERNAME, @@VERSION' |
            Format-List | Out-String | Write-Output
    }
    catch {
        Write-Log "Mesure de latence indisponible : $($_.Exception.Message)" -Level WARN
    }

    Write-Log 'Planification des jobs de maintenance.'
    $jobs = Get-DbaAgentJob -SqlInstance $Server -Category 'Database Maintenance'
    $planifications = Get-DbaAgentSchedule -SqlInstance $Server

    $lignes = foreach ($unJob in $jobs) {
        $nomPlanification = if ($unJob.JobSchedules) { $unJob.JobSchedules[0] } else { $null }
        $planification = $planifications | Where-Object { $_.ScheduleName -eq $nomPlanification } | Select-Object -First 1
        [pscustomobject]@{
            Job         = $unJob.Name
            Prochaine   = $unJob.NextRunDate
            Planification = $planification.Description
        }
    }
    $lignes | Format-Table -AutoSize | Out-String | Write-Output

    if ($Server.HostPlatform -ne 'Windows') { return }

    Write-Log 'Vérification de la configuration Kerberos.'
    try {
        $auth = Test-DbaConnectionAuthScheme -SqlInstance $Server
        if ($auth.AuthScheme -eq 'NTLM') {
            $port = Get-DbaTcpPort -SqlInstance $Server
            $reseau = Resolve-DbaNetworkName -ComputerName $Server.Name -Turbo
            $compte = $Server.ServiceAccount
            if ($compte -match 'NT Service') {
                $compte = "$($reseau.Domain)\$($Server.ComputerName)$"
            }

            Write-Log "  NTLM détecté : enregistrez les SPN suivants." -Level WARN
            if ($Server.ServiceName -eq 'MSSQLSERVER') {
                Write-Host "  setspn -s MSSQLSvc/$($reseau.ComputerName):$($port.Port) $compte"
                Write-Host "  setspn -s MSSQLSvc/$($reseau.DNSHostEntry):$($port.Port) $compte"
            }
            else {
                Write-Host "  setspn -s MSSQLSvc/$($reseau.ComputerName):$($port.Port) $compte"
                Write-Host "  setspn -s MSSQLSvc/$($reseau.ComputerName):$($Server.ServiceName) $compte"
                Write-Host "  setspn -s MSSQLSvc/$($reseau.DNSHostEntry):$($port.Port) $compte"
                Write-Host "  setspn -s MSSQLSvc/$($reseau.DNSHostEntry):$($Server.ServiceName) $compte"
            }
        }
        else {
            Write-Log "  Kerberos en place ($($auth.AuthScheme))."
        }
    }
    catch {
        Write-Log "Contrôle Kerberos impossible : $($_.Exception.Message)" -Level WARN
    }
}

# --------------------------------------------------------------------------
# Exécution
# --------------------------------------------------------------------------

$scriptVersion = '2.0.0'

$serveur = $null
try {
    Write-Log "=== Configuration de $SqlInstance — script v$scriptVersion ==="

    Initialize-DbaToolsModule
    $serveur = Connect-SqlTarget

    $estExpress = $serveur.Edition -match 'Express'
    if ($estExpress) {
        Write-Log 'Édition Express : Agent SQL, audits et jobs seront ignorés.' -Level WARN
    }

    if ($PSCmdlet.ShouldProcess($SqlInstance, 'Appliquer les réglages du moteur')) {
        Invoke-ConfigurationStep -Name 'Réglages du moteur' -Action { Set-SqlInstanceConfiguration -Server $serveur }
    }

    if (-not $SkipEventSessions -and $PSCmdlet.ShouldProcess($SqlInstance, 'Configurer les sessions Extended Events')) {
        Invoke-ConfigurationStep -Name 'Sessions Extended Events' -Action { Set-SqlEventSessions -Server $serveur }
    }

    if (-not $SkipAudit -and -not $estExpress -and $PSCmdlet.ShouldProcess($SqlInstance, 'Configurer l''audit DDL')) {
        Invoke-ConfigurationStep -Name 'Audit DDL' -Action { Set-SqlAuditing -Server $serveur }
    }

    if (-not $estExpress -and $PSCmdlet.ShouldProcess($SqlInstance, 'Régler l''Agent SQL')) {
        Invoke-ConfigurationStep -Name 'Agent SQL' -Action { Set-SqlAgentConfiguration -Server $serveur }
    }

    if ($PSCmdlet.ShouldProcess($SqlInstance, "Créer la base [$DbaDatabase]")) {
        Invoke-ConfigurationStep -Name 'Base d''administration' -Action { Initialize-DbaDatabase -Server $serveur }
    }

    if (-not $SkipCommunityTools -and $PSCmdlet.ShouldProcess($SqlInstance, 'Installer l''outillage communautaire')) {
        Invoke-ConfigurationStep -Name 'Outillage communautaire' -Action { Install-CommunityToolkit -Server $serveur }
    }

    if (-not $SkipMaintenanceSolution -and -not $estExpress -and $PSCmdlet.ShouldProcess($SqlInstance, 'Déployer la solution de maintenance')) {
        Invoke-ConfigurationStep -Name 'Solution de maintenance' -Action { Install-MaintenanceSolution -Server $serveur }
    }

    if (-not $SkipHousekeepingJob -and -not $estExpress -and $PSCmdlet.ShouldProcess($SqlInstance, 'Créer le job de maintenance courante')) {
        Invoke-ConfigurationStep -Name 'Job de maintenance courante' -Action { New-HousekeepingJob -Server $serveur }
    }

    if (-not $SkipBackupJobs -and -not $estExpress -and $PSCmdlet.ShouldProcess($SqlInstance, 'Créer les jobs de sauvegarde')) {
        Invoke-ConfigurationStep -Name 'Jobs de sauvegarde' -Action { New-BackupJobs -Server $serveur }
    }

    if (-not $SkipMonitoring -and -not $estExpress -and $PSCmdlet.ShouldProcess($SqlInstance, 'Installer la supervision')) {
        Invoke-ConfigurationStep -Name 'Supervision' -Action { Enable-InstanceMonitoring -Server $serveur }
    }

    if (-not $SkipFinalChecks -and $PSCmdlet.ShouldProcess($SqlInstance, 'Exécuter les contrôles de fin')) {
        Invoke-ConfigurationStep -Name 'Contrôles de fin' -Action { Test-ConfiguredInstance -Server $serveur }
    }

    Write-Log 'Configuration terminée.'
}
catch {
    Write-Log "Configuration interrompue : $($_.Exception.Message)" -Level ERROR
    throw
}
finally {
    if ($serveur) {
        try { $serveur | Disconnect-DbaInstance | Out-Null } catch { }
    }
    Clear-DbaConnectionPool
}
